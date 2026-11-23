import AppKit
import SwiftUI
import Combine
import Carbon
import Translation
import ImageIO
import ApplicationServices

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class SubtitlePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class SelectionToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    var window: NSWindow!
    var panel: FloatingPanel!
    var subtitle: SubtitlePanel!
    var selectionToolbar: SelectionToolbarPanel!
    var statusItem: NSStatusItem!
    var monitor: HoverMonitor!
    var subscriptions = Set<AnyCancellable>()
    var hotKeySelection: EventHotKeyRef?
    var hotKeyScreenshot: EventHotKeyRef?
    var hotKeyHandler: EventHandlerRef?
    private var panelDraggedByUser = false
    private var settingPanelFrame = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        createPanel()
        createSubtitle()
        createSelectionToolbar()
        createStatusItem()
        monitor = HoverMonitor(model: model)
        monitor.visibleCardFrame = { [weak self] in
            guard let panel = self?.panel, panel.isVisible else { return nil }
            return panel.frame
        }
        monitor.visibleToolbarFrame = { [weak self] in
            guard let bar = self?.selectionToolbar, bar.isVisible else { return nil }
            return bar.frame
        }
        monitor.start()
        model.showCard = { [weak self] anchor in self?.showCard(anchor) }
        model.hideCard = { [weak self] in
            self?.panel.orderOut(nil)
            if self?.model.toastMessage.isEmpty == true { self?.subtitle.orderOut(nil) }
        }
        model.showToast = { [weak self] message, point in self?.showToast(message, at: point) }
        model.hideToast = { [weak self] in
            guard let self, !self.model.isPresenting || self.model.selectionVisible else { return }
            self.subtitle.orderOut(nil)
        }
        model.showSelectionToolbar = { [weak self] anchor in self?.showSelectionToolbar(anchor) }
        model.hideSelectionToolbar = { [weak self] in
            self?.model.toolbarShown = false
            self?.selectionToolbar.orderOut(nil)
        }
        model.toolbarActionTranslate = { [weak self] in self?.monitor.performToolbarAction(.translate) }
        model.toolbarActionCopy = { [weak self] in self?.monitor.performToolbarAction(.copy) }
        model.toolbarActionSave = { [weak self] in self?.monitor.performToolbarAction(.save) }
        model.startScreenshot = { [weak self] in self?.screenshot() }
        model.showWindow = { [weak self] in self?.showMain() }
        model.pointerInCard = { [weak self] in self?.panel.isVisible == true && self?.panel.frame.contains(NSEvent.mouseLocation) == true }
        model.pointerInToolbar = { [weak self] in self?.selectionToolbar.isVisible == true && self?.selectionToolbar.frame.contains(NSEvent.mouseLocation) == true }
        model.stageHover = { [weak self] capture, rect, point, demo in self?.monitor.stage(capture, sourceRect: rect, pointer: point, demo: demo) }
        model.clearHover = { [weak self] in self?.monitor.clearCandidate() }
        model.releasePanelFocus = { [weak self] in self?.panel.resignKey() }
        model.$replacementMessage.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.resizeCard() }
        }.store(in: &subscriptions)
        model.$phase.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.resizeCard() }
        }.store(in: &subscriptions)
        model.$result.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.resizeCard() }
        }.store(in: &subscriptions)
        model.$source.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.resizeCard() }
        }.store(in: &subscriptions)
        model.$enabled.sink { [weak self] enabled in
            self?.statusItem?.button?.toolTip = enabled ? "浮译 · 全局翻译已开启" : "浮译 · 已暂停"
        }.store(in: &subscriptions)
        registerShortcut()
        DispatchQueue.main.async { self.showMain() }
        let checkSelfHit = CommandLine.arguments.contains("--check-self-hit-flow")
        if CommandLine.arguments.contains("--check-window-flow") || checkSelfHit {
            model.enabled = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                if checkSelfHit && !self.model.accessibility {
                    print("Self-hit check requires the installed application's existing accessibility grant.")
                    exit(1)
                }
                let cycles = checkSelfHit ? 32 : 12
                let fixtures = [("Keep in Dock", "保留在程序坞"),
                                ("Good design makes complex things feel simple.", "好的设计，让复杂的事情变得简单。"),
                                (String(repeating: "English text. ", count: 40), String(repeating: "较长的译文。", count: 100))]
                for cycle in 0..<cycles {
                    DiagnosticCheck.require(Thread.isMainThread)
                    if checkSelfHit {
                        let point = TextLogic.quartzPoint(CGPoint(x: self.window.frame.midX, y: self.window.frame.midY), desktopTop: self.monitor.desktopTop)
                        do {
                            _ = try await TextCapture.accessible(at: point, word: false)
                            DiagnosticCheck.fail("The application's own window must be rejected")
                        } catch CaptureError.ownApplication { }
                        catch { DiagnosticCheck.fail("Unexpected self-hit error: \(error)") }
                        // Exercise the final notification path seen in the crash report,
                        // without changing the computer's actual power settings.
                        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                            DispatchQueue.global(qos: .userInteractive).async {
                                NotificationCenter.default.post(name: .NSProcessInfoPowerStateDidChange, object: ProcessInfo.processInfo)
                                continuation.resume()
                            }
                        }
                    }
                    let anchor = CGRect(x: 300, y: 400, width: 100, height: 24)
                    let sample = fixtures[cycle % fixtures.count]
                    let destination = cycle.isMultiple(of: 2) ? nil : ReplacementTarget(
                        element: AXUIElementCreateApplication(1), pid: 1,
                        edit: SelectionEdit(value: sample.0, selected: sample.0, range: NSRange(location: 0, length: sample.0.utf16.count)))
                    self.model.present(CapturedText(text: sample.0, bounds: .zero, method: "窗口回归检查"),
                                       cocoaAnchor: anchor, selection: true, replacement: destination)
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    self.model.result = sample.1
                    self.model.phase = .result
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    DiagnosticCheck.require(self.panel.frame.width == self.model.cardWidth)
                    DiagnosticCheck.require(self.panel.frame.height == self.model.cardHeight)
                    DiagnosticCheck.require(self.panel.frame.height <= 388)
                    DiagnosticCheck.require(self.panel.contentView is NSVisualEffectView)
                    self.model.dismiss(force: true)
                    self.window.performClose(nil)
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    self.showMain()
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
                let report = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/HoverTranslate/" + (checkSelfHit ? "self-hit-check.txt" : "window-check.txt"))
                try? "\(cycles) native window cycles passed on the main thread; self-hit and background notification check: \(checkSelfHit).\n".write(to: report, atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
            }
        }
    }

    func attachWindow(_ newWindow: NSWindow) {
        guard window !== newWindow else { return }
        window = newWindow
        window.title = "浮译 · Hover Translate"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 1040, height: 740)
        window.delegate = self
        window.center()
    }

    func createPanel() {
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: CardLayout.minimumWidth, height: 84),
                              styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.title = "浮译 · 翻译浮窗"
        panel.setAccessibilityRole(.window)
        panel.setAccessibilityLabel("翻译浮窗")
        panel.acceptsMouseMovedEvents = true
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 2)
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let glass = NSVisualEffectView(frame: CGRect(origin: .zero, size: panel.frame.size))
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 14
        glass.layer?.masksToBounds = true
        let content = fixedHostingView(TranslationCard(model: model), size: glass.bounds.size)
        content.autoresizingMask = [.width, .height]
        glass.addSubview(content)
        panel.contentView = glass
    }

    func createSubtitle() {
        subtitle = SubtitlePanel(contentRect: CGRect(x: 0, y: 0, width: 30, height: 30),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        subtitle.title = "浮译 · 悬停译文"
        subtitle.setAccessibilityRole(.window)
        subtitle.setAccessibilityLabel("悬停译文")
        subtitle.isOpaque = false
        subtitle.backgroundColor = .clear
        subtitle.ignoresMouseEvents = true
        subtitle.hasShadow = true
        subtitle.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        subtitle.hidesOnDeactivate = false
        subtitle.isReleasedWhenClosed = false
        subtitle.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        subtitle.contentView = fixedHostingView(HoverSubtitle(model: model), size: subtitle.frame.size)
    }

    func createSelectionToolbar() {
        let size = CGSize(width: 136, height: 64)
        selectionToolbar = SelectionToolbarPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        selectionToolbar.title = "浮译 · 划词快捷圆球"
        selectionToolbar.setAccessibilityRole(.window)
        selectionToolbar.setAccessibilityLabel("划词快捷圆球")
        selectionToolbar.isOpaque = false
        selectionToolbar.backgroundColor = .clear
        selectionToolbar.hasShadow = false
        selectionToolbar.acceptsMouseMovedEvents = true
        selectionToolbar.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 3)
        selectionToolbar.hidesOnDeactivate = false
        selectionToolbar.isReleasedWhenClosed = false
        selectionToolbar.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let hosting = FirstMouseHostingView(rootView: SelectionToolbarView(model: model))
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        selectionToolbar.contentView = hosting
    }

    func showSelectionToolbar(_ anchor: CGRect) {
        let size = CGSize(width: 136, height: 64)
        guard let screen = screen(containing: anchor.origin) else { return }
        let safe = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let x = min(max(anchor.midX - size.width / 2, safe.minX), safe.maxX - size.width)
        var y = anchor.maxY + 2
        if y + size.height > safe.maxY { y = anchor.minY - size.height + 10 }
        y = min(max(y, safe.minY), safe.maxY - size.height)
        selectionToolbar.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: true)
        model.toolbarShown = true
        model.toolbarAppearance &+= 1
        selectionToolbar.orderFrontRegardless()
    }

    func showToast(_ message: String, at point: CGPoint) {
        guard let screen = screen(containing: point) else { return }
        let width = min(screen.visibleFrame.width - 24, max(96, min(420, ceil((message as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width) + 48)))
        let anchor = CGRect(origin: point, size: CGSize(width: 1, height: 1))
        let frame = TextLogic.panelFrame(anchor: anchor, size: CGSize(width: width, height: 30), visible: screen.visibleFrame)
        subtitle.setFrame(frame, display: true)
        subtitle.orderFrontRegardless()
    }

    // AppKit owns panel geometry; asynchronous SwiftUI measurement must not
    // resize the NSWindow as translation content changes.
    private func fixedHostingView<Content: View>(_ content: Content, size: CGSize) -> NSView {
        let container = NSView(frame: CGRect(origin: .zero, size: size))
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        return container
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func setPanelFrame(_ frame: CGRect) {
        settingPanelFrame = true
        panel.setFrame(frame, display: true)
        settingPanelFrame = false
    }

    func showCard(_ anchor: CGRect) {
        if !model.selectionVisible {
            panel.orderOut(nil)
            panelDraggedByUser = false
            guard let screen = screen(containing: anchor.origin) else { return }
            let extra: CGFloat = model.phase == .failure ? 46 : 30
            let width = min(screen.visibleFrame.width - 24, max(96, min(680, ceil((model.subtitleText as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width) + extra)))
            let frame = TextLogic.panelFrame(anchor: anchor, size: CGSize(width: width, height: 28), visible: screen.visibleFrame)
            subtitle.setFrame(frame, display: true)
            subtitle.orderFrontRegardless()
            return
        }
        subtitle.orderOut(nil)
        panelDraggedByUser = false
        let height = model.cardHeight
        guard let screen = screen(containing: CGPoint(x: anchor.midX, y: anchor.midY)) else { return }
        let frame = TextLogic.panelFrame(anchor: anchor, size: CGSize(width: model.cardWidth, height: height), visible: screen.visibleFrame)
        setPanelFrame(frame)
        panel.orderFrontRegardless()
        if model.method == "文字试用" { panel.makeKeyAndOrderFront(nil) }
    }

    func resizeCard() {
        guard panel.isVisible || subtitle.isVisible else { return }
        if model.selectionVisible {
            let old = panel.frame
            guard let screen = screen(containing: CGPoint(x: old.midX, y: old.midY)) else { return }
            let safe = screen.visibleFrame.insetBy(dx: 12, dy: 12)
            let below = panelDraggedByUser ? true : old.maxY <= model.anchor.minY
            let y = below ? old.maxY - model.cardHeight : old.minY
            let clampedY = min(max(y, safe.minY), safe.maxY - model.cardHeight)
            let x = min(max(old.minX, safe.minX), safe.maxX - model.cardWidth)
            let frame = CGRect(x: x, y: panelDraggedByUser ? clampedY : y, width: model.cardWidth, height: model.cardHeight)
            if panelDraggedByUser || (safe.contains(frame) && !frame.intersects(model.anchor)) {
                setPanelFrame(frame)
                return
            }
        }
        showCard(model.anchor)
    }

    func showMain() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "浮译") {
            image.isTemplate = true; statusItem.button?.image = image
        }
        statusItem.button?.toolTip = "浮译 · 已暂停"
        let menu = NSMenu()
        menu.addItem(item("打开浮译", #selector(openMain), ""))
        menu.addItem(item("打开摘录本", #selector(openSnippets), ""))
        menu.addItem(.separator())
        menu.addItem(item("开启 / 暂停全局翻译", #selector(toggle), ""))
        menu.addItem(item("翻译选中文字  ⌃⌥T", #selector(selection), ""))
        menu.addItem(item("截图翻译与提取文字  ⌥S", #selector(screenshot), ""))
        menu.addItem(item("翻译剪贴板", #selector(clipboard), ""))
        menu.addItem(item("偏好设置…", #selector(settings), ","))
        menu.addItem(.separator())
        menu.addItem(item("退出浮译", #selector(quit), "q"))
        statusItem.menu = menu
    }

    func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; return item
    }

    func registerShortcut() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData -> OSStatus in
            guard let userData, let eventRef else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard err == noErr else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in
                if hotKeyID.id == 1 { delegate.monitor.readSelection() }
                else if hotKeyID.id == 2 { delegate.screenshot() }
            }
            return noErr
        }, 1, &event, pointer, &hotKeyHandler)

        let selID = EventHotKeyID(signature: OSType(0x46555949), id: 1)
        let selResult = RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(controlKey | optionKey), selID, GetApplicationEventTarget(), 0, &hotKeySelection)
        let shotID = EventHotKeyID(signature: OSType(0x46555949), id: 2)
        let shotResult = RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(optionKey), shotID, GetApplicationEventTarget(), 0, &hotKeyScreenshot)

        if selResult != noErr && shotResult != noErr {
            model.status = "⌃⌥T 与 ⌥S 快捷键被占用；仍可使用划词工具栏与菜单栏。"
        } else if selResult != noErr {
            model.status = "⌃⌥T 快捷键被占用；仍可使用划词工具栏与菜单栏。"
        } else if shotResult != noErr {
            model.status = "⌥S 快捷键被占用；仍可从菜单栏使用截图翻译。"
        }
    }

    @objc func openMain() { showMain() }
    @objc func openSnippets() { model.openSnippets() }
    @objc func toggle() { model.toggleEnabled() }
    @objc func selection() { monitor.readSelection() }

    @objc func screenshot() {
        guard !model.capturingRegion else { return }
        model.refreshPermissions()
        guard model.screenPermission else { model.requestScreen(); showMain(); return }
        monitor.clearToolbar()
        model.dismiss(force: true)
        model.capturingRegion = true
        let hideMain = window?.isVisible == true && NSApp.isActive
        if hideMain { window?.orderOut(nil) }
        Task {
            defer { model.capturingRegion = false }
            if hideMain { try? await Task.sleep(nanoseconds: 140_000_000) }
            var dropPoint = NSEvent.mouseLocation
            do {
                guard let ocr = try await RegionCapture.capture(onCaptured: {
                    await MainActor.run {
                        dropPoint = NSEvent.mouseLocation
                        self.model.presentRegionRecognizing(at: CGRect(origin: dropPoint, size: CGSize(width: 1, height: 1)))
                    }
                }) else {
                    if hideMain { showMain() }
                    return
                }
                model.presentRegionResult(ocr, cocoaAnchor: CGRect(origin: dropPoint, size: CGSize(width: 1, height: 1)))
            } catch {
                model.dismiss(force: true)
                model.flashToast(error.localizedDescription, at: dropPoint)
            }
        }
    }
    @objc func clipboard() { model.clipboard() }
    @objc func settings() { model.settings() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMain() }
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeySelection { UnregisterEventHotKey(hotKeySelection) }
        if let hotKeyScreenshot { UnregisterEventHotKey(hotKeyScreenshot) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        model.continuePermissionSetup()
        // Packs downloaded in System Settings appear when the user comes back.
        Task { await model.refreshLanguage() }
    }
    func windowDidMove(_ notification: Notification) {
        guard let moved = notification.object as? NSWindow, moved === panel, !settingPanelFrame, panel.isVisible else { return }
        panelDraggedByUser = true
    }
    func windowWillClose(_ notification: Notification) {
        guard let closed = notification.object as? NSWindow, closed === window else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.model.pinned else { return }
            self.model.dismiss(force: true)
        }
    }
}

@main
struct Entry {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if args.count == 3, args[1] == "--check-region-image" {
            do { print(try RegionCapture.recognize(URL(fileURLWithPath: args[2]))); exit(0) }
            catch { DiagnosticCheck.fail(error.localizedDescription) }
        }
        if args.count == 3, args[1] == "--check-ai", let provider = [AIProvider.codex, .claude].first(where: { String(describing: $0) == args[2] }) {
            Task {
                do { print(try await provider.translate("다음 역에서 내려 주세요.", from: "ko", to: "zh-Hans")); exit(0) }
                catch { DiagnosticCheck.fail(error.localizedDescription) }
            }
            dispatchMain()
        }
        if args.contains("--check-hover-flow") {
            Task { @MainActor in
                let model = AppModel(checkPermissions: false)
                do {
                    try TextCapture.requireExternalElement(AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier))
                    DiagnosticCheck.fail("Own accessibility elements must never enter the background reader")
                } catch CaptureError.ownApplication { }
                catch { DiagnosticCheck.fail("Unexpected own-element guard error") }
                do { try TextCapture.requireExternalElement(AXUIElementCreateApplication(1)) }
                catch { DiagnosticCheck.fail("External element guard failed: \(error)") }
                do {
                    _ = try await TextCapture.selected(pid: ProcessInfo.processInfo.processIdentifier, fallbackPoint: .zero)
                    DiagnosticCheck.fail("Own selection must not enter the background reader")
                } catch CaptureError.ownApplication { }
                catch { DiagnosticCheck.fail("Unexpected own-selection guard error") }
                var updates = 0
                let subscription = model.objectWillChange.sink { updates += 1 }
                model.applyPermissions(accessibility: false, screen: false)
                DiagnosticCheck.require(updates == 0, "Unchanged permissions must not invalidate SwiftUI layout")
                model.applyPermissions(accessibility: true, screen: true)
                DiagnosticCheck.require(updates == 2, "Permission changes must publish immediately")
                model.applyPermissions(accessibility: true, screen: true)
                DiagnosticCheck.require(updates == 2, "Repeated polling must not publish")
                model.dismiss()
                model.dismiss(force: true)
                DiagnosticCheck.require(updates == 2, "Idle dismiss must never invalidate SwiftUI layout")
                DiagnosticCheck.require(AIProvider.apple.binary == nil, "Apple offline provider must never resolve a CLI binary")
                subscription.cancel()
                let monitor = HoverMonitor(model: model)
                let pointer = CGPoint(x: 150, y: 310)
                let source = CGRect(x: 100, y: 300, width: 300, height: 25)
                var opened = 0
                model.showCard = { _ in opened += 1 }
                model.clearHover = { monitor.clearCandidate() }
                monitor.stage(CapturedText(text: "Test", bounds: .zero, method: "test"), sourceRect: source, pointer: pointer, demo: true)
                DiagnosticCheck.require(opened == 1 && monitor.retainCandidate(at: pointer), "Hover translates immediately after dwell")
                DiagnosticCheck.require(!monitor.retainCandidate(at: .zero), "Leaving the source dismisses the subtitle")
                // Single-character AX bounds must still retain nearby movement along the hovered word.
                let tinyChar = CGRect(x: pointer.x - 3, y: pointer.y - 7, width: 7, height: 14)
                monitor.stage(CapturedText(text: "Hello world", bounds: .zero, method: "test"), sourceRect: tinyChar, pointer: pointer, demo: true)
                DiagnosticCheck.require(monitor.retainCandidate(at: CGPoint(x: pointer.x + 14, y: pointer.y)), "Tiny character bounds keep a comfortable hover zone")
                monitor.clearCandidate()
                DiagnosticCheck.require(!model.toolbarShown, "Selection orbs start hidden")
                monitor.visibleCardFrame = { source }
                let destination = ReplacementTarget(element: AXUIElementCreateApplication(1), pid: 1,
                    edit: SelectionEdit(value: "你好，世界！", selected: "你好，世界！", range: NSRange(location: 0, length: 6)))
                model.present(CapturedText(text: "你好，世界！", bounds: .zero, method: "test"),
                              cocoaAnchor: source, selection: true, replacement: destination)
                DiagnosticCheck.require(model.hasReplacementTarget && !model.canReplaceSelection, "A selection must preview before replacing")
                model.result = "你好，世界！"; model.phase = .result
                DiagnosticCheck.require(!model.canReplaceSelection, "An unchanged result must not enable replacement")
                model.target = "en"; model.result = "Hello, world!"; model.phase = .result
                DiagnosticCheck.require(model.canReplaceSelection && model.showsReplacementControls, "A translated editable selection exposes replacement")
                model.phase = .loading
                DiagnosticCheck.require(!model.canReplaceSelection, "An unfinished translation cannot replace text")
                model.phase = .result
                let clipboardCount = NSPasteboard.general.changeCount
                model.replaceSelection()
                DiagnosticCheck.require(model.isReplacing && !model.canReplaceSelection, "Prevent duplicate replacements")
                model.translate(to: "ja")
                DiagnosticCheck.require(model.target == "en", "Language cannot change during a replacement")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                DiagnosticCheck.require(!model.isReplacing && !model.canReplaceSelection && !model.replacementMessage.isEmpty,
                             "An invalid destination must fail safely and cannot be retried")
                DiagnosticCheck.require(NSPasteboard.general.changeCount == clipboardCount, "Rejected replacements must not touch the clipboard")
                model.present(CapturedText(text: "Read-only text", bounds: .zero, method: "test"), cocoaAnchor: source, selection: true)
                DiagnosticCheck.require(!model.hasReplacementTarget && !model.showsReplacementControls,
                             "Read-only selections never expose replacement or stale errors")
                DiagnosticCheck.require(monitor.retainSelection(), "Read-only and editable selections share the persistent card")
                model.dismiss(force: true)
                let spaced = ReplacementTarget(element: AXUIElementCreateApplication(1), pid: 1,
                    edit: SelectionEdit(value: "Say Hello now", selected: "Hello ", range: NSRange(location: 4, length: 6)))
                model.present(CapturedText(text: "Hello", bounds: .zero, method: "test"), cocoaAnchor: source, selection: true, replacement: spaced)
                model.result = "Hello"; model.phase = .result
                DiagnosticCheck.require(!model.canReplaceSelection, "Whitespace-only differences do not count as a translation")
                model.result = "你好"
                DiagnosticCheck.require(model.canReplaceSelection, "A selection with a trailing space can still be replaced")
                model.dismiss(force: true)
                // Polling runs only while it is needed.
                let idle = HoverMonitor(model: model)
                model.enabled = false
                idle.updatePolling()
                DiagnosticCheck.require(!idle.isPolling, "A paused app with nothing on screen does not poll")
                idle.stage(CapturedText(text: "Keep in Dock", bounds: .zero, method: "test"), sourceRect: source, pointer: pointer, demo: true)
                DiagnosticCheck.require(idle.isPolling, "A staged badge starts polling, even while paused")
                idle.clearCandidate(); idle.updatePolling()
                DiagnosticCheck.require(!idle.isPolling, "Polling stops once the badge is gone")
                model.enabled = true; idle.updatePolling()
                DiagnosticCheck.require(idle.isPolling, "Enabled translation polls the pointer")
                model.enabled = false; idle.updatePolling()
                DiagnosticCheck.require(!idle.isPolling, "Pausing stops polling")
                // Clipboard lease on a private pasteboard: never touch the user's clipboard.
                let board = NSPasteboard(name: NSPasteboard.Name("io.github.kianzzz.hovertranslate.check.\(UUID().uuidString)"))
                board.clearContents(); board.setString("user clipboard", forType: .string)
                let lease = try! PasteboardLease(text: "译文", board: board)
                DiagnosticCheck.require(board.string(forType: .string) == "译文", "The lease offers the translation for pasting")
                DiagnosticCheck.require(PasteboardLease.markerTypes.allSatisfy { board.types?.contains($0) == true },
                                        "The lease is marked transient so clipboard managers skip it")
                lease.restore()
                DiagnosticCheck.require(board.string(forType: .string) == "user clipboard"
                                        && !PasteboardLease.markerTypes.contains { board.types?.contains($0) == true },
                                        "Restoring brings back the user's clipboard without markers")
                let second = try! PasteboardLease(text: "译文", board: board)
                board.clearContents(); board.setString("copied meanwhile", forType: .string)
                second.restore()
                DiagnosticCheck.require(board.string(forType: .string) == "copied meanwhile", "A copy made meanwhile is never overwritten")
                board.releaseGlobally()
                let pasteKey = KeyboardLayout.keyCode(for: "v")
                let copyKey = KeyboardLayout.keyCode(for: "c")
                DiagnosticCheck.require(pasteKey != nil && copyKey != nil, "The current keyboard layout resolves ⌘V and ⌘C keys")
                // Snippet store non-destructive Markdown append check in a private temp directory.
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("HoverTranslate-SnippetCheck-\(UUID().uuidString)")
                let tempMD = tempDir.appendingPathComponent("摘录.md")
                let tempJSON = tempDir.appendingPathComponent("snippets.json")
                defer { try? FileManager.default.removeItem(at: tempDir) }
                let firstSnippet = Snippet(text: "Stay curious.", translation: "保持好奇。", appName: "Safari")
                try! SnippetStore.saveIndex([firstSnippet], to: tempJSON)
                try! SnippetStore.appendMarkdown(firstSnippet, to: tempMD)
                let loaded = SnippetStore.load(from: tempJSON)
                let mdContent = try! String(contentsOf: tempMD, encoding: .utf8)
                DiagnosticCheck.require(loaded.count == 1 && loaded[0].text == "Stay curious." && loaded[0].translation == "保持好奇。", "Snippet JSON round-trip works")
                DiagnosticCheck.require(mdContent.contains("> Stay curious.") && mdContent.contains("保持好奇。") && mdContent.contains("Safari"), "Markdown append formats blockquote, translation, and app name")
                print("Snippet store checks passed: JSON round-trip and non-destructive Markdown append.")
                print("Replacement checks passed: edge whitespace, transient clipboard lease, restore safety, paste key \(pasteKey!), copy key \(copyKey!) for the current layout.")
                print("Polling checks passed: idle when paused, active for badges and enabled translation.")
                print("Selection-card checks passed: preview gating, native fallback, read-only mode, busy state, invalid target and clipboard safety.")
                print("Capture safety and hover-flow checks passed: own-element and own-selection rejection, remote element acceptance, permission publication, subtitle opening and dismissal.")
                exit(0)
            }
            dispatchMain()
        }
        if args.count == 5, ["--check-image", "--check-word-image"].contains(args[1]), let x = Double(args[3]), let y = Double(args[4]) {
            Task { @MainActor in
                guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { print("Cannot read image"); exit(1) }
                do {
                    let region = CGRect(x: 0, y: 0, width: image.width, height: image.height)
                    let result = try await TextCapture.hoverText(image: image, region: region, at: CGPoint(x: x, y: y), word: args[1] == "--check-word-image")
                    let data = try JSONSerialization.data(withJSONObject: ["text": result?.text as Any? ?? NSNull()], options: [.sortedKeys])
                    print(String(decoding: data, as: UTF8.self))
                    exit(0)
                } catch { print(error.localizedDescription); exit(1) }
            }
            dispatchMain()
        }
        if CommandLine.arguments.contains("--check-packs") {
            Task { @MainActor in
                for id in ["en", "ja", "ja-JP", "ko", "ko-KR", "fr"] {
                    let low = await TranslationRuntime.availability().status(from: Locale.Language(identifier: id), to: Locale.Language(identifier: "zh-Hans"))
                    let plain = await LanguageAvailability().status(from: Locale.Language(identifier: id), to: Locale.Language(identifier: "zh-Hans"))
                    let cn = await LanguageAvailability().status(from: Locale.Language(identifier: id), to: Locale.Language(identifier: "zh-CN"))
                    print(id, "lowLatency:", low, "default:", plain, "zh-CN:", cn)
                }
                exit(0)
            }
            dispatchMain()
        }
        if CommandLine.arguments.contains("--check-engine") {
            Task { @MainActor in
                let availability = TranslationRuntime.availability()
                let status = await availability.status(from: Locale.Language(identifier: "en"), to: Locale.Language(identifier: "zh-Hans"))
                print("English → Chinese language status: \(status)")
                if status == .installed {
                    do {
                        let engine = LocalTranslator()
                        print("English → Chinese: \(try await engine.translate("Good design makes complex things feel simple.", from: "en", to: "zh-Hans"))")
                        if await availability.status(from: Locale.Language(identifier: "ja"), to: Locale.Language(identifier: "zh-Hans")) == .installed {
                            print("Japanese → Chinese: \(try await engine.translate("次の駅で降りてください。", from: "ja", to: "zh-Hans"))")
                        }
                        print("Chinese → English: \(try await engine.translate("保持好奇，总有更多值得发现。", from: "zh-Hans", to: "en"))")
                    } catch { print("Translation failed: \(error.localizedDescription)"); exit(1) }
                }
                exit(0)
            }
            dispatchMain()
        }
        NativeApp.main()
    }
}

@MainActor
struct NativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("浮译 · Hover Translate") {
            MainView(model: delegate.model)
                .background(WindowBridge { delegate.attachWindow($0) })
        }
        .defaultSize(width: 1110, height: 780)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appSettings) {
                Button("偏好设置…") { delegate.model.settings() }.keyboardShortcut(",")
            }
        }
    }
}

struct WindowBridge: NSViewRepresentable {
    let attach: (NSWindow) -> Void
    func makeNSView(context: Context) -> AttachedView {
        let view = AttachedView()
        view.attach = attach
        return view
    }
    func updateNSView(_ nsView: AttachedView, context: Context) { }
    final class AttachedView: NSView {
        var attach: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [weak self] in self?.attach?(window) }
        }
    }
}
