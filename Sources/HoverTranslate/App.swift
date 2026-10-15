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

final class HoverBadgePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    var window: NSWindow!
    var panel: FloatingPanel!
    var badge: HoverBadgePanel!
    var statusItem: NSStatusItem!
    var monitor: HoverMonitor!
    var subscriptions = Set<AnyCancellable>()
    var hotKey: EventHotKeyRef?
    var hotKeyHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        createPanel()
        createBadge()
        createStatusItem()
        monitor = HoverMonitor(model: model)
        monitor.visibleCardFrame = { [weak self] in
            guard let panel = self?.panel, panel.isVisible else { return nil }
            return panel.frame
        }
        monitor.showBadge = { [weak self] point, source in self?.showBadge(point, source: source) ?? .zero }
        monitor.hideBadge = { [weak self] in self?.badge.orderOut(nil) }
        monitor.start()
        model.showCard = { [weak self] anchor in self?.showCard(anchor) }
        model.hideCard = { [weak self] in self?.panel.orderOut(nil) }
        model.showWindow = { [weak self] in self?.showMain() }
        model.pointerInCard = { [weak self] in self?.panel.isVisible == true && self?.panel.frame.contains(NSEvent.mouseLocation) == true }
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
                    _ = self.showBadge(CGPoint(x: 400, y: 430))
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let glass = NSVisualEffectView(frame: CGRect(origin: .zero, size: panel.frame.size))
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.appearance = NSAppearance(named: .aqua)
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 11
        glass.layer?.masksToBounds = true
        let content = fixedHostingView(TranslationCard(model: model), size: glass.bounds.size)
        content.autoresizingMask = [.width, .height]
        glass.addSubview(content)
        panel.contentView = glass
    }

    func createBadge() {
        badge = HoverBadgePanel(contentRect: CGRect(x: 0, y: 0, width: 30, height: 30),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        badge.title = "浮译 · 悬停图标"
        badge.setAccessibilityRole(.window)
        badge.setAccessibilityLabel("悬停翻译图标")
        badge.isOpaque = false
        badge.backgroundColor = .clear
        badge.hasShadow = true
        badge.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        badge.hidesOnDeactivate = false
        badge.isReleasedWhenClosed = false
        badge.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        badge.contentView = fixedHostingView(HoverBadgeView(), size: badge.frame.size)
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

    func showBadge(_ point: CGPoint, source: CGRect = .zero) -> CGRect {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main!
        let rect = TextLogic.badgeFrame(pointer: point, visible: screen.visibleFrame, source: source)
        badge.setFrame(rect, display: true)
        badge.orderFrontRegardless()
        return badge.frame
    }

    func showCard(_ anchor: CGRect) {
        let height = model.cardHeight
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) } ?? NSScreen.main!
        let frame = TextLogic.panelFrame(anchor: anchor, size: CGSize(width: model.cardWidth, height: height), visible: screen.visibleFrame)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        if model.method == "文字试用 · 本机翻译" { panel.makeKeyAndOrderFront(nil) }
    }

    func resizeCard() {
        guard panel.isVisible else { return }
        if model.selectionVisible {
            let old = panel.frame
            let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: old.midX, y: old.midY)) } ?? NSScreen.main!
            let safe = screen.visibleFrame.insetBy(dx: 12, dy: 12)
            let below = old.maxY <= model.anchor.minY
            let y = below ? old.maxY - model.cardHeight : old.minY
            let x = min(max(old.minX, safe.minX), safe.maxX - model.cardWidth)
            let frame = CGRect(x: x, y: y, width: model.cardWidth, height: model.cardHeight)
            if safe.contains(frame), !frame.intersects(model.anchor) {
                panel.setFrame(frame, display: true)
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
        menu.addItem(.separator())
        menu.addItem(item("开启 / 暂停全局翻译", #selector(toggle), ""))
        menu.addItem(item("翻译选中文字  ⌃⌥T", #selector(selection), ""))
        menu.addItem(item("翻译剪贴板", #selector(clipboard), ""))
        menu.addItem(item("偏好设置…", #selector(settings), ","))
        menu.addItem(.separator())
        menu.addItem(item("退出浮译", #selector(quit), "q"))
        statusItem.menu = menu
    }

    func createMainMenu() {
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "浮译")
        applicationMenu.addItem(item("打开浮译", #selector(openMain), ""))
        applicationMenu.addItem(item("偏好设置…", #selector(settings), ","))
        applicationMenu.addItem(.separator())
        let hide = NSMenuItem(title: "隐藏浮译", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.target = NSApp
        applicationMenu.addItem(hide)
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(item("退出浮译", #selector(quit), "q"))
        applicationItem.submenu = applicationMenu
        main.addItem(applicationItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        for (title, selector, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: NSSelectorFromString(selector), keyEquivalent: key))
        }
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; return item
    }

    func registerShortcut() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in delegate.monitor.readSelection() }
            return noErr
        }, 1, &event, pointer, &hotKeyHandler)
        let id = EventHotKeyID(signature: OSType(0x46555949), id: 1)
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
        if result != noErr { model.status = "⌃⌥T 快捷键被占用；仍可使用鼠标选区和菜单栏。" }
    }

    @objc func openMain() { showMain() }
    @objc func toggle() { model.toggleEnabled() }
    @objc func selection() { monitor.readSelection() }
    @objc func clipboard() { model.clipboard() }
    @objc func settings() { model.settings() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDidBecomeActive(_ notification: Notification) { model.continuePermissionSetup() }
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.model.dismiss(force: true) }
    }
}

@main
struct Entry {
    @MainActor static func main() {
        let args = CommandLine.arguments
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
                subscription.cancel()
                let monitor = HoverMonitor(model: model)
                let pointer = CGPoint(x: 150, y: 310)
                let source = CGRect(x: 100, y: 300, width: 300, height: 25)
                let badge = TextLogic.badgeFrame(pointer: pointer, visible: CGRect(x: 0, y: 0, width: 1100, height: 780))
                // Exercise approach/reversal with immediate dismissal selected.
                let travel = HoverMonitor(model: model)
                travel.showBadge = { _, _ in badge }
                model.clearHover = { [weak travel] in travel?.clearCandidate() }
                model.closeDelay = 0
                let travelTime = Date(timeIntervalSince1970: 900)
                travel.stage(CapturedText(text: "Test", bounds: .zero, method: "test"), sourceRect: source, pointer: pointer, demo: true)
                let approaching = CGPoint(x: pointer.x + 4, y: pointer.y - 4)
                DiagnosticCheck.require(travel.retainCandidate(at: approaching, now: travelTime), "Approaching survives zero close delay")
                DiagnosticCheck.require(travel.retainCandidate(at: approaching, now: travelTime.addingTimeInterval(0.1)), "Brief approach pause tolerates hand jitter")
                DiagnosticCheck.require(!travel.retainCandidate(at: CGPoint(x: approaching.x - 10, y: approaching.y + 10), now: travelTime.addingTimeInterval(0.12)), "Reversing closes even inside the old source region")
                travel.stage(CapturedText(text: "Test", bounds: .zero, method: "test"), sourceRect: source, pointer: pointer, demo: true)
                DiagnosticCheck.require(travel.retainCandidate(at: approaching, now: travelTime))
                DiagnosticCheck.require(!travel.retainCandidate(at: approaching, now: travelTime.addingTimeInterval(0.21)), "Approach grace expires when movement stops")
                var opened = 0
                monitor.showBadge = { _, _ in badge }
                model.showCard = { _ in opened += 1 }
                model.clearHover = { [weak monitor] in monitor?.clearCandidate() }
                monitor.stage(CapturedText(text: "Keep in Dock", bounds: .zero, method: "test"), sourceRect: source, pointer: pointer, demo: true)
                DiagnosticCheck.require(opened == 0, "Text hover must only show the badge")
                DiagnosticCheck.require(monitor.retainCandidate(at: pointer) && opened == 0, "Source hover must not translate")
                let center = CGPoint(x: badge.midX, y: badge.midY)
                DiagnosticCheck.require(monitor.retainCandidate(at: center) && opened == 1, "Entering the badge must open without a click")
                DiagnosticCheck.require(monitor.retainCandidate(at: center) && opened == 1, "Badge hover must not launch duplicate translations")
                let outside = CGPoint(x: 900, y: 700)
                let now = Date(timeIntervalSince1970: 1000)
                model.closeDelay = 0.3
                DiagnosticCheck.require(monitor.retainCandidate(at: outside, now: now), "Keep the configured grace period")
                DiagnosticCheck.require(!monitor.retainCandidate(at: outside, now: now.addingTimeInterval(0.31)), "Dismiss after the configured delay")
                let frame = TextLogic.panelFrame(anchor: badge, size: CGSize(width: 360, height: 84), visible: CGRect(x: 0, y: 0, width: 1100, height: 780))
                monitor.visibleCardFrame = { frame }
                let inside = CGPoint(x: frame.midX, y: frame.midY)
                @MainActor func stageAgain() {
                    monitor.stage(CapturedText(text: "Keep in Dock", bounds: .zero, method: "test"), sourceRect: source, pointer: pointer, demo: true)
                    DiagnosticCheck.require(monitor.retainCandidate(at: center, now: now))
                }
                model.closeDelay = 0
                stageAgain()
                DiagnosticCheck.require(monitor.retainCandidate(at: CGPoint(x: badge.maxX + 6, y: badge.minY - 6), now: now), "Keep the bridge before entering the popup")
                DiagnosticCheck.require(monitor.retainCandidate(at: inside, now: now), "Keep the popup while inside")
                DiagnosticCheck.require(!monitor.retainCandidate(at: pointer, now: now), "Zero delay closes immediately, even back over the source")
                model.closeDelay = 0.3
                stageAgain()
                DiagnosticCheck.require(monitor.retainCandidate(at: inside, now: now))
                DiagnosticCheck.require(monitor.retainCandidate(at: outside, now: now), "Start delayed close on exit")
                DiagnosticCheck.require(monitor.retainCandidate(at: inside, now: now.addingTimeInterval(0.2)), "Reentry cancels pending close")
                DiagnosticCheck.require(monitor.retainCandidate(at: outside, now: now.addingTimeInterval(0.3)))
                DiagnosticCheck.require(monitor.retainCandidate(at: outside, now: now.addingTimeInterval(0.59)), "Reentry resets the full close delay")
                DiagnosticCheck.require(!monitor.retainCandidate(at: outside, now: now.addingTimeInterval(0.61)), "Close when the restarted delay expires")
                stageAgain()
                model.pinned = true
                DiagnosticCheck.require(monitor.retainCandidate(at: outside, now: now.addingTimeInterval(10)), "Pinned cards ignore automatic close")
                model.dismiss(force: true)
                model.present(CapturedText(text: "Selected text", bounds: .zero, method: "test"), cocoaAnchor: source, selection: true)
                DiagnosticCheck.require(monitor.retainSelection(), "Selection toolbar must survive pointer movement across the gap, even with zero close delay")
                model.translate(to: "original")
                DiagnosticCheck.require(monitor.retainSelection(), "Selection result must remain available for copy and replacement")
                model.dismiss(force: true)
                DiagnosticCheck.require(!monitor.retainSelection(), "Explicit dismissal releases the selection toolbar")
                let destination = ReplacementTarget(element: AXUIElementCreateApplication(1), pid: 1,
                    edit: SelectionEdit(value: "你好，世界！", selected: "你好，世界！", range: NSRange(location: 0, length: 6)))
                model.present(CapturedText(text: "你好，世界！", bounds: .zero, method: "test"),
                              cocoaAnchor: source, selection: true, replacement: destination)
                DiagnosticCheck.require(model.hasReplacementTarget && !model.canReplaceSelection, "A selection must preview before replacing")
                model.translate(to: "original")
                DiagnosticCheck.require(!model.canReplaceSelection, "Original text must not enable replacement")
                model.target = "en"; model.result = "Hello, world!"; model.phase = .result
                DiagnosticCheck.require(model.canReplaceSelection && model.showsReplacementControls, "A translated editable selection exposes replacement")
                model.phase = .loading
                DiagnosticCheck.require(!model.canReplaceSelection, "An unfinished translation cannot replace text")
                model.phase = .result
                let clipboardCount = NSPasteboard.general.changeCount
                model.replaceSelection()
                DiagnosticCheck.require(model.isReplacing && !model.canReplaceSelection, "Prevent duplicate replacements")
                model.translate(to: "original")
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
                print("Selection-card checks passed: preview gating, original/translation tabs, read-only mode, busy state, invalid target and clipboard safety.")
                print("Capture safety and hover-flow checks passed: own-element and own-selection rejection, remote element acceptance, permission publication, badge opening, close delay, bridge, reentry and pinned cards.")
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
                    let result = try await TextCapture.recognize(image: image, region: region, at: CGPoint(x: x, y: y), word: args[1] == "--check-word-image")
                    let data = try JSONSerialization.data(withJSONObject: ["text": result?.text as Any? ?? NSNull()], options: [.sortedKeys])
                    print(String(decoding: data, as: UTF8.self))
                    exit(0)
                } catch { print(error.localizedDescription); exit(1) }
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
                        print("English → Chinese: \(try await engine.translate("Good design makes complex things feel simple.", target: "zh-Hans"))")
                        print("Chinese → English: \(try await engine.translate("保持好奇，总有更多值得发现。", target: "en"))")
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
