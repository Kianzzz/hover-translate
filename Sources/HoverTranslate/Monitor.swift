import AppKit
import Combine

@MainActor
final class HoverMonitor {
    struct Candidate {
        let region: CGRect
        let demo: Bool
    }

    struct SelectionToolbarState {
        let pid: pid_t
        let appName: String?
        let anchor: CGRect
        let pointer: CGPoint
        let preloaded: SelectedCapture?
        let createdAt: Date
    }

    enum ToolbarAction { case translate, copy, save }

    let model: AppModel
    var visibleCardFrame: (() -> CGRect?)?
    var visibleToolbarFrame: (() -> CGRect?)?
    private var candidate: Candidate?
    private var toolbarState: SelectionToolbarState?
    private var outsideSince: Date?
    nonisolated(unsafe) private var timer: Timer?
    nonisolated(unsafe) private var globalEvents: Any?
    nonisolated(unsafe) private var localEvents: Any?
    private var lastPoint = CGPoint.zero
    private var stableSince = Date()
    private var attempted = false
    private var captureTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var toolbarTask: Task<Void, Never>?
    private var previousEnabled = false
    private var revision = 0
    private var lastPermissionRefresh = Date.distantPast
    private var previousCaptureAccess = ""
    private var mouseDownPoint: CGPoint?
    private var mouseDownWindow: (id: CGWindowID, frame: CGRect)?
    private var enabledSubscription: AnyCancellable?
    private var wasPrimaryButtonDown = false
    private var pollPressStart: CGPoint?
    private var pollPressWindow: (id: CGWindowID, frame: CGRect)?
    private var lastGlobalMouseUpAt = Date.distantPast

    init(model: AppModel) { self.model = model }

    deinit {
        timer?.invalidate()
        if let globalEvents { NSEvent.removeMonitor(globalEvents) }
        if let localEvents { NSEvent.removeMonitor(localEvents) }
    }

    var desktopTop: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    func start() {
        // Polling only runs while something needs it; see updatePolling().
        enabledSubscription = model.$enabled.dropFirst().sink { [weak self] enabled in
            guard enabled else { return }
            MainActor.assumeIsolated { self?.startPolling() }
        }
        updatePolling()
        globalEvents = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]) { [weak self] event in
            // Read pointer and click details now; the hop below runs later.
            let location = NSEvent.mouseLocation
            let type = event.type
            let keyCode = type == .keyDown ? event.keyCode : 0
            let clickCount = type == .leftMouseUp ? event.clickCount : 0
            let extending = event.modifierFlags.contains(.shift)
            Task { @MainActor in
                guard let self else { return }
                // The app's own normal paste or transient copy emits key events in the destination.
                if self.model.isReplacing { return }
                let active = self.model.enabled || self.model.isPresenting || self.candidate != nil
                    || self.toolbarState != nil || self.visibleCardFrame?() != nil
                guard active else { return }
                if type == .keyDown {
                    if keyCode == 53 { self.selectionTask?.cancel() }
                    self.clearToolbar()
                    if self.model.isPresenting || self.candidate != nil {
                        self.model.dismiss(force: keyCode == 53)
                    }
                    self.resetMotion(at: location)
                    self.attempted = true
                    return
                }
                if type == .leftMouseDown {
                    self.mouseDownPoint = location
                    let quartz = TextLogic.quartzPoint(location, desktopTop: self.desktopTop)
                    self.mouseDownWindow = self.windowAt(quartz: quartz)
                    self.clearToolbar()
                    self.selectionTask?.cancel()
                    if self.model.isPresenting || self.candidate != nil {
                        self.model.dismiss()
                    }
                    self.resetMotion(at: location)
                    return
                }
                if type == .leftMouseUp {
                    self.lastGlobalMouseUpAt = Date()
                    let downPoint = self.mouseDownPoint ?? self.pollPressStart
                    let downWindow = self.mouseDownWindow ?? self.pollPressWindow
                    self.mouseDownPoint = nil
                    self.mouseDownWindow = nil
                    self.pollPressStart = nil
                    self.pollPressWindow = nil
                    let selected = TextLogic.isSelectionGesture(
                        from: downPoint, to: location, clickCount: clickCount, extending: extending)
                    let windowMoved = self.didWindowMove(downWindow)
                    self.selectionTask?.cancel()
                    if selected && !windowMoved && self.model.enabled && self.model.selectionToolbarEnabled
                        && !self.model.capturingRegion && !self.model.pinned {
                        if self.model.isPresenting || self.candidate != nil {
                            self.model.dismiss()
                        }
                        self.resetMotion(at: location)
                        self.attempted = true
                        self.scheduleSelectionToolbar(at: location)
                        return
                    }
                    self.clearToolbar()
                    if self.model.isPresenting || self.candidate != nil {
                        self.model.dismiss()
                    }
                    self.resetMotion(at: location)
                    self.attempted = selected
                    return
                }
                self.selectionTask?.cancel()
                self.clearToolbar()
                if self.model.isPresenting || self.candidate != nil {
                    self.model.dismiss()
                }
                self.resetMotion(at: location)
                self.attempted = type == .rightMouseDown
            }
        }
        localEvents = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown, .leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown && event.keyCode == 53 {
                if self.toolbarState != nil {
                    self.clearToolbar()
                    return nil
                }
                if self.model.isPresenting || self.candidate != nil {
                    self.model.dismiss(force: true)
                    return nil
                }
                return event
            }
            if event.type == .leftMouseDown {
                if self.model.pointerInToolbar?() == true { return event }
                self.mouseDownPoint = NSEvent.mouseLocation
                if self.toolbarState != nil { self.clearToolbar() }
                if (self.model.isPresenting || self.candidate != nil) && self.model.pointerInCard?() != true {
                    self.model.dismiss()
                }
                return event
            }
            if event.type == .leftMouseUp {
                let loc = NSEvent.mouseLocation
                let down = self.mouseDownPoint
                self.mouseDownPoint = nil
                if self.model.pointerInToolbar?() != true && self.model.pointerInCard?() != true,
                   self.model.selectionToolbarEnabled && !self.model.pinned && !self.model.capturingRegion,
                   TextLogic.isSelectionGesture(from: down, to: loc, clickCount: event.clickCount, extending: event.modifierFlags.contains(.shift)) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                        self?.showLocalSelectionToolbarIfSelected(at: loc)
                    }
                }
                return event
            }
            if event.type == .scrollWheel {
                if self.toolbarState != nil && self.model.pointerInToolbar?() != true {
                    self.clearToolbar()
                }
                if (self.model.isPresenting || self.candidate != nil) && self.model.pointerInCard?() != true && self.model.pointerInToolbar?() != true {
                    self.model.dismiss()
                }
            }
            return event
        }
    }

    private func showLocalSelectionToolbarIfSelected(at pointer: CGPoint) {
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        let range = tv.selectedRange()
        guard range.length > 0, range.location != NSNotFound else { return }
        let raw = (tv.string as NSString).substring(with: range)
        let cleaned = TextLogic.clean(raw)
        guard !cleaned.isEmpty else { return }
        let capture = SelectedCapture(
            text: CapturedText(text: cleaned, bounds: .zero, method: "选中文字"),
            replacement: nil
        )
        toolbarState = SelectionToolbarState(
            pid: ProcessInfo.processInfo.processIdentifier,
            appName: "浮译",
            anchor: CGRect(origin: pointer, size: CGSize(width: 1, height: 1)),
            pointer: pointer,
            preloaded: capture,
            createdAt: Date()
        )
        startPolling()
        model.showSelectionToolbar?(CGRect(origin: pointer, size: CGSize(width: 1, height: 1)))
    }

    /// The 25 Hz pointer poll is needed only while translation is on or a
    /// toolbar/card is on screen; a paused app must not keep waking the CPU.
    var pollingNeeded: Bool { model.enabled || candidate != nil || toolbarState != nil || visibleCardFrame?() != nil }
    var isPolling: Bool { timer != nil }

    func startPolling() {
        guard timer == nil else { return }
        resetMotion(at: NSEvent.mouseLocation)
        let polling = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer = polling
        RunLoop.main.add(polling, forMode: .common)
    }

    func updatePolling() {
        if pollingNeeded { startPolling() }
        else { timer?.invalidate(); timer = nil }
    }

    func clearCandidate() {
        captureTask?.cancel()
        revision += 1
        candidate = nil
        outsideSince = nil
    }

    func clearToolbar() {
        toolbarTask?.cancel()
        toolbarTask = nil
        if toolbarState != nil {
            toolbarState = nil
            model.hideSelectionToolbar?()
        }
    }

    private func scheduleSelectionToolbar(at pointer: CGPoint) {
        toolbarTask?.cancel()
        toolbarTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 65_000_000)
            guard let self, !Task.isCancelled else { return }
            guard NSEvent.pressedMouseButtons == 0,
                  self.model.enabled, self.model.selectionToolbarEnabled,
                  !self.model.pinned, !self.model.capturingRegion else { return }
            guard let front = NSWorkspace.shared.frontmostApplication,
                  front.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                self.attempted = false; self.stableSince = Date(); return
            }
            let pid = front.processIdentifier
            let quartz = TextLogic.quartzPoint(pointer, desktopTop: self.desktopTop)
            let context = TextCapture.selectionContext(at: quartz, pid: pid)
            guard context.allowed, !context.protected else {
                self.attempted = false; self.stableSince = Date(); return
            }

            var preloaded: SelectedCapture?
            if self.model.accessibility {
                do {
                    preloaded = try await TextCapture.selected(pid: pid, fallbackPoint: quartz, timeout: 0.12)
                } catch CaptureError.protectedText {
                    self.attempted = false; self.stableSince = Date(); return
                } catch {
                    preloaded = nil
                }
            }
            guard !Task.isCancelled,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  self.model.enabled, self.model.selectionToolbarEnabled,
                  !self.model.pinned, !self.model.capturingRegion else { return }

            let anchor: CGRect
            if let preloaded, !preloaded.text.bounds.isEmpty {
                anchor = TextLogic.cocoaRect(preloaded.text.bounds, desktopTop: self.desktopTop)
            } else {
                anchor = CGRect(origin: pointer, size: CGSize(width: 1, height: 1))
            }
            self.toolbarState = SelectionToolbarState(
                pid: pid,
                appName: front.localizedName,
                anchor: anchor,
                pointer: pointer,
                preloaded: preloaded,
                createdAt: Date()
            )
            self.startPolling()
            self.model.showSelectionToolbar?(CGRect(origin: pointer, size: CGSize(width: 1, height: 1)))
        }
    }

    func performToolbarAction(_ action: ToolbarAction) {
        guard let state = toolbarState else { return }
        clearToolbar()
        selectionTask?.cancel()
        captureTask?.cancel()
        revision += 1
        attempted = true
        selectionTask = Task { [weak self] in
            guard let self else { return }
            var text: String?
            var replacement: ReplacementTarget?
            var anchor = state.anchor
            if let preloaded = state.preloaded {
                text = preloaded.text.text
                replacement = preloaded.replacement
            } else {
                // Tier 2 fallback: transiently copy selection from Chromium/Electron/PDF/Terminal apps.
                text = await TextCapture.copySelectionViaClipboard(pid: state.pid, keepOnClipboard: action == .copy)
                anchor = CGRect(origin: state.pointer, size: CGSize(width: 8, height: 18))
            }
            guard !Task.isCancelled else { return }
            guard let resolved = text, !resolved.isEmpty else {
                self.model.flashToast("未检测到选中文字", at: state.pointer)
                return
            }
            switch action {
            case .translate:
                self.model.present(
                    CapturedText(text: resolved, bounds: .zero, method: "选中文字"),
                    cocoaAnchor: anchor,
                    selection: true,
                    replacement: replacement,
                    appName: state.appName
                )
            case .copy:
                if state.preloaded != nil {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(resolved, forType: .string)
                }
                self.model.flashToast("已复制", at: state.pointer)
            case .save:
                let lang = TextLogic.language(of: resolved, japaneseKanji: self.model.japaneseKanji)
                self.model.saveSnippet(text: resolved, sourceLanguage: lang, appName: state.appName)
                self.model.flashToast("已保存到摘录本", at: state.pointer)
            }
        }
    }

    func stage(_ capture: CapturedText, sourceRect: CGRect, pointer: CGPoint, demo: Bool = false) {
        guard !model.pinned else { return }
        clearToolbar()
        // Ensure single-character AX bounds still provide a comfortable hover zone.
        let vicinity = CGRect(x: pointer.x - 32, y: pointer.y - 12, width: 64, height: 24)
        let region: CGRect
        if sourceRect.contains(pointer) && (demo || sourceRect.height <= 44) {
            region = sourceRect.width < 64 || sourceRect.height < 22 ? sourceRect.union(vicinity) : sourceRect
        } else {
            region = vicinity
        }
        candidate = Candidate(region: region.insetBy(dx: -4, dy: -3), demo: demo)
        outsideSince = nil
        startPolling()
        model.present(capture, cocoaAnchor: CGRect(x: pointer.x, y: region.minY, width: 1, height: region.height), selection: false)
    }

    private func resetMotion(at point: CGPoint) {
        captureTask?.cancel()
        captureTask = nil
        revision += 1
        lastPoint = point
        stableSince = Date()
        attempted = false
    }

    func retainCandidate(at point: CGPoint, now: Date = Date()) -> Bool {
        guard let candidate else { return false }
        if !candidate.demo && (!model.enabled || !model.hoverEnabled) {
            model.dismiss(force: true)
            resetMotion(at: point)
            return false
        }
        if candidate.region.contains(point) { outsideSince = nil; return true }
        let left = outsideSince ?? now
        outsideSince = left
        if now.timeIntervalSince(left) < model.closeDelay { return true }
        model.dismiss()
        resetMotion(at: point)
        return false
    }

    private func retainToolbar(at point: CGPoint, now: Date) -> Bool {
        guard let state = toolbarState else { return false }
        if let frame = visibleToolbarFrame?(), frame.insetBy(dx: -20, dy: -20).contains(point) {
            return true
        }
        let distance = hypot(point.x - state.pointer.x, point.y - state.pointer.y)
        if distance <= 96 && now.timeIntervalSince(state.createdAt) < 3.5 {
            return true
        }
        clearToolbar()
        resetMotion(at: point)
        return false
    }

    private func tick() {
        let now = Date()
        let missingPermission = model.enabled && (!model.accessibility || (model.ocrEnabled && !model.screenPermission))
        let refreshInterval: TimeInterval = NSApp.isActive ? 2 : (missingPermission ? 3 : .infinity)
        if now.timeIntervalSince(lastPermissionRefresh) > refreshInterval {
            model.refreshPermissions()
            lastPermissionRefresh = now
        }
        if model.enabled != previousEnabled {
            resetMotion(at: NSEvent.mouseLocation)
            previousEnabled = model.enabled
        }
        guard pollingNeeded else { updatePolling(); return }
        let access = "\(model.accessibility):\(model.screenPermission):\(model.ocrEnabled):\(model.hoverEnabled)"
        if access != previousCaptureAccess {
            previousCaptureAccess = access
            resetMotion(at: NSEvent.mouseLocation)
        }
        let point = NSEvent.mouseLocation
        // Backup drag detector in case macOS suppresses a global leftMouseDown/Up (e.g., certain trackpad gestures).
        let primaryDown = (NSEvent.pressedMouseButtons & 1) != 0
        if primaryDown && !wasPrimaryButtonDown {
            wasPrimaryButtonDown = true
            pollPressStart = point
            pollPressWindow = windowAt(quartz: TextLogic.quartzPoint(point, desktopTop: desktopTop))
        } else if !primaryDown && wasPrimaryButtonDown {
            wasPrimaryButtonDown = false
            let start = pollPressStart
            let win = pollPressWindow
            pollPressStart = nil
            pollPressWindow = nil
            if now.timeIntervalSince(lastGlobalMouseUpAt) > 0.12,
               let start, hypot(point.x - start.x, point.y - start.y) >= 8,
               !didWindowMove(win),
               model.enabled, model.selectionToolbarEnabled, !model.capturingRegion, !model.pinned,
               NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                resetMotion(at: point)
                attempted = true
                scheduleSelectionToolbar(at: point)
                return
            }
        }
        // A deliberate selection is an action toolbar, not a hover preview.
        // Keep it reachable across any gap until an outside click/scroll or close.
        if model.capturingRegion { return }
        if retainToolbar(at: point, now: now) { return }
        if retainSelection() { return }
        if retainCandidate(at: point, now: now) { return }
        guard model.enabled, !model.pinned else { return }
        if let frame = visibleCardFrame?(), frame.insetBy(dx: -12, dy: -12).contains(point) { return }
        // Tolerate tiny involuntary cursor jitter while an async AX/OCR capture is in flight.
        let jitterLimit: CGFloat = captureTask != nil ? 6 : 3.5
        let moved = hypot(point.x - lastPoint.x, point.y - lastPoint.y) > jitterLimit
        if moved || NSEvent.pressedMouseButtons != 0 {
            resetMotion(at: point)
            if model.isPresenting || candidate != nil { model.dismiss() }
            return
        }
        guard model.hoverEnabled, !attempted, now.timeIntervalSince(stableSince) >= model.delay else { return }
        attempted = true
        guard model.accessibility || (model.ocrEnabled && model.screenPermission) else { return }
        let token = revision
        let quartz = TextLogic.quartzPoint(point, desktopTop: desktopTop)
        if topWindowIsOurs(at: quartz) { return }
        let word = model.wordMode
        captureTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.revision == token { self.captureTask = nil } }
            do {
                var capture: CapturedText?
                if model.accessibility { capture = try await TextCapture.accessible(at: quartz, word: word) }
                guard !Task.isCancelled, token == revision else { return }
                let native = model.nativeLanguage
                let shouldRunOCR: Bool
                if let existing = capture {
                    shouldRunOCR = existing.needsLineCheck
                        && (existing.isContainer || TextLogic.mayContainForeign(existing.text, native: native, japaneseKanji: model.japaneseKanji))
                } else {
                    shouldRunOCR = true
                }
                if shouldRunOCR, model.ocrEnabled, model.screenPermission {
                    // Prefer text at the pointer over a guessed row or paragraph label.
                    // Keep the AX result if Vision cannot resolve the line.
                    if capture == nil { capture = try await TextCapture.ocr(at: quartz, word: word) }
                    else if let line = try? await TextCapture.ocr(at: quartz, word: word) { capture = line }
                }
                guard !Task.isCancelled, token == revision, model.enabled, !model.pinned,
                      let capture, TextLogic.isForeign(capture.text, native: native, japaneseKanji: model.japaneseKanji) else { return }
                stage(capture, sourceRect: TextLogic.cocoaRect(capture.bounds, desktopTop: desktopTop), pointer: point)
            } catch {
                guard !Task.isCancelled, token == revision else { return }
                // Do not OCR or publish changes when the target is our own UI.
                if case CaptureError.ownApplication = error { return }
                if error is CancellationError { return }
                model.status = error.localizedDescription
            }
        }
    }

    func retainSelection() -> Bool {
        model.selectionVisible && visibleCardFrame?() != nil
    }

    private func windowAt(quartz: CGPoint) -> (id: CGWindowID, frame: CGRect)? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let ownPid = ProcessInfo.processInfo.processIdentifier
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int ?? 0) == 0,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  window[kCGWindowOwnerPID as String] as? pid_t != ownPid,
                  let id = window[kCGWindowNumber as String] as? CGWindowID,
                  let raw = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: raw as CFDictionary),
                  rect.width > 50, rect.height > 50,
                  rect.contains(quartz) else { continue }
            return (id, rect)
        }
        return nil
    }

    private func didWindowMove(_ initial: (id: CGWindowID, frame: CGRect)?) -> Bool {
        guard let initial,
              let windows = CGWindowListCopyWindowInfo([.optionIncludingWindow], initial.id) as? [[String: Any]],
              let raw = windows.first?[kCGWindowBounds as String] as? [String: Any],
              let after = CGRect(dictionaryRepresentation: raw as CFDictionary) else { return false }
        return abs(initial.frame.minX - after.minX) > 2
            || abs(initial.frame.minY - after.minY) > 2
            || abs(initial.frame.width - after.width) > 2
            || abs(initial.frame.height - after.height) > 2
    }

    private func topWindowIsOurs(at quartz: CGPoint) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        for window in windows {
            guard (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let raw = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: raw as CFDictionary), rect.contains(quartz) else { continue }
            return window[kCGWindowOwnerPID as String] as? pid_t == ProcessInfo.processInfo.processIdentifier
        }
        return false
    }

    func readSelection() {
        clearToolbar()
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        if front.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            if let tv = NSApp.keyWindow?.firstResponder as? NSTextView {
                let range = tv.selectedRange()
                if range.length > 0, range.location != NSNotFound {
                    let text = (tv.string as NSString).substring(with: range)
                    if !TextLogic.clean(text).isEmpty {
                        model.presentSelection(text, appName: "浮译")
                        return
                    }
                }
            }
            model.flashToast("未检测到选中文字")
            return
        }
        selectionTask?.cancel()
        captureTask?.cancel()
        revision += 1
        attempted = true
        model.dismiss(force: true)
        let pid = front.processIdentifier
        let appName = front.localizedName
        let mouse = NSEvent.mouseLocation
        let point = TextLogic.quartzPoint(mouse, desktopTop: desktopTop)
        selectionTask = Task { [weak self] in
            guard let self else { return }
            guard !Task.isCancelled else { return }
            guard model.accessibility else {
                model.requestAccessibility()
                model.showWindow?()
                attempted = false
                return
            }
            do {
                let capture = try await TextCapture.selected(pid: pid, fallbackPoint: point)
                guard !Task.isCancelled, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                let anchor = TextLogic.cocoaRect(capture.text.bounds, desktopTop: desktopTop)
                model.present(capture.text, cocoaAnchor: anchor, selection: true, replacement: capture.replacement, appName: appName)
            } catch CaptureError.protectedText {
                guard !Task.isCancelled else { return }
                attempted = false
                stableSince = Date()
                model.flashToast("此处是受保护的输入区域，已跳过", at: mouse)
            } catch CaptureError.nothingSelected {
                // Tier 2 fallback: transiently copy from Chromium/Electron/PDF/Terminal apps.
                if let copied = await TextCapture.copySelectionViaClipboard(pid: pid, keepOnClipboard: false),
                   !Task.isCancelled {
                    model.present(
                        CapturedText(text: copied, bounds: .zero, method: "选中文字"),
                        cocoaAnchor: CGRect(origin: mouse, size: CGSize(width: 8, height: 18)),
                        selection: true,
                        appName: appName
                    )
                    return
                }
                guard !Task.isCancelled else { return }
                attempted = false
                stableSince = Date()
                model.flashToast("未检测到选中文字", at: mouse)
            } catch {
                guard !Task.isCancelled else { return }
                attempted = false
                stableSince = Date()
                model.flashToast(error.localizedDescription, at: mouse)
            }
        }
    }
}
