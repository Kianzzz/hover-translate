import AppKit

@MainActor
final class HoverMonitor {
    struct Candidate {
        let capture: CapturedText
        let sourceRect: CGRect
        let badgeRect: CGRect
        let origin: CGPoint
        var previousPoint: CGPoint
        var approachUntil = Date.distantPast
        let demo: Bool
        /// A selection badge waits for an outside click, scroll or key instead of pointer movement.
        var selection = false
        var replacement: ReplacementTarget?
        var opened = false
        var enteredCard = false
    }

    let model: AppModel
    var visibleCardFrame: (() -> CGRect?)?
    var showBadge: ((CGPoint, CGRect) -> CGRect)?
    var hideBadge: (() -> Void)?
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
    private var lifecycle = CaptureLifecycle()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var displayObserver: NSObjectProtocol?
    var captureReady: Bool { lifecycle.isReady(at: ProcessInfo.processInfo.systemUptime) }

    init(model: AppModel) { self.model = model }
    var desktopTop: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    func start() {
        guard timer == nil else { return }
        observeWorkspace()
        let polling = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer = polling
        RunLoop.main.add(polling, forMode: .common)
        globalEvents = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                // The app's own normal paste emits key events in the destination.
                if self.model.isReplacing || !self.captureReady { return }
                if event.type == .keyDown {
                    if event.keyCode == 53 { self.selectionTask?.cancel(); self.model.dismiss(force: true) }
                    else if self.model.selectionVisible || self.hasSelectionBadge { self.model.dismiss() }
                    return
                }
                if event.type == .leftMouseUp, self.model.enabled, self.model.selectionEnabled {
                    self.readSelection(automatic: true)
                } else {
                    self.selectionTask?.cancel()
                    self.resetMotion(at: NSEvent.mouseLocation)
                    self.model.dismiss()
                }
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

    func stop() {
        timer?.invalidate()
        timer = nil
        if let globalEvents { NSEvent.removeMonitor(globalEvents) }
        if let localScrollEvents { NSEvent.removeMonitor(localScrollEvents) }
        globalEvents = nil
        localScrollEvents = nil
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        displayObserver = nil
        selectionTask?.cancel()
        resetMotion(at: NSEvent.mouseLocation)
    }

    private func observeWorkspace() {
        let transitions: [(Notification.Name, CaptureLifecycle.Suspension, Bool)] = [
            (NSWorkspace.willSleepNotification, .systemSleep, true),
            (NSWorkspace.didWakeNotification, .systemSleep, false),
            (NSWorkspace.screensDidSleepNotification, .displaySleep, true),
            (NSWorkspace.screensDidWakeNotification, .displaySleep, false),
            (NSWorkspace.sessionDidResignActiveNotification, .inactiveSession, true),
            (NSWorkspace.sessionDidBecomeActiveNotification, .inactiveSession, false)
        ]
        // Avoid synchronous delivery through OperationQueue.main; enter the UI
        // actor explicitly even when the workspace posts from a background thread.
        for (name, reason, suspended) in transitions {
            let observer = NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.timer != nil else { return }
                    if suspended { self.lifecycle.suspend(reason) }
                    else { self.lifecycle.resume(reason, at: ProcessInfo.processInfo.systemUptime) }
                    self.resetAfterDisplayChange(refreshPermissions: !suspended)
                }
            }
            workspaceObservers.append(observer)
        }
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.timer != nil else { return }
                self.lifecycle.deferCapture(at: ProcessInfo.processInfo.systemUptime)
                self.resetAfterDisplayChange(refreshPermissions: false)
            }
        }
    }

    private func resetAfterDisplayChange(refreshPermissions: Bool) {
        selectionTask?.cancel()
        resetMotion(at: NSEvent.mouseLocation)
        model.dismiss(force: true)
        if refreshPermissions {
            model.refreshPermissions()
            lastPermissionRefresh = Date()
        }
    }

    var hasSelectionBadge: Bool { candidate?.selection == true && candidate?.opened == false }

    func clearCandidate() {
        candidate = nil
        outsideSince = nil
        hideBadge?()
    }

    func stage(_ capture: CapturedText, sourceRect: CGRect, pointer: CGPoint, demo: Bool = false,
               selection: Bool = false, replacement: ReplacementTarget? = nil) {
        guard !model.pinned, let badgeRect = showBadge?(pointer, sourceRect) else { return }
        candidate = Candidate(capture: capture, sourceRect: sourceRect, badgeRect: badgeRect, origin: pointer, previousPoint: pointer,
                              demo: demo, selection: selection, replacement: replacement)
        outsideSince = nil
        model.status = selection ? "已选中文字 · 将鼠标移到“译”图标查看译文" : "已发现外语 · 将鼠标移到“译”图标查看译文"
    }

    private func resetMotion(at point: CGPoint) {
        captureTask?.cancel()
        revision += 1
        lastPoint = point
        stableSince = Date()
        attempted = false
    }

    /// Returns true while a source, its icon, the path to it, or its result is in use.
    func retainCandidate(at point: CGPoint, now: Date = Date()) -> Bool {
        guard var current = candidate else { return false }
        if model.pinned { hideBadge?(); return true }
        if !current.demo && (!model.enabled || !(current.selection ? model.selectionEnabled : model.hoverEnabled)) {
            model.dismiss(force: true)
            resetMotion(at: point)
            return false
        }
        if current.opened, let frame = visibleCardFrame?(), frame.contains(point) {
            current.enteredCard = true
            candidate = current
            outsideSince = nil
            return true
        }
        if !current.enteredCard && current.badgeRect.contains(point) {
            outsideSince = nil
            if !current.opened {
                current.opened = true
                candidate = current
                if current.selection {
                    // The selection card persists on its own; place it beyond both text and icon.
                    model.present(current.capture, cocoaAnchor: current.sourceRect.isEmpty ? current.badgeRect : current.sourceRect.union(current.badgeRect),
                                  selection: true, replacement: current.replacement)
                } else {
                    model.present(current.capture, cocoaAnchor: current.badgeRect, selection: false)
                }
            }
            return true
        }
        if current.selection { outsideSince = nil; return true }
        let movement = hypot(point.x - current.previousPoint.x, point.y - current.previousPoint.y)
        let toward = TextLogic.movingTowardBadge(from: current.previousPoint, to: point, badge: current.badgeRect)
        if movement >= 0.5 {
            current.previousPoint = point
            current.approachUntil = toward ? now.addingTimeInterval(0.2) : .distantPast
        }
        candidate = current
        // The source may be an entire paragraph. Only the initial hover point
        // remains a resting zone; moving elsewhere in that paragraph dismisses.
        let inSource = !current.opened && hypot(point.x - current.origin.x, point.y - current.origin.y) <= 4
        let towardBadge = !current.opened && (toward || now < current.approachUntil)
        let towardCard: Bool
        if current.opened, !current.enteredCard, let frame = visibleCardFrame?() {
            towardCard = TextLogic.hoverTransitContains(point, from: current.badgeRect, to: frame)
        } else { towardCard = false }
        if inSource || towardBadge || towardCard { outsideSince = nil; return true }
        let leftAt = outsideSince ?? now
        outsideSince = leftAt
        if now.timeIntervalSince(leftAt) < model.closeDelay { return true }
        model.dismiss()
        resetMotion(at: point)
        return false
    }

    private func tick() {
        guard captureReady else { return }
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
        let access = "\(model.accessibility):\(model.screenPermission):\(model.ocrEnabled):\(model.hoverEnabled)"
        if access != previousCaptureAccess {
            previousCaptureAccess = access
            resetMotion(at: NSEvent.mouseLocation)
        }
        let point = NSEvent.mouseLocation
        // A deliberate selection is an action toolbar, not a hover preview.
        // Keep it reachable across any gap until an outside click/scroll or close.
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
                // Only OCR where the system exposes no text: if it read native text,
                // the Latin-only recognizer would misread those glyphs as gibberish.
                if capture == nil, model.ocrEnabled, model.screenPermission {
                    capture = try await TextCapture.ocr(at: quartz, word: word)
                    if let text = capture?.text, !TextLogic.plausibleOCR(text) { capture = nil }
                }
                // Native-language text never shows the hover icon; selecting it still does.
                guard !Task.isCancelled, token == revision, model.enabled, !model.pinned,
                      let capture, TextLogic.isForeign(capture.text, native: native) else { return }
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

    func readSelection(automatic: Bool = false) {
        guard captureReady else { return }
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
            if automatic { try? await Task.sleep(nanoseconds: 180_000_000) }
            guard !Task.isCancelled else { return }
            guard model.accessibility else {
                if !automatic { model.requestAccessibility() }
                attempted = false
                return
            }
            do {
                let capture = try await TextCapture.selected(pid: pid, fallbackPoint: point)
                guard !Task.isCancelled, (!automatic || model.enabled), NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                let anchor = TextLogic.cocoaRect(capture.text.bounds, desktopTop: desktopTop)
                if automatic {
                    // Mouse selections show the icon first; the shortcut and menu open the card directly.
                    let pointer = NSEvent.mouseLocation
                    stage(capture.text, sourceRect: capture.text.bounds.isEmpty ? .zero : anchor, pointer: pointer,
                          selection: true, replacement: capture.replacement)
                } else {
                    model.present(capture.text, cocoaAnchor: anchor, selection: true, replacement: capture.replacement)
                }
            } catch {
                guard !Task.isCancelled else { return }
                attempted = false
                stableSince = Date()
                if !automatic { model.status = error.localizedDescription; model.showWindow?() }
            }
        }
    }
}
