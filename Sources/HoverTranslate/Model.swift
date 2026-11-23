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
    static func configuration(source: String, target: String) -> TranslationSession.Configuration {
        let source = Locale.Language(identifier: source)
        let target = Locale.Language(identifier: target)
        if #available(macOS 26.4, *) { return TranslationSession.Configuration(source: source, target: target, preferredStrategy: .lowLatency) }
        return TranslationSession.Configuration(source: source, target: target)
    }
}

enum TranslationIssue: LocalizedError {
    case languagePack(source: String, target: String), tooLong, unsupported(source: String, target: String)
    var errorDescription: String? {
        switch self {
        case let .languagePack(source, target):
            return "\(TextLogic.displayName(source)) → \(TextLogic.displayName(target)) 语言包尚未下载，下载后即可离线翻译。"
        case .tooLong: return "这段文字超过 8,000 字，请缩小选区后重试。"
        case let .unsupported(source, target):
            return "本机翻译暂不支持 \(TextLogic.displayName(source)) → \(TextLogic.displayName(target))。"
        }
    }
}

@MainActor
final class LocalTranslator {
    private var cache: [String: String] = [:]
    private var keys: [String] = []

    func cached(provider: AIProvider, text: String, from source: String, to target: String) -> String? {
        cache[provider.rawValue + "|" + source + "|" + target + "|" + text]
    }

    func store(_ output: String, provider: AIProvider, text: String, from source: String, to target: String) {
        let key = provider.rawValue + "|" + source + "|" + target + "|" + text
        if cache[key] == nil {
            if keys.count >= 100, let oldest = keys.first { cache.removeValue(forKey: oldest); keys.removeFirst() }
            keys.append(key)
        }
        cache[key] = output
    }

    func translate(_ text: String, from source: String, to target: String) async throws -> String {
        guard text.count <= 8000 else { throw TranslationIssue.tooLong }
        if source == target { return text }
        if let cached = cached(provider: .apple, text: text, from: source, to: target) { return cached }
        let from = Locale.Language(identifier: source)
        let to = Locale.Language(identifier: target)
        let status = await TranslationRuntime.availability().status(from: from, to: to)
        guard status != .unsupported else { throw TranslationIssue.unsupported(source: source, target: target) }
        guard status == .installed else { throw TranslationIssue.languagePack(source: source, target: target) }
        try Task.checkCancellation()
        let session = TranslationRuntime.session(source: from, target: to)
        let response = try await withTaskCancellationHandler {
            try await session.translate(text)
        } onCancel: {
            session.cancel()
        }
        try Task.checkCancellation()
        store(response.targetText, provider: .apple, text: text, from: source, to: target)
        return response.targetText
    }
}

enum CardPhase { case idle, loading, result, failure }
@MainActor
final class AppModel: ObservableObject {
    @Published var provider = AIProvider.apple {
        didSet { defaults?.set(provider.rawValue, forKey: "translationProvider") }
    }
    @Published var availableProviders: [AIProvider] = [.apple]
    @Published var checkingProviders = false
    @Published var providerCheckMessage = ""
    var capturingRegion = false
    func refreshProviders(interactive: Bool = false) async {
        guard !checkingProviders else { return }
        checkingProviders = true
        if interactive { providerCheckMessage = "正在检测本机 AI 登录状态…" }
        defer { checkingProviders = false }
        async let codexReady = AIProvider.codex.authenticated()
        async let claudeReady = AIProvider.claude.authenticated()
        var providers = [AIProvider.apple]
        if await codexReady { providers.append(.codex) }
        if await claudeReady { providers.append(.claude) }
        if availableProviders != providers { availableProviders = providers }
        if interactive {
            let detected = providers.filter { $0 != .apple }.map(\.rawValue)
            providerCheckMessage = detected.isEmpty
                ? "未检测到已登录的 Codex 或 Claude 客户端。"
                : "已检测到可用服务：" + detected.joined(separator: "、")
        }
    }
    @Published var page = "home"
    @Published var enabled = false
    @Published var hoverEnabled = true { didSet { defaults?.set(hoverEnabled, forKey: "hoverEnabled") } }
    @Published var ocrEnabled = true { didSet { defaults?.set(ocrEnabled, forKey: "ocrEnabled") } }
    @Published var delay = 0.6 { didSet { defaults?.set(delay, forKey: "hoverDelay") } }
    @Published var closeDelay = 0.0 { didSet { defaults?.set(closeDelay, forKey: "closeDelay") } }
    @Published var wordMode = false { didSet { defaults?.set(wordMode, forKey: "wordMode") } }
    /// Hover ignores text in this language; selection still offers translation.
    @Published var nativeLanguage = "zh-Hans" {
        didSet { defaults?.set(nativeLanguage, forKey: "nativeLanguage") }
    }
    @Published var targetLanguage = "zh-Hans" {
        didSet {
            defaults?.set(targetLanguage, forKey: "targetLanguage")
            Task { await refreshLanguage() }
        }
    }
    @Published var japaneseKanji = false { didSet { defaults?.set(japaneseKanji, forKey: "japaneseKanji") } }
    @Published var sourceLanguage = "en"
    @Published private(set) var missingPack: (source: String, target: String)?
    @Published var accessibility = false
    @Published var screenPermission = false
    @Published var languageReady = false
    @Published var preparationConfig: TranslationSession.Configuration?
    @Published var preparationMessage = ""
    @Published var preparing = false
    /// Pack status for each source language into the current target.
    @Published var packStatus: [String: LanguageAvailability.Status] = [:]
    @Published var preparingSource: String?
    @Published var preparingTarget: String?
    /// The language currently shown in the settings pack menu.
    @Published var selectedPack = "ja"
    @Published var source = ""
    @Published var result = ""
    @Published var method = ""
    @Published var target = "zh-Hans"
    @Published var phase: CardPhase = .idle
    @Published var pinned = false
    @Published var copied = false
    @Published var copiedSource = false
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
    /// nil in diagnostics: checks neither read nor overwrite the user's settings.
    private let defaults: UserDefaults?
    var showCard: ((CGRect) -> Void)?
    var hideCard: (() -> Void)?
    var startScreenshot: (() -> Void)?
    var showWindow: (() -> Void)?
    var pointerInCard: (() -> Bool)?
    var stageHover: ((CapturedText, CGRect, CGPoint, Bool) -> Void)?
    var clearHover: (() -> Void)?
    var releasePanelFocus: (() -> Void)?
    var anchor = CGRect.zero
    private(set) var selectionVisible = false
    private(set) var isPresenting = false

    var hasReplacementTarget: Bool { selectionVisible && replacementTarget != nil }
    var showsReplacementControls: Bool { hasReplacementTarget || !replacementMessage.isEmpty }
    var canReplaceSelection: Bool {
        guard hasReplacementTarget, !isReplacing, phase == .result,
              let replacementTarget, !result.isEmpty else { return false }
        return TextLogic.clean(result) != TextLogic.clean(replacementTarget.edit.selected)
    }

    func replaceSelection() {
        guard canReplaceSelection, let destination = replacementTarget else { return }
        let output = TextLogic.preservingEdgeWhitespace(of: destination.edit.selected, around: result)
        let id = UUID()
        replacementID = id
        isReplacing = true
        if !replacementMessage.isEmpty { replacementMessage = "" }
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
        if replacementTarget != nil { replacementTarget = nil }
        if isReplacing { isReplacing = false }
        if !replacementMessage.isEmpty { replacementMessage = "" }
    }

    init(checkPermissions: Bool = true) {
        defaults = checkPermissions ? .standard : nil
        if let d = defaults {
            if d.object(forKey: "hoverDelay") != nil { delay = min(1.5, max(0.3, d.double(forKey: "hoverDelay"))) }
            if d.object(forKey: "closeDelay") != nil { closeDelay = min(1, max(0, d.double(forKey: "closeDelay"))) }
            if d.object(forKey: "hoverEnabled") != nil { hoverEnabled = d.bool(forKey: "hoverEnabled") }
            if d.object(forKey: "ocrEnabled") != nil { ocrEnabled = d.bool(forKey: "ocrEnabled") }
            provider = AIProvider(rawValue: d.string(forKey: "translationProvider") ?? "") ?? .apple
            Task { await refreshProviders() }
            japaneseKanji = d.bool(forKey: "japaneseKanji")
            wordMode = d.bool(forKey: "wordMode")
            if let native = d.string(forKey: "nativeLanguage") { nativeLanguage = native }
            if let preferred = d.string(forKey: "targetLanguage") { targetLanguage = preferred }
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

    var subtitleText: String { phase == .loading ? "正在翻译…" : result.components(separatedBy: .newlines).joined(separator: " ") }
    var cardWidth: CGFloat {
        let headerLabels = TextLogic.displayName(sourceLanguage) + " → " + TextLogic.displayName(target)
        let labelWidth = ceil((headerLabels as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width)
        let buttonsWidth: CGFloat = method == "截图 OCR" ? 94 : 70
        let headerMinimum = max(CardLayout.minimumWidth, ceil(14 + 17 + 18 + labelWidth + 24 + buttonsWidth + 8))
        return CardLayout.width(source: source, result: phase == .result ? result : "", minimumWidth: headerMinimum)
    }
    var cardSourceHeight: CGFloat { CardLayout.sourceHeight(source: source, width: cardWidth) }
    var cardBodyHeight: CGFloat {
        CardLayout.bodyHeight(result: result, width: cardWidth, loading: phase == .loading,
                              choosing: phase == .idle, failure: phase == .failure)
    }
    /// Header, source, divider (8 + 1 + 9), translation, bottom padding, replacement bar.
    var cardHeight: CGFloat {
        CardLayout.headerHeight + cardSourceHeight + 18 + cardBodyHeight + 14
            + (showsReplacementControls ? 38 : 0) + (replacementMessage.isEmpty ? 0 : 30)
    }

    func applyPermissions(accessibility trusted: Bool, screen allowed: Bool) {
        let changed = accessibility != trusted || screenPermission != allowed
        // Equal @Published assignments still invalidate SwiftUI layout.
        if accessibility != trusted { accessibility = trusted }
        if screenPermission != allowed { screenPermission = allowed }
        if enabled, changed { updatePermissionStatus() }
    }

    var preparationSource: String { TextLogic.sameLanguage(targetLanguage, "en") ? "zh-Hans" : "en" }

    func refreshLanguage() async {
        let availability = TranslationRuntime.availability()
        let target = targetLanguage
        var packs: [String: LanguageAvailability.Status] = [:]
        for language in TextLogic.languages where !TextLogic.sameLanguage(language.id, target) {
            packs[language.id] = await availability.status(from: Locale.Language(identifier: language.id), to: Locale.Language(identifier: target))
        }
        guard target == targetLanguage else { return }
        let ready = packs.values.contains(.installed)
        if languageReady != ready { languageReady = ready }
        if packStatus != packs { packStatus = packs }
    }

    /// System Settings shows real download progress; the in-app sheet does not.
    func openSystemTranslationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") { NSWorkspace.shared.open(url) }
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
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

    func prepareLanguage(source: String? = nil, target: String? = nil) {
        let src = source ?? preparationSource
        let dst = target ?? targetLanguage
        preparing = true
        preparingSource = src
        preparingTarget = dst
        preparationMessage = "请在弹窗中确认下载（\(TextLogic.displayName(src)) → \(TextLogic.displayName(dst))），期间保持此窗口打开。弹窗长时间不动时可关掉，改用“在系统设置中下载”，那里能看到进度。"
        let config = TranslationRuntime.configuration(source: src, target: dst)
        if preparationConfig == config { preparationConfig?.invalidate() } else { preparationConfig = config }
    }

    func toggleEnabled() {
        enabled.toggle()
        defaults?.set(enabled, forKey: "globalEnabled")
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
        else { status = "等待悬停外语" }
    }

    func present(_ capture: CapturedText, cocoaAnchor: CGRect, selection: Bool, replacement: ReplacementTarget? = nil) {
        guard !pinned else { return }
        clearReplacement()
        if selection { clearHover?() }
        isPresenting = true
        selectionVisible = selection
        let nextReplacement = selection ? replacement : nil
        if (replacementTarget == nil) != (nextReplacement == nil) || nextReplacement != nil {
            replacementTarget = nextReplacement
        }
        translationTask?.cancel()
        translationTask = nil
        requestID = UUID()
        source = capture.text
        method = capture.method
        anchor = cocoaAnchor
        copiedSource = false
        if pinned { pinned = false }
        sourceLanguage = TextLogic.language(of: capture.text, japaneseKanji: japaneseKanji)
        let resolvedTarget = TextLogic.target(for: sourceLanguage, preferred: targetLanguage, native: nativeLanguage)
        target = resolvedTarget
        result = ""
        phase = .loading
        showCard?(anchor)
        translate(to: resolvedTarget)
    }

    func translate(to language: String) {
        guard !isReplacing else { return }
        translationTask?.cancel()
        let id = UUID()
        requestID = id
        if target != language { target = language }
        if copied { copied = false }
        if missingPack != nil { missingPack = nil }
        let input = source, from = sourceLanguage, activeProvider = provider
        if let cached = translator.cached(provider: activeProvider, text: input, from: from, to: language) {
            result = cached
            phase = .result
            status = "翻译完成"
            return
        }
        if !result.isEmpty { result = "" }
        if phase != .loading { phase = .loading }
        translationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let output: String
                if activeProvider == .apple {
                    output = try await translator.translate(input, from: from, to: language)
                } else {
                    output = try await activeProvider.translate(input, from: from, to: language)
                    translator.store(output, provider: activeProvider, text: input, from: from, to: language)
                }
                guard !Task.isCancelled, requestID == id else { return }
                result = output; phase = .result; status = "翻译完成"
            } catch is CancellationError {
                // Pointer movement and language changes intentionally cancel old requests.
            } catch {
                guard !Task.isCancelled, requestID == id else { return }
                if case let TranslationIssue.languagePack(source, target) = error { missingPack = (source, target) }
                result = error.localizedDescription; phase = .failure; status = "翻译未完成"
            }
        }
    }

    func dismiss(force: Bool = false) {
        guard force || !pinned else { return }
        let hasState = isPresenting || selectionVisible || translationTask != nil
            || replacementTarget != nil || isReplacing || !replacementMessage.isEmpty
            || pinned || missingPack != nil
        guard hasState else {
            clearHover?()
            return
        }
        clearReplacement()
        isPresenting = false
        selectionVisible = false
        translationTask?.cancel()
        translationTask = nil
        requestID = UUID()
        if pinned { pinned = false }
        if missingPack != nil { missingPack = nil }
        hideCard?()
        clearHover?()
    }

    func copyResult() {
        let text = phase == .result ? result : source
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
    }

    func copySource() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(source, forType: .string)
        copiedSource = true
        status = "已复制提取的原文"
    }

    func clipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !TextLogic.clean(text).isEmpty else {
            status = "剪贴板中没有文字"; showWindow?(); return
        }
        dismiss(force: true)
        let mouse = NSEvent.mouseLocation
        present(CapturedText(text: TextLogic.clean(text), bounds: .zero, method: "剪贴板 · 手动触发"),
                cocoaAnchor: CGRect(origin: mouse, size: CGSize(width: 8, height: 18)), selection: true)
    }

    func presentSelection(_ text: String) {
        let cleaned = TextLogic.clean(text)
        guard !cleaned.isEmpty else { return }
        dismiss(force: true)
        present(CapturedText(text: cleaned, bounds: .zero, method: "右键选区"),
                cocoaAnchor: CGRect(origin: NSEvent.mouseLocation, size: CGSize(width: 1, height: 1)), selection: true)
    }

    func manualTranslate() {
        let text = TextLogic.clean(manualText)
        guard !text.isEmpty else { return }
        let rect = NSApp.keyWindow.map { CGRect(x: $0.frame.midX - 200, y: $0.frame.midY + 80, width: 400, height: 30) }
            ?? CGRect(origin: NSEvent.mouseLocation, size: CGSize(width: 20, height: 20))
        dismiss(force: true)
        present(CapturedText(text: text, bounds: .zero, method: "文字试用"), cocoaAnchor: rect, selection: true)
    }

    func settings() { page = "settings"; showWindow?() }

    /// Translation downloads run through the main window's translation task.
    func downloadMissingPack() {
        guard let pack = missingPack else { return }
        dismiss(force: true)
        settings()
        if TextLogic.sameLanguage(pack.target, targetLanguage) {
            selectedPack = pack.source
            Task { await refreshLanguage() }
            preparationMessage = "\(TextLogic.displayName(pack.source)) → \(TextLogic.displayName(pack.target)) 需要下载：点下方“下载”，或在系统设置中下载。"
        } else {
            // Do not overwrite the user's preferred targetLanguage; prepare the exact missing pair directly.
            prepareLanguage(source: pack.source, target: pack.target)
        }
    }

    func preview(_ english: String, bounds: CGRect) {
        guard !pinned else { return }
        dismiss(force: true)
        stageHover?(CapturedText(text: english, bounds: .zero, method: "本机翻译 · 交互试用"), bounds, NSEvent.mouseLocation, true)
    }
}
