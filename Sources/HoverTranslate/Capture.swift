import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision
import NaturalLanguage
import CoreML
import Carbon

private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
}

private final class OCRJob: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private var active: VNRecognizeTextRequest?
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func track(_ request: VNRecognizeTextRequest) throws {
        lock.lock()
        let alreadyStopped = stopped
        if !alreadyStopped { active = request }
        lock.unlock()
        if alreadyStopped {
            request.cancel()
            throw CancellationError()
        }
    }
    func cancel() {
        lock.lock()
        stopped = true
        let current = active
        lock.unlock()
        current?.cancel()
    }
}

// An immutable AX proxy to another process can cross the capture queue.
// Never permit an in-process AppKit/SwiftUI object into that queue.
private struct ExternalAXElement: @unchecked Sendable {
    let value: AXUIElement
    init(_ element: AXUIElement) throws {
        try TextCapture.requireExternalElement(element)
        value = element
    }
}

enum CaptureError: LocalizedError {
    case protectedText, nothingSelected, noScreenPermission, ownApplication
    var errorDescription: String? {
        switch self {
        case .protectedText: return "此处是受保护的输入区域，已跳过识别。"
        case .nothingSelected: return "当前应用没有提供可读取的选中文字。可以先复制，再用菜单中的“翻译剪贴板”。"
        case .noScreenPermission: return "需要屏幕录制权限才能识别图片中的文字。"
        case .ownApplication: return "已跳过浮译自身的界面。"
        }
    }
}

enum TextCapture {
    /// The fast recognizer covers these Latin-script languages; English keeps priority.
    static let ocrLanguages = ["en-US", "fr-FR", "de-DE", "es-ES", "it-IT", "pt-BR"]
    static let queue = DispatchQueue(label: "io.github.kianzzz.hovertranslate.capture", qos: .userInitiated)
    static let accurateQueue = DispatchQueue(label: "io.github.kianzzz.hovertranslate.multilingual-ocr", qos: .userInitiated)
    static let ocrQueue = DispatchQueue(label: "io.github.kianzzz.hovertranslate.ocr", qos: .userInitiated)

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    @MainActor
    static func elementAt(_ point: CGPoint) -> AXUIElement? {
        // A system-wide hit can resolve into this process. AppKit then invokes
        // our SwiftUI accessibility tree synchronously on the calling thread.
        // It must therefore run on the UI thread, even for a global hover.
        precondition(Thread.isMainThread)
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element) == .success else { return nil }
        if let element { AXUIElementSetMessagingTimeout(element, 0.25) }
        return element
    }

    static func requireExternalElement(_ element: AXUIElement) throws {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              pid > 0, pid != ProcessInfo.processInfo.processIdentifier else {
            throw CaptureError.ownApplication
        }
    }

    static func isProtected(_ element: AXUIElement) -> Bool {
        let subrole = attribute(element, kAXSubroleAttribute) as? String ?? ""
        let protected = attribute(element, "AXProtectedContent") as? Bool ?? false
        return subrole == "AXSecureTextField" || protected
    }

    static func bounds(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        var s = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }

    static func selected(pid: pid_t, fallbackPoint: CGPoint) async throws -> SelectedCapture {
        guard pid != ProcessInfo.processInfo.processIdentifier else { throw CaptureError.ownApplication }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.3)
                guard let ref = attribute(app, kAXFocusedUIElementAttribute), CFGetTypeID(ref) == AXUIElementGetTypeID() else {
                    continuation.resume(throwing: CaptureError.nothingSelected); return
                }
                let focused = ref as! AXUIElement
                AXUIElementSetMessagingTimeout(focused, 0.3)
                if isProtected(focused) { continuation.resume(throwing: CaptureError.protectedText); return }
                guard let raw = readSelectedText(from: focused),
                      !TextLogic.clean(raw).isEmpty else {
                    continuation.resume(throwing: CaptureError.nothingSelected); return
                }
                var rect = CGRect(origin: fallbackPoint, size: CGSize(width: 8, height: 18))
                if let range = attribute(focused, kAXSelectedTextRangeAttribute) {
                    var value: CFTypeRef?
                    if AXUIElementCopyParameterizedAttributeValue(focused, kAXBoundsForRangeParameterizedAttribute as CFString, range, &value) == .success,
                       let value, CFGetTypeID(value) == AXValueGetTypeID() {
                        var selectionBounds = CGRect.zero
                        if AXValueGetValue(value as! AXValue, .cgRect, &selectionBounds), selectionBounds.width > 0 { rect = selectionBounds }
                    }
                }
                let replacement = ReplacementTarget.capture(element: focused, pid: pid, selected: raw)
                continuation.resume(returning: SelectedCapture(
                    text: CapturedText(text: TextLogic.clean(raw), bounds: rect, method: "选中文字"),
                    replacement: replacement))
            }
        }
    }

    private static func readSelectedText(from element: AXUIElement) -> String? {
        if let direct = attribute(element, kAXSelectedTextAttribute) as? String, !TextLogic.clean(direct).isEmpty {
            return direct
        }
        // Tier 1B: range + StringForRange / AXValue substring.
        if let rangeRef = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(rangeRef) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(rangeRef as! AXValue, .cfRange, &range), range.length > 0 {
                var strRef: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, rangeRef, &strRef) == .success,
                   let str = strRef as? String, !TextLogic.clean(str).isEmpty {
                    return str
                }
                if let value = attribute(element, kAXValueAttribute) as? String {
                    let ns = value as NSString
                    if range.location >= 0, range.location <= ns.length, range.length <= ns.length - range.location {
                        let slice = ns.substring(with: NSRange(location: range.location, length: range.length))
                        if !TextLogic.clean(slice).isEmpty { return slice }
                    }
                }
            }
        }
        // Tier 1C: WebKit / Chromium / Electron text marker ranges.
        if let markerRange = attribute(element, "AXSelectedTextMarkerRange") {
            var strRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, "AXStringForTextMarkerRange" as CFString, markerRange, &strRef) == .success,
               let str = strRef as? String, !TextLogic.clean(str).isEmpty {
                return str
            }
        }
        return nil
    }

    /// Quick UI-control filter so window drags, scrollbars, and sliders do not summon the selection toolbar.
    @MainActor
    static func selectionContext(at quartzPoint: CGPoint, pid: pid_t) -> (allowed: Bool, protected: Bool) {
        guard pid != ProcessInfo.processInfo.processIdentifier else { return (false, false) }
        guard let hit = elementAt(quartzPoint) else { return (true, false) }
        if (try? requireExternalElement(hit)) == nil { return (false, false) }
        if isProtected(hit) { return (false, true) }
        let role = attribute(hit, kAXRoleAttribute) as? String ?? ""
        let ignoredRoles: Set<String> = [
            "AXScrollBar", "AXValueIndicator", "AXSlider", "AXSplitter", "AXGrowArea",
            "AXToolbar", "AXToolbarButton", "AXCloseButton", "AXZoomButton", "AXMinimizeButton",
            "AXFullScreenButton", "AXMenuBar", "AXMenuBarItem", "AXDockItem", "AXTabGroup"
        ]
        if ignoredRoles.contains(role) { return (false, false) }
        return (true, false)
    }

    /// Tier 2 fallback: on explicit user action, transiently issue ⌘C to read selections
    /// from Chromium/Electron/PDF/Terminal apps that omit AXSelectedText, then restore the clipboard.
    @MainActor
    static func copySelectionViaClipboard(pid: pid_t, keepOnClipboard: Bool = false) async -> String? {
        guard pid != ProcessInfo.processInfo.processIdentifier,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return nil }
        // Never simulate ⌘C in a protected password field.
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        if let ref = attribute(app, kAXFocusedUIElementAttribute), CFGetTypeID(ref) == AXUIElementGetTypeID() {
            let focused = ref as! AXUIElement
            AXUIElementSetMessagingTimeout(focused, 0.15)
            if isProtected(focused) { return nil }
        }
        let key = KeyboardLayout.keyCode(for: "c") ?? CGKeyCode(kVK_ANSI_C)
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return nil }

        let board = NSPasteboard.general
        let savedItems = keepOnClipboard ? [] : PasteboardLease.snapshot(board)
        let beforeCount = board.changeCount

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(pid)
        up.postToPid(pid)

        let deadline = Date().addingTimeInterval(0.24)
        while board.changeCount == beforeCount && Date() < deadline {
            try? await Task.sleep(nanoseconds: 15_000_000)
            if Task.isCancelled { break }
        }
        guard board.changeCount != beforeCount else { return nil }
        let copiedCount = board.changeCount
        let text = board.string(forType: .string).map(TextLogic.clean)
        if !keepOnClipboard && board.changeCount == copiedCount {
            board.clearContents()
            if !savedItems.isEmpty { board.writeObjects(savedItems) }
        }
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    @MainActor
    static func accessible(at point: CGPoint, word: Bool) async throws -> CapturedText? {
        try Task.checkCancellation()
        guard let hit = elementAt(point) else { return nil }
        let remote = try ExternalAXElement(hit)
        try Task.checkCancellation()
        let flag = CancellationFlag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CapturedText?, Error>) in
                queue.async {
                    guard !flag.cancelled else { continuation.resume(throwing: CancellationError()); return }
                    let hit = remote.value
                    var elements = [hit]
                    var parent = hit
                    for _ in 0..<3 {
                        guard !flag.cancelled else { continuation.resume(throwing: CancellationError()); return }
                        guard let ref = attribute(parent, kAXParentAttribute), CFGetTypeID(ref) == AXUIElementGetTypeID() else { break }
                        parent = ref as! AXUIElement
                        AXUIElementSetMessagingTimeout(parent, 0.2)
                        elements.append(parent)
                    }
                    // Check the ancestry before falling back to visible pixels.
                    if elements.contains(where: isProtected) { continuation.resume(throwing: CaptureError.protectedText); return }
                    let compactRoles: Set<String> = ["AXStaticText", "AXButton", "AXMenuItem", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXHeading", "AXTextField", "AXCell", "AXTab", "AXRow", "AXImage", "AXToolbarButton", "AXMenuBarItem", "AXDisclosureTriangle", "AXSegmentedControl", "AXSwitch"]
                    var fallback: CapturedText?
                    for (index, element) in elements.enumerated() {
                        guard !flag.cancelled else { continuation.resume(throwing: CancellationError()); return }
                        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
                        if role == "AXWindow" || role == "AXApplication" { break }
                        let valueText = attribute(element, kAXValueAttribute) as? String
                        let candidates: [(String?, Bool)] = [
                            (valueText, true),
                            (attribute(element, kAXTitleAttribute) as? String, false),
                            (attribute(element, kAXDescriptionAttribute) as? String, false),
                            (attribute(element, kAXHelpAttribute) as? String, false)
                        ]
                        guard let matched = candidates.compactMap({ text, isValue in
                            guard let text, !TextLogic.clean(text).isEmpty else { return nil as (String, Bool)? }
                            return (text, isValue)
                        }).first else { continue }
                        let raw = matched.0
                        let fromValue = matched.1
                        let text = TextLogic.clean(raw)
                        guard let rect = bounds(element), rect.insetBy(dx: -4, dy: -4).contains(point) else { continue }
                        // kAXRangeForPositionParameterizedAttribute indexes into AXValue, never AXTitle/AXDescription.
                        if fromValue {
                            var pointCopy = point
                            if let pointValue = AXValueCreate(.cgPoint, &pointCopy) {
                                var rangeRef: CFTypeRef?
                                if AXUIElementCopyParameterizedAttributeValue(element, kAXRangeForPositionParameterizedAttribute as CFString, pointValue, &rangeRef) == .success,
                                   let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() {
                                    var range = CFRange()
                                    var boxRef: CFTypeRef?
                                    var charBounds = CGRect.zero
                                    let hasBounds = AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeRef, &boxRef) == .success
                                    if let boxRef, CFGetTypeID(boxRef) == AXValueGetTypeID() { _ = AXValueGetValue(boxRef as! AXValue, .cgRect, &charBounds) }
                                    if hasBounds, charBounds.height > 0, charBounds.insetBy(dx: -6, dy: -5).contains(point),
                                       AXValueGetValue(rangeRef as! AXValue, .cfRange, &range),
                                       let result = TextLogic.segment(raw, utf16Offset: range.location, word: word) {
                                        continuation.resume(returning: CapturedText(text: result, bounds: charBounds, method: "系统取词")); return
                                    }
                                }
                            }
                        }
                        // UI controls, system menus and labels often expose a title or description,
                        // not a text value. Large document containers still go through local OCR.
                        let compact = rect.height <= 240 && text.count <= 4000 && text.components(separatedBy: .newlines).count <= 12
                        if compact && compactRoles.contains(role) {
                            if !word || text.split(whereSeparator: { $0.isWhitespace }).count == 1 {
                                // Preserve complete static paragraphs when AX exposes no character
                                // position; controls keep their own labels as before.
                                if fallback == nil {
                                    let container = ["AXRow", "AXCell", "AXImage"].contains(role)
                                    fallback = CapturedText(text: text, bounds: rect, method: "系统取词 · 文字块 / 控件",
                                                            needsLineCheck: index > 0 || container || rect.height > 40,
                                                            isContainer: index > 0 || container)
                                }
                            }
                        }
                    }
                    continuation.resume(returning: fallback)
                }
            }
        } onCancel: {
            flag.cancel()
        }
    }

    static func ocr(at point: CGPoint, word: Bool) async throws -> CapturedText? {
        try Task.checkCancellation()
        guard CGPreflightScreenCaptureAccess() else { throw CaptureError.noScreenPermission }
        var displayID: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &displayID, &count) == .success, count > 0 else { return nil }
        let display = CGDisplayBounds(displayID)
        let width = min(1400, display.width), height = min(720, display.height)
        let crop = CGRect(x: min(max(point.x - width / 2, display.minX), display.maxX - width),
                          y: min(max(point.y - height / 2, display.minY), display.maxY - height),
                          width: width, height: height)
        let image = try await SCScreenshotManager.captureImage(in: crop)
        try Task.checkCancellation()
        return try await hoverText(image: image, region: crop, at: point, word: word)
    }

    static func hoverText(image: CGImage, region: CGRect, at point: CGPoint, word: Bool) async throws -> CapturedText? {
        // Accurate multilingual OCR already supersedes fast Latin-only OCR; running a
        // second full-crop fast pass on blank space only wastes CPU/battery.
        try await recognize(image: image, region: region, at: point, word: word, accurate: true)
    }

    static func accurateLanguages(_ request: VNRecognizeTextRequest) throws -> [String] {
        let supported = try request.supportedRecognitionLanguages()
        return (["ja-JP", "ko-KR", "zh-Hans", "zh-Hant", "en-US"] + ocrLanguages.dropFirst()).filter { supported.contains($0) }
    }

    static func recognize(image: CGImage, region crop: CGRect, at point: CGPoint, word: Bool, accurate: Bool = false) async throws -> CapturedText? {
        let job = OCRJob()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CapturedText?, Error>) in
            (accurate ? accurateQueue : ocrQueue).async {
                do {
                    if job.cancelled { throw CancellationError() }
                    let request = VNRecognizeTextRequest()
                    try job.track(request)
                    // Let Vision use hardware acceleration (ANE/GPU) for accurate recognition;
                    // only pin fast recognition to CPU if requested.
                    if !accurate, let cpu = MLComputeDevice.allComputeDevices.first(where: { if case .cpu = $0 { return true }; return false }) {
                        request.setComputeDevice(cpu, for: .main)
                    }
                    request.recognitionLanguages = TextCapture.ocrLanguages
                    request.minimumTextHeight = Float(min(0.02, 6 / max(1, crop.height)))
                    request.recognitionLevel = accurate ? .accurate : .fast
                    request.automaticallyDetectsLanguage = accurate
                    if accurate { request.recognitionLanguages = try accurateLanguages(request) }
                    request.usesLanguageCorrection = true
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    if job.cancelled { throw CancellationError() }
                    let lines: [(String, CGRect, VNRecognizedText)] = (request.results ?? []).compactMap { observation in
                        guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.35 else { return nil }
                        let b = observation.boundingBox
                        let box = CGRect(x: crop.minX + b.minX * crop.width,
                                         y: crop.minY + (1 - b.maxY) * crop.height,
                                         width: b.width * crop.width, height: b.height * crop.height)
                        return (candidate.string, box, candidate)
                    }
                    // Hit-test the actual text line. Blank space must not pick the nearest paragraph.
                    guard let hitEntry = lines.enumerated()
                        .filter({ $0.element.1.insetBy(dx: -max(4, $0.element.1.height), dy: -4).contains(point) })
                        .min(by: { abs($0.element.1.midY - point.y) < abs($1.element.1.midY - point.y) }) else {
                        continuation.resume(returning: nil); return
                    }
                    let originalHit = hitEntry.offset
                    var hit = hitEntry.element
                    var hitRegion = crop
                    // Re-read just this line when fast mode or short/low-confidence labels
                    // might have dropped an edge character next to a UI icon.
                    let needsRefinement = !accurate || hit.0.count <= 24 || hit.2.confidence < 0.75
                    let lineRegion = hit.1.insetBy(dx: -max(32, hit.1.height * 1.25), dy: -12).intersection(crop)
                    let scaleX = CGFloat(image.width) / crop.width
                    let scaleY = CGFloat(image.height) / crop.height
                    let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
                    let pixels = CGRect(x: (lineRegion.minX - crop.minX) * scaleX,
                                        y: (lineRegion.minY - crop.minY) * scaleY,
                                        width: lineRegion.width * scaleX, height: lineRegion.height * scaleY)
                        .integral.intersection(imageBounds)
                    if needsRefinement, !pixels.isEmpty, let lineImage = image.cropping(to: pixels) {
                        let refinement = VNRecognizeTextRequest()
                        try job.track(refinement)
                        refinement.recognitionLevel = accurate ? .accurate : .fast
                        refinement.automaticallyDetectsLanguage = accurate
                        refinement.recognitionLanguages = request.recognitionLanguages
                        refinement.usesLanguageCorrection = true
                        if !accurate, let cpu = MLComputeDevice.allComputeDevices.first(where: { if case .cpu = $0 { return true }; return false }) {
                            refinement.setComputeDevice(cpu, for: .main)
                        }
                        try VNImageRequestHandler(cgImage: lineImage).perform([refinement])
                        if job.cancelled { throw CancellationError() }
                        let refinedRegion = CGRect(x: crop.minX + pixels.minX / scaleX, y: crop.minY + pixels.minY / scaleY,
                                                   width: CGFloat(lineImage.width) / scaleX, height: CGFloat(lineImage.height) / scaleY)
                        let refinements = (refinement.results ?? []).compactMap { observation -> (String, CGRect, VNRecognizedText)? in
                            guard let text = observation.topCandidates(1).first, text.confidence >= 0.35 else { return nil }
                            let b = observation.boundingBox
                            let box = CGRect(x: refinedRegion.minX + b.minX * refinedRegion.width,
                                             y: refinedRegion.minY + (1 - b.maxY) * refinedRegion.height,
                                             width: b.width * refinedRegion.width, height: b.height * refinedRegion.height)
                            return box.insetBy(dx: -4, dy: -4).contains(point) ? (text.string, box, text) : nil
                        }
                        if let refined = refinements.min(by: { abs($0.1.midY - point.y) < abs($1.1.midY - point.y) }) {
                            hit = refined
                            hitRegion = refinedRegion
                        }
                    }
                    guard hit.1.insetBy(dx: -4, dy: -4).contains(point) else {
                        continuation.resume(returning: nil); return
                    }
                    if word {
                        let tokenizer = NLTokenizer(unit: .word)
                        tokenizer.string = hit.0
                        var found: CapturedText?
                        tokenizer.enumerateTokens(in: hit.0.startIndex..<hit.0.endIndex) { range, _ in
                            if let b = try? hit.2.boundingBox(for: range)?.boundingBox {
                                let box = CGRect(x: hitRegion.minX + b.minX * hitRegion.width, y: hitRegion.minY + (1-b.maxY) * hitRegion.height,
                                                 width: b.width * hitRegion.width, height: b.height * hitRegion.height)
                                if box.insetBy(dx: -3, dy: -3).contains(point) { found = CapturedText(text: String(hit.0[range]), bounds: box, method: "本机 OCR"); return false }
                            }
                            return true
                        }
                        continuation.resume(returning: found); return
                    }
                    // Locate the hovered word within the line so a line containing
                    // the end of one sentence and start of another picks the right one.
                    var offset = min(max(0, Int((point.x - hit.1.minX) / max(1, hit.1.width) * CGFloat(hit.0.utf16.count))), max(0, hit.0.utf16.count - 1))
                    let tokenizer = NLTokenizer(unit: .word)
                    tokenizer.string = hit.0
                    tokenizer.enumerateTokens(in: hit.0.startIndex..<hit.0.endIndex) { range, _ in
                        if let b = try? hit.2.boundingBox(for: range)?.boundingBox {
                            let box = CGRect(x: hitRegion.minX + b.minX * hitRegion.width,
                                             y: hitRegion.minY + (1 - b.maxY) * hitRegion.height,
                                             width: b.width * hitRegion.width, height: b.height * hitRegion.height)
                            if box.insetBy(dx: -3, dy: -3).contains(point) {
                                offset = NSRange(range, in: hit.0).location; return false
                            }
                        }
                        return true
                    }
                    var context = lines.map { TextLogic.OCRLine(text: $0.0, bounds: $0.1) }
                    context[originalHit] = TextLogic.OCRLine(text: hit.0, bounds: hit.1)
                    let sentence = TextLogic.ocrSentence(lines: context, hit: originalHit, offset: offset)
                    continuation.resume(returning: sentence.map { CapturedText(text: $0, bounds: hit.1, method: "本机 OCR · 句子 / 段落") })
                } catch { continuation.resume(throwing: error) }
            }
            }
        } onCancel: {
            job.cancel()
        }
    }
}
