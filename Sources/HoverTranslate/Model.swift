import AppKit
import SwiftUI
import Translation
import ApplicationServices

enum TranslationRuntime {
    static func availability() -> LanguageAvailability {
        if #available(macOS 26.4, *) { return LanguageAvailability(preferredStrategy: .lowLatency) }
        return LanguageAvailability()
    }
    static func session(source: Locale.Language, target: Locale.Language) -> TranslationSession {
        if #available(macOS 26.4, *) { return TranslationSession(installedSource: source, target: target, preferredStrategy: .lowLatency) }
        return TranslationSession(installedSource: source, target: target)
    }
    static func configuration() -> TranslationSession.Configuration {
        let source = Locale.Language(identifier: "en")
        let target = Locale.Language(identifier: "zh-Hans")
        if #available(macOS 26.4, *) { return TranslationSession.Configuration(source: source, target: target, preferredStrategy: .lowLatency) }
        return TranslationSession.Configuration(source: source, target: target)
    }
}

enum TranslationIssue: LocalizedError {
    case languagePack, tooLong, unsupported
    var errorDescription: String? {
        switch self {
        case .languagePack: return "中英文语言包尚未准备好。打开设置，点击“准备语言包”后即可使用本机翻译。"
        case .tooLong: return "这段文字超过 8,000 字，请缩小选区后重试。"
        case .unsupported: return "本机翻译引擎暂不支持这一语言组合。"
        }
    }
}

@MainActor
final class LocalTranslator {
    private var cache: [String: String] = [:]
    private var keys: [String] = []

    func translate(_ text: String, target: String) async throws -> String {
        guard text.count <= 8000 else { throw TranslationIssue.tooLong }
        let source = TextLogic.language(of: text)
        if source == target { return text }
        let key = source + "|" + target + "|" + text
        if let cached = cache[key] { return cached }
        let from = Locale.Language(identifier: source)
        let to = Locale.Language(identifier: target)
        let status = await TranslationRuntime.availability().status(from: from, to: to)
        guard status != .unsupported else { throw TranslationIssue.unsupported }
        guard status == .installed else { throw TranslationIssue.languagePack }
        try Task.checkCancellation()
        let session = TranslationRuntime.session(source: from, target: to)
        let response = try await withTaskCancellationHandler {
            try await session.translate(text)
        } onCancel: {
            session.cancel()
        }
        try Task.checkCancellation()
        if keys.count >= 100, let oldest = keys.first { cache.removeValue(forKey: oldest); keys.removeFirst() }
        cache[key] = response.targetText
        keys.append(key)
        return response.targetText
    }
}

enum CardPhase { case choose, loading, result, failure }
@MainActor
final class AppModel: ObservableObject {
    @Published var page = "home"
    @Published var enabled = false
    @Published var hoverEnabled = true { didSet { UserDefaults.standard.set(hoverEnabled, forKey: "hoverEnabled") } }
    @Published var selectionEnabled = true { didSet { UserDefaults.standard.set(selectionEnabled, forKey: "selectionEnabled") } }
    @Published var ocrEnabled = true { didSet { UserDefaults.standard.set(ocrEnabled, forKey: "ocrEnabled") } }
    @Published var delay = 0.6 { didSet { UserDefaults.standard.set(delay, forKey: "hoverDelay") } }
    @Published var closeDelay = 0.0 { didSet { if persistSettings { UserDefaults.standard.set(closeDelay, forKey: "closeDelay") } } }
    @Published var wordMode = false { didSet { UserDefaults.standard.set(wordMode, forKey: "wordMode") } }
    @Published var accessibility = false
    @Published var screenPermission = false
    @Published var languageStatus = "检查中"
    @Published var languageReady = false
    @Published var preparationConfig: TranslationSession.Configuration?
    @Published var preparationMessage = ""
    @Published var preparing = false
    @Published var source = ""
    @Published var result = ""
    @Published var method = ""
    @Published var target = "zh-Hans"
    @Published var phase: CardPhase = .choose
    @Published var pinned = false
    @Published var copied = false
    @Published var status = "准备就绪"
    @Published var manualText = "Good design makes complex things feel simple."
    @Published private(set) var isReplacing = false
    @Published private(set) var replacementMessage = ""
    @Published private var replacementTarget: ReplacementTarget?
    private var replacementTask: Task<Void, Never>?
    private var replacementID = UUID()
    private let translator = LocalTranslator()
    private var translationTask: Task<Void, Never>?
    private var requestID = UUID()
    private var screenGuidancePending = false
    private var persistSettings = true
    var showCard: ((CGRect) -> Void)?
    var hideCard: (() -> Void)?
    var showWindow: (() -> Void)?
    var pointerInCard: (() -> Bool)?
    var stageHover: ((CapturedText, CGRect, CGPoint, Bool) -> Void)?
    var clearHover: (() -> Void)?
    var releasePanelFocus: (() -> Void)?
    var anchor = CGRect.zero
    private(set) var selectionVisible = false

    var hasReplacementTarget: Bool { selectionVisible && replacementTarget != nil }
    var showsReplacementControls: Bool { hasReplacementTarget || !replacementMessage.isEmpty }
    var canReplaceSelection: Bool {
        guard hasReplacementTarget, !isReplacing, phase == .result, target != "original",
              let replacementTarget, !result.isEmpty else { return false }
        return result != replacementTarget.edit.selected
    }

    func replaceSelection() {
        guard canReplaceSelection, let destination = replacementTarget else { return }
        let output = result
        let id = UUID()
        replacementID = id
        isReplacing = true
        replacementMessage = ""
        replacementTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Strictly validate the original selection; never reselect a stale span.
                let verified = try await TextReplacement.perform(destination, text: output,
                    stillCurrent: { self.replacementID == id },
                    releasePanelFocus: { self.releasePanelFocus?() })
                guard !Task.isCancelled, replacementID == id else { return }
                guard verified else {
                    replacementTarget = nil
                    isReplacing = false
                    replacementMessage = "无法确认替换结果，请检查输入框；未重复替换。"
                    return
                }
                dismiss(force: true)
                NSRunningApplication(processIdentifier: destination.pid)?.activate()
                status = "已替换选中文字 · 可在原输入框按 ⌘Z 撤销"
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled, replacementID == id else { return }
                replacementTarget = nil
                isReplacing = false
                replacementMessage = error.localizedDescription
            }
        }
    }

    private func clearReplacement() {
        replacementTask?.cancel()
        replacementTask = nil
        replacementID = UUID()
        replacementTarget = nil
        isReplacing = false
        replacementMessage = ""
    }

    init(checkPermissions: Bool = true) {
        persistSettings = checkPermissions
        let d = UserDefaults.standard
        if d.object(forKey: "hoverDelay") != nil { delay = min(1.5, max(0.3, d.double(forKey: "hoverDelay"))) }
        if d.object(forKey: "closeDelay") != nil { closeDelay = min(1, max(0, d.double(forKey: "closeDelay"))) }
        if d.object(forKey: "hoverEnabled") != nil { hoverEnabled = d.bool(forKey: "hoverEnabled") }
        if d.object(forKey: "selectionEnabled") != nil { selectionEnabled = d.bool(forKey: "selectionEnabled") }
        if d.object(forKey: "ocrEnabled") != nil { ocrEnabled = d.bool(forKey: "ocrEnabled") }
        wordMode = d.bool(forKey: "wordMode")
        if checkPermissions {
            enabled = d.bool(forKey: "globalEnabled")
            refreshPermissions()
            if enabled { updatePermissionStatus() }
        }
        Task { await refreshLanguage() }
    }

    func refreshPermissions() {
        applyPermissions(accessibility: AXIsProcessTrusted(), screen: CGPreflightScreenCaptureAccess())
    }

    func recheckPermissions() {
        refreshPermissions()
        status = accessibility ? "系统取词权限已生效" : "当前版本的取词权限尚未生效 · 请确认添加的是当前浮译应用"
    }

    var cardWidth: CGFloat { CardLayout.width(source: source, result: phase == .result ? result : "") }
    var showsCardSource: Bool { target != "original" && !source.isEmpty }
    var cardBodyHeight: CGFloat {
        CardLayout.bodyHeight(result: result, width: cardWidth, loading: phase == .loading,
                              choosing: phase == .choose, failure: phase == .failure)
    }
    var cardHeight: CGFloat {
        CardLayout.headerHeight + 14 + (showsCardSource ? 20 : 0) + cardBodyHeight
            + (showsReplacementControls ? 34 : 0) + (replacementMessage.isEmpty ? 0 : 30)
    }

    func applyPermissions(accessibility trusted: Bool, screen allowed: Bool) {
        let changed = accessibility != trusted || screenPermission != allowed
        // Equal @Published assignments still invalidate SwiftUI layout.
        if accessibility != trusted { accessibility = trusted }
        if screenPermission != allowed { screenPermission = allowed }
        if enabled, changed { updatePermissionStatus() }
    }

    func refreshLanguage() async {
        let availability = TranslationRuntime.availability()
        let forward = await availability.status(from: Locale.Language(identifier: "en"), to: Locale.Language(identifier: "zh-Hans"))
        let reverse = await availability.status(from: Locale.Language(identifier: "zh-Hans"), to: Locale.Language(identifier: "en"))
        languageReady = forward == .installed && reverse == .installed
        languageStatus = languageReady ? "已就绪 · 离线可用" : (forward == .unsupported || reverse == .unsupported ? "当前系统不支持" : "需要准备语言包")
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacy("Accessibility")
    }

    func requestScreen() {
        page = "settings"
        _ = CGRequestScreenCaptureAccess()
        openPrivacy("ScreenCapture")
    }

    var applicationPath: String { Bundle.main.bundleURL.path }

    func revealApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func copyApplicationPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(applicationPath, forType: .string)
        status = "已复制浮译应用路径 · 在添加窗口按 ⇧⌘G 后粘贴"
    }

    func openPrivacy(_ section: String) {
        let current = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_" + section
        if let url = URL(string: current), NSWorkspace.shared.open(url) { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_" + section) { NSWorkspace.shared.open(url) }
    }

    func prepareLanguage() {
        preparing = true
        preparationMessage = "请在系统弹窗中确认下载；准备期间保持此窗口打开。"
        let config = TranslationRuntime.configuration()
        if preparationConfig == config { preparationConfig?.invalidate() } else { preparationConfig = config }
    }

    func toggleEnabled() {
        enabled.toggle()
        if persistSettings { UserDefaults.standard.set(enabled, forKey: "globalEnabled") }
        if !enabled { screenGuidancePending = false; dismiss(force: true) }
        refreshPermissions()
        updatePermissionStatus()
        if enabled {
            screenGuidancePending = ocrEnabled && !screenPermission
            if !accessibility {
                page = "settings"
                requestAccessibility()
            } else if screenGuidancePending {
                screenGuidancePending = false
                requestScreen()
            }
        }
    }

    func continuePermissionSetup() {
        refreshPermissions()
        guard enabled, accessibility, screenGuidancePending else { return }
        screenGuidancePending = false
        if ocrEnabled && !screenPermission { requestScreen() }
    }

    private func updatePermissionStatus() {
        if !enabled { status = "全局翻译已暂停" }
        else if !accessibility { status = "请在隐私权限页开启“浮译”（设备控制与数据访问 / 辅助功能）" }
        else if ocrEnabled && !screenPermission { status = "覆盖范围受限 · 系统选项和图片需要识图授权，请打开偏好设置" }
        else { status = "等待英文悬停 · 移到“译”图标查看译文" }
    }

    func present(_ capture: CapturedText, cocoaAnchor: CGRect, selection: Bool, replacement: ReplacementTarget? = nil) {
        guard !pinned else { return }
        clearReplacement()
        if selection { clearHover?() }
        selectionVisible = selection
        replacementTarget = selection ? replacement : nil
        translationTask?.cancel()
        requestID = UUID()
        source = capture.text
        method = capture.method
        anchor = cocoaAnchor
        result = ""
        copied = false
        pinned = false
        phase = selection ? .choose : .loading
        target = "zh-Hans"
        showCard?(anchor)
        if !selection { translate(to: "zh-Hans") }
    }

    func translate(to language: String) {
        guard !isReplacing else { return }
        translationTask?.cancel()
        let id = UUID()
        requestID = id
        target = language
        copied = false
        if language == "original" { result = source; phase = .result; return }
        let input = source
        result = ""
        phase = .loading
        translationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let output = try await translator.translate(input, target: language)
                guard !Task.isCancelled, requestID == id else { return }
                result = output; phase = .result; status = "翻译完成"
            } catch is CancellationError {
                // Pointer movement and language changes intentionally cancel old requests.
            } catch {
                guard !Task.isCancelled, requestID == id else { return }
                result = error.localizedDescription; phase = .failure; status = "翻译未完成"
            }
        }
    }

    func dismiss(force: Bool = false) {
        guard force || !pinned else { return }
        clearReplacement()
        selectionVisible = false
        translationTask?.cancel()
        requestID = UUID()
        pinned = false
        hideCard?()
        clearHover?()
    }

    func copyResult() {
        let text = phase == .result ? result : source
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
    }

    func clipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !TextLogic.clean(text).isEmpty else {
            status = "剪贴板中没有文字"; showWindow?(); return
        }
        let mouse = NSEvent.mouseLocation
        present(CapturedText(text: TextLogic.clean(text), bounds: .zero, method: "剪贴板 · 手动触发"),
                cocoaAnchor: CGRect(origin: mouse, size: CGSize(width: 8, height: 18)), selection: true)
    }

    func manualTranslate() {
        let text = TextLogic.clean(manualText)
        guard !text.isEmpty else { return }
        let rect = NSApp.keyWindow.map { CGRect(x: $0.frame.midX - 200, y: $0.frame.midY + 80, width: 400, height: 30) }
            ?? CGRect(origin: NSEvent.mouseLocation, size: CGSize(width: 20, height: 20))
        dismiss(force: true)
        present(CapturedText(text: text, bounds: .zero, method: "文字试用 · 本机翻译"), cocoaAnchor: rect, selection: true)
    }

    func settings() { page = "settings"; showWindow?() }

    func preview(_ english: String, bounds: CGRect) {
        guard !pinned else { return }
        dismiss(force: true)
        stageHover?(CapturedText(text: english, bounds: .zero, method: "本机翻译 · 交互试用"), bounds, NSEvent.mouseLocation, true)
    }
}
