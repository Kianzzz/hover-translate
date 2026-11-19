import AppKit
import Combine

@MainActor
final class HoverMonitor {
    struct Candidate {
        let region: CGRect
        let demo: Bool
    }

    let model: AppModel
    var visibleCardFrame: (() -> CGRect?)?
    private var candidate: Candidate?
    private var outsideSince: Date?
    private var timer: Timer?
    private var globalEvents: Any?
    private var localScrollEvents: Any?
    private var lastPoint = CGPoint.zero
    private var stableSince = Date()
    private var attempted = false
    private var captureTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var previousEnabled = false
    private var revision = 0
    private var lastPermissionRefresh = Date.distantPast
    private var previousCaptureAccess = ""
    private var mouseDownPoint: CGPoint?
    private var enabledSubscription: AnyCancellable?

    init(model: AppModel) { self.model = model }
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
            let clickCount = event.type == .leftMouseUp ? event.clickCount : 0
            let extending = event.modifierFlags.contains(.shift)
            Task { @MainActor in
                guard let self else { return }
                // The app's own normal paste emits key events in the destination.
                if self.model.isReplacing { return }
                if event.type == .keyDown {
                    if event.keyCode == 53 { self.selectionTask?.cancel() }
                    self.model.dismiss(force: event.keyCode == 53)
                    self.resetMotion(at: location)
                    self.attempted = true
                    return
                }
                if event.type == .leftMouseDown { self.mouseDownPoint = location }
                let selected = event.type == .leftMouseUp && TextLogic.isSelectionGesture(
                    from: self.mouseDownPoint, to: location, clickCount: clickCount, extending: extending)
                self.selectionTask?.cancel()
                self.model.dismiss()
                self.resetMotion(at: location)
                self.attempted = selected || event.type == .rightMouseDown
            }
        }
        localScrollEvents = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            Task { @MainActor in
                guard let self, self.model.pointerInCard?() != true else { return }
                self.model.dismiss()
            }
            return event
        }
    }

    /// The 25 Hz pointer poll is needed only while translation is on or a
    /// badge/card is on screen; a paused app must not keep waking the CPU.
    var pollingNeeded: Bool { model.enabled || candidate != nil || visibleCardFrame?() != nil }
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

    func stage(_ capture: CapturedText, sourceRect: CGRect, pointer: CGPoint, demo: Bool = false) {
        guard !model.pinned else { return }
        let vicinity = CGRect(x: pointer.x - 24, y: pointer.y - 8, width: 48, height: 16)
        let region = sourceRect.contains(pointer) && sourceRect.height <= 44 ? sourceRect : vicinity
        candidate = Candidate(region: region.insetBy(dx: -3, dy: -2), demo: demo)
        outsideSince = nil
        startPolling()
        model.present(capture, cocoaAnchor: CGRect(x: pointer.x, y: region.minY, width: 1, height: region.height), selection: false)
    }

    private func resetMotion(at point: CGPoint) {
        captureTask?.cancel()
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

    private func tick() {
        // Refresh on return to the app, without repeatedly querying TCC while
        // the user is editing permissions in System Settings.
        if NSApp.isActive && Date().timeIntervalSince(lastPermissionRefresh) > 2 {
            model.refreshPermissions()
            lastPermissionRefresh = Date()
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
        // A deliberate selection is an action toolbar, not a hover preview.
        // Keep it reachable across any gap until an outside click/scroll or close.
        if model.capturingRegion { return }
        if retainSelection() { return }
        if retainCandidate(at: point) { return }
        guard model.enabled, !model.pinned else { return }
        if let frame = visibleCardFrame?(), frame.insetBy(dx: -12, dy: -12).contains(point) { return }
        let moved = hypot(point.x - lastPoint.x, point.y - lastPoint.y) > 3
        if moved || NSEvent.pressedMouseButtons != 0 {
            resetMotion(at: point)
            model.dismiss()
            return
        }
        guard model.hoverEnabled, !attempted, Date().timeIntervalSince(stableSince) >= model.delay else { return }
        attempted = true
        guard model.accessibility || (model.ocrEnabled && model.screenPermission) else { return }
        let token = revision
        let quartz = TextLogic.quartzPoint(point, desktopTop: desktopTop)
        if topWindowIsOurs(at: quartz) { return }
        let word = model.wordMode
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                var capture: CapturedText?
                if model.accessibility { capture = try await TextCapture.accessible(at: quartz, word: word) }
                guard !Task.isCancelled, token == revision else { return }
                let native = model.nativeLanguage
                if capture == nil || capture?.needsLineCheck == true, model.ocrEnabled, model.screenPermission {
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
                model.status = error.localizedDescription
            }
        }
    }

    func retainSelection() -> Bool {
        model.selectionVisible && visibleCardFrame?() != nil
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
        guard !model.pinned, let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        selectionTask?.cancel()
        captureTask?.cancel()
        revision += 1
        attempted = true
        model.dismiss()
        let pid = front.processIdentifier
        let point = TextLogic.quartzPoint(NSEvent.mouseLocation, desktopTop: desktopTop)
        selectionTask = Task { [weak self] in
            guard let self else { return }
            guard !Task.isCancelled else { return }
            guard model.accessibility else {
                model.requestAccessibility()
                attempted = false
                return
            }
            do {
                let capture = try await TextCapture.selected(pid: pid, fallbackPoint: point)
                guard !Task.isCancelled, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                let anchor = TextLogic.cocoaRect(capture.text.bounds, desktopTop: desktopTop)
                model.present(capture.text, cocoaAnchor: anchor, selection: true, replacement: capture.replacement)
            } catch {
                guard !Task.isCancelled else { return }
                attempted = false
                stableSince = Date()
                model.status = error.localizedDescription; model.showWindow?()
            }
        }
    }
}
