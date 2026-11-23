import SwiftUI
import AppKit
import Translation

struct MainView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Coss.sidebarBorder).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    Group {
                        if model.page == "settings" { SettingsView(model: model) }
                        else if model.page == "snippets" { SnippetsView(model: model) }
                        else if model.page == "try" { TryView(model: model) }
                        else { HomeView(model: model) }
                    }
                    .padding(.horizontal, 40).padding(.top, 46).padding(.bottom, 32)
                    .frame(maxWidth: 860, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                HStack(spacing: 10) {
                    Circle()
                        .fill(model.enabled ? Coss.success : Coss.mutedForeground.opacity(0.5))
                        .frame(width: 6, height: 6)
                    Text(model.status)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Coss.mutedForeground)
                        .lineLimit(1)
                    Spacer()
                    CossKbd(keys: "⌃⌥T", label: "译选区")
                    CossKbd(keys: "⌥S", label: "截图翻译")
                }
                .padding(.horizontal, 40).padding(.vertical, 11)
                .background(Coss.sidebar)
                .overlay(alignment: .top) { Rectangle().fill(Coss.sidebarBorder).frame(height: 1) }
            }
            .background(Coss.background)
        }
        .frame(minWidth: 1040, minHeight: 740)
        .foregroundStyle(Coss.foreground)
        .translationTask(model.preparationConfig) { session in
            let targetSource = model.preparingSource
            let targetDest = model.preparingTarget ?? model.targetLanguage
            do {
                try await session.prepareTranslation()
                await model.refreshLanguage()
                let installed: Bool
                if let targetSource {
                    let status = await TranslationRuntime.availability().status(
                        from: Locale.Language(identifier: targetSource),
                        to: Locale.Language(identifier: targetDest)
                    )
                    installed = status == .installed
                } else {
                    installed = model.languageReady
                }
                model.preparationMessage = installed
                    ? "语言包已下载，可以开始翻译。"
                    : "语言包尚未完成下载；如已取消，可重新点击“下载”或在系统设置中查看进度。"
            } catch {
                model.preparationMessage = "准备失败：" + error.localizedDescription
                await model.refreshLanguage()
            }
            model.preparing = false
            model.preparingSource = nil
            model.preparingTarget = nil
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.6.1"
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("译")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Coss.primaryForeground)
                    .frame(width: 34, height: 34)
                    .background(Coss.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Coss.innerHighlight, lineWidth: 0.5)
                            .padding(0.5)
                    )
                    .shadow(color: Coss.subtleShadow, radius: 3, y: 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text("浮译").font(.system(size: 16, weight: .semibold)).tracking(-0.3)
                    Text("Hover Translate").font(.system(size: 10, weight: .medium)).foregroundStyle(Coss.mutedForeground)
                }
            }
            .padding(.horizontal, 6).padding(.bottom, 28)

            nav("home", "开始使用", "sparkles")
            nav("snippets", "摘录本", "bookmark", badge: model.snippets.isEmpty ? nil : "\(model.snippets.count)")
            nav("try", "翻译试用", "text.bubble")
            nav("settings", "偏好设置", "slider.horizontal.3")
            Spacer()
            powerCard
            Text("v\(appVersion) · \(model.provider.rawValue)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Coss.mutedForeground)
                .padding(.top, 12).padding(.horizontal, 6)
        }
        .padding(.horizontal, 14).padding(.top, 50).padding(.bottom, 18)
        .frame(width: 224)
        .background(Coss.sidebar)
    }

    private var powerCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.enabled ? Coss.success : Coss.mutedForeground.opacity(0.45))
                        .frame(width: 6, height: 6)
                    Text("全局翻译").font(.system(size: 12, weight: .semibold))
                }
                Spacer()
                Toggle("全局翻译", isOn: Binding(get: { model.enabled }, set: { _ in model.toggleEnabled() }))
                    .toggleStyle(.switch).labelsHidden().tint(Coss.primary).controlSize(.mini)
            }
            Text(model.enabled ? "悬停外语、划词工具栏已启用" : "已暂停，不会读取屏幕文字")
                .font(.system(size: 10.5))
                .foregroundStyle(Coss.mutedForeground)
                .lineSpacing(2)
            HStack(spacing: 5) {
                CossBadge(text: TextLogic.displayName(model.nativeLanguage), tone: .neutral)
                Text("→").font(.system(size: 9.5)).foregroundStyle(Coss.mutedForeground)
                CossBadge(text: TextLogic.displayName(model.targetLanguage), tone: .neutral)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Coss.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Coss.border, lineWidth: 1)
        )
        .shadow(color: Coss.subtleShadow, radius: 2, y: 1)
    }

    private func nav(_ id: String, _ title: String, _ symbol: String, badge: String? = nil) -> some View {
        let active = model.page == id
        return Button { model.page = id } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(active ? Coss.foreground : Coss.mutedForeground)
                Text(title)
                    .font(.system(size: 13, weight: active ? .medium : .regular))
                    .foregroundStyle(active ? Coss.foreground : Coss.mutedForeground)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(active ? Coss.foreground : Coss.mutedForeground)
                        .padding(.horizontal, 6).padding(.vertical, 1.5)
                        .background(Coss.muted)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(active ? Coss.card : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(active ? Coss.border : .clear, lineWidth: 1)
            )
            .shadow(color: active ? Coss.subtleShadow : .clear, radius: 1.5, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 3)
    }
}

struct SectionHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Coss.mutedForeground)
            Text(title)
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.7)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Coss.mutedForeground)
                .lineSpacing(3.5)
        }
    }
}

struct HomeView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeading(
                eyebrow: "OVERVIEW",
                title: "停一下，就读懂。",
                subtitle: "悬停查看一行译文，划词弹出快捷工具栏，按 ⌥S 随时截图翻译。原文自动识别，默认译成\(TextLogic.displayName(model.targetLanguage))。"
            )
            HStack(alignment: .top, spacing: 18) {
                browserPreview
                VStack(alignment: .leading, spacing: 18) {
                    step("1", "悬停外语", "停留片刻显示一行译文；\(TextLogic.displayName(model.nativeLanguage))文字不打扰。")
                    step("2", "划词工具栏", "拖选或双击出现「翻译 / 复制 / 保存」图标，也可按 ⌃⌥T 直接翻译。")
                    step("3", "截图翻译 ⌥S", "全局按 ⌥S 框选任意区域，自动合段识别并翻译。")
                    Spacer(minLength: 0)
                    Button { model.startScreenshot?() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "viewfinder").font(.system(size: 12))
                            Text("截图翻译")
                            Text("⌥S").font(.system(size: 10.5, design: .monospaced)).opacity(0.75)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CossButtonStyle(variant: .primary))
                    Button { model.page = "try" } label: {
                        HStack(spacing: 6) {
                            Text("试试自己的文字")
                            Image(systemName: "arrow.right").font(.system(size: 11))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CossButtonStyle(variant: .outline))
                }
                .padding(.vertical, 4).frame(width: 218, alignment: .leading)
            }
            HStack(spacing: 12) {
                feature("globe", "多语种识别", "自动识别英、日、韩、法、德等 20 种语言")
                feature("bookmark", "一键摘录保存", "存入内置摘录本并追加到本地 Markdown")
                feature("lock", "本地优先", "默认 Apple 离线翻译，可选本机 AI CLI")
            }
            CossCard(padding: 15) {
                HStack(spacing: 13) {
                    CossIconTile(symbol: ready ? "checkmark.seal" : "exclamationmark.triangle", size: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(ready ? "取词、识图与翻译均已就绪" : "还差一步 · 检查权限与翻译服务")
                                .font(.system(size: 13, weight: .semibold))
                            CossBadge(text: ready ? "就绪" : "待配置", tone: ready ? .success : .warning)
                        }
                        Text("取词 \(model.accessibility ? "已授权" : "待授权")  ·  识图 \(!model.ocrEnabled ? "已关闭" : (model.screenPermission ? "已授权" : "待授权"))  ·  \(model.provider.rawValue)")
                            .font(.system(size: 11.5)).foregroundStyle(Coss.mutedForeground)
                    }
                    Spacer()
                    Button("检查设置") { model.page = "settings" }
                        .buttonStyle(CossButtonStyle(variant: .outline))
                }
            }
        }
    }

    private var ready: Bool {
        model.accessibility
            && (model.provider == .apple ? model.languageReady : model.availableProviders.contains(model.provider))
            && (!model.ocrEnabled || model.screenPermission)
    }

    private var browserPreview: some View {
        CossCardFrame(contentPadding: 20) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Coss.border).frame(width: 8, height: 8)
                }
                Spacer()
                CossBadge(text: "交互预览", tone: .outline)
            }
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                Text("THE QUIET INTERNET")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Coss.mutedForeground)
                    .modifier(PreviewHover(model: model, text: "THE QUIET INTERNET"))
                Text("Read without breaking\nyour flow.")
                    .font(.system(size: 23, weight: .semibold))
                    .tracking(-0.5)
                    .lineSpacing(1)
                    .modifier(PreviewHover(model: model, text: "Read without breaking your flow."))
                DemoSentence(model: model, english: "Good design makes complex things feel simple.")
                DemoSentence(model: model, english: "Stay curious. There is always more to discover.")
                HStack(spacing: 6) {
                    Image(systemName: "cursorarrow.rays").font(.system(size: 10.5))
                    Text("悬停在句子上体验实时译文，或拖选文字体验工具栏").font(.system(size: 11))
                }
                .foregroundStyle(Coss.mutedForeground)
                .padding(.top, 2)
            }
        }
    }

    private func step(_ n: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Coss.foreground)
                .frame(width: 22, height: 22)
                .background(Coss.muted)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Coss.border, lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text).font(.system(size: 11.5)).foregroundStyle(Coss.mutedForeground).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        CossCard(padding: 15) {
            CossIconTile(symbol: symbol, size: 28).padding(.bottom, 10)
            Text(title).font(.system(size: 13, weight: .semibold)).padding(.bottom, 3)
            Text(text).font(.system(size: 11.5)).foregroundStyle(Coss.mutedForeground).lineSpacing(2.5)
        }
    }
}

@MainActor
final class DemoInteraction: ObservableObject {
    var task: Task<Void, Never>?
}

struct DemoSentence: View {
    @ObservedObject var model: AppModel
    let english: String
    var body: some View {
        Text(english)
            .font(.system(size: 13))
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(Coss.frame)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Coss.border, lineWidth: 1))
            .modifier(PreviewHover(model: model, text: english))
    }
}

private struct PreviewHover: ViewModifier {
    @ObservedObject var model: AppModel
    let text: String
    @StateObject private var interaction = DemoInteraction()

    func body(content: Content) -> some View {
        content.textSelection(.enabled)
            .background(HoverSampleSensor { inside, rect in
                interaction.task?.cancel()
                if inside {
                    interaction.task = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64(model.delay * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        model.preview(text, bounds: rect)
                    }
                }
            })
            .onDisappear { interaction.task?.cancel() }
    }
}

struct HoverSampleSensor: NSViewRepresentable {
    let changed: (Bool, CGRect) -> Void
    func makeNSView(context: Context) -> SensorView {
        let view = SensorView()
        view.changed = changed
        return view
    }
    func updateNSView(_ nsView: SensorView, context: Context) { nsView.changed = changed }
    final class SensorView: NSView {
        var changed: ((Bool, CGRect) -> Void)?
        private var area: NSTrackingArea?
        private var inside = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let tracking = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(tracking)
            area = tracking
        }

        private var screenRect: CGRect {
            guard let window else { return .zero }
            return window.convertToScreen(convert(bounds, to: nil))
        }

        override func mouseEntered(with event: NSEvent) {
            guard !inside, NSEvent.pressedMouseButtons == 0 else { return }
            inside = true
            changed?(true, screenRect)
        }

        override func mouseExited(with event: NSEvent) {
            guard inside else { return }
            inside = false
            changed?(false, screenRect)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil && inside {
                inside = false
                changed?(false, .zero)
            }
        }
    }
}

/// Coss UI Tooltip / Toast pill for inline hover translation and quick feedback.
struct HoverSubtitle: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let isToast = !model.toastMessage.isEmpty
        HStack(spacing: 6) {
            if isToast {
                Image(systemName: model.toastMessage.contains("已") ? "checkmark.circle.fill" : "info.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(model.toastMessage.contains("已") ? Coss.success : Coss.mutedForeground)
            } else if model.phase == .failure {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Coss.warning)
            }
            Text(model.subtitleText)
                .font(.system(size: 12, weight: isToast ? .medium : .regular))
                .foregroundStyle(!isToast && model.phase == .failure ? Coss.mutedForeground : Coss.foreground)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Coss.popover)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Coss.border, lineWidth: 1)
        )
    }
}

struct TryView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeading(
                eyebrow: "PLAYGROUND",
                title: "输入任意语言试试。",
                subtitle: "自动识别原文语种，也可直接在下方框内拖选局部文字测试划词工具栏。"
            )
            CossCardFrame(contentPadding: 16) {
                HStack {
                    Text("原文输入").font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Text("\(model.manualText.count) / 8,000")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(model.manualText.count > 8000 ? Coss.destructiveForeground : Coss.mutedForeground)
                }
            } content: {
                SelectionEditor(text: $model.manualText, translate: { model.presentSelection($0) })
                    .padding(12).frame(height: 200)
                    .background(Coss.frame)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Coss.border, lineWidth: 1))
                HStack {
                    CossBadge(text: "\(model.provider.rawValue) · 译成\(TextLogic.displayName(model.targetLanguage))", tone: .neutral)
                    Spacer()
                    Button { model.manualTranslate() } label: {
                        HStack(spacing: 5) {
                            Text("打开翻译浮窗")
                            Image(systemName: "arrow.up.right").font(.system(size: 11))
                        }
                    }
                    .buttonStyle(CossButtonStyle(variant: .primary))
                    .disabled(TextLogic.clean(model.manualText).isEmpty)
                }
                .padding(.top, 14)
            }
            CossCard(padding: 16) {
                HStack(alignment: .top, spacing: 13) {
                    CossIconTile(symbol: "text.cursor", size: 34)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("跨应用使用划词与截图翻译").font(.system(size: 13, weight: .semibold))
                        Text("在任意浏览器、编辑器、PDF 中拖选或双击文字，旁边会自动弹出「翻译 / 复制 / 保存」工具栏；也可以随时按 ⌃⌥T 直接翻译选区，或按 ⌥S 框选截图翻译。")
                            .font(.system(size: 12)).foregroundStyle(Coss.mutedForeground).lineSpacing(4)
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(
                eyebrow: "SETTINGS",
                title: "按你的习惯来。",
                subtitle: "配置语言、翻译服务、权限与摘录保存路径。随时可以从菜单栏开启或暂停。"
            )
            CossCardFrame {
                Text("语言与翻译服务").font(.system(size: 12.5, weight: .semibold))
            } content: {
                row("sparkles", "翻译服务", "选用 AI 后，待翻译文字会发送至对应服务并使用账号额度；截图始终在本机识别。") {
                    HStack(spacing: 8) {
                        Picker("翻译服务", selection: $model.provider) {
                            ForEach(AIProvider.allCases.filter { model.availableProviders.contains($0) || model.provider == $0 }, id: \.self) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }.labelsHidden()
                        Button {
                            Task { await model.refreshProviders(interactive: true) }
                        } label: {
                            HStack(spacing: 5) {
                                if model.checkingProviders { ProgressView().controlSize(.mini) }
                                Text(model.checkingProviders ? "检测中…" : "检测登录")
                            }
                        }.buttonStyle(CossButtonStyle(variant: .outline)).disabled(model.checkingProviders)
                    }
                }
                if !model.providerCheckMessage.isEmpty {
                    Text(model.providerCheckMessage)
                        .font(.system(size: 11)).foregroundStyle(Coss.mutedForeground)
                        .padding(.top, 8).padding(.leading, 45)
                }
                divider
                row("person.wave.2", "母语", "悬停时跳过母语文字；划词或快捷键仍可翻译。") {
                    languagePicker("母语", $model.nativeLanguage)
                }
                divider
                toggleRow("character.book.closed", "纯汉字按日语翻译", "阅读日文时可开启，例如「受付」。开启后中文汉字也可能按日语处理。", $model.japaneseKanji)
                divider
                row("character.bubble", "译成", "原文语种自动识别；原文已是该语言时，自动改译成母语或英文。") {
                    languagePicker("译成", $model.targetLanguage)
                }
                divider
                row("arrow.down.circle", "离线语言包", model.provider == .apple
                    ? "把各语种译成\(TextLogic.displayName(model.targetLanguage))需下载对应离线语言包。"
                    : "当前使用 AI 翻译，以下语言包仅用于 Apple 离线翻译。") {
                    Button("系统设置下载") { model.openSystemTranslationSettings() }
                        .buttonStyle(CossButtonStyle(variant: .outline))
                }
                packPicker.padding(.top, 14).padding(.leading, 45)
                Text(model.preparationMessage.isEmpty ? "系统设置 → 通用 → 语言与地区 → 翻译语言，可查看下载进度。" : model.preparationMessage)
                    .font(.system(size: 10.5)).foregroundStyle(Coss.mutedForeground).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10).padding(.leading, 45)
            }

            CossCardFrame {
                HStack {
                    Text("系统权限").font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Button("重新检测") { model.recheckPermissions() }
                        .buttonStyle(CossButtonStyle(variant: .outline, compact: true))
                }
            } content: {
                row("hand.point.up.left", "辅助功能（全局取词与划词）", model.accessibility ? "当前运行版本已获得系统取词权限。" : "当前运行版本未就绪；请确认授权的是此处的“浮译”。") {
                    if model.accessibility { readyLabel } else { Button("打开权限设置") { model.requestAccessibility() }.buttonStyle(CossButtonStyle(variant: .outline)) }
                }
                divider
                row("viewfinder", "屏幕录制（局部 OCR 与截图翻译）", "识别图片、系统界面和框选截图，仅在本机处理。") {
                    if model.screenPermission { readyLabel } else { Button("前往授权") { model.requestScreen() }.buttonStyle(CossButtonStyle(variant: .outline)) }
                }
                if !model.accessibility || !model.screenPermission { permissionHelp }
            }

            CossCardFrame {
                Text("触发与快捷键").font(.system(size: 12.5, weight: .semibold))
            } content: {
                toggleRow("cursorarrow.rays", "悬停翻译", "停留后在原文下显示一行译文。", $model.hoverEnabled)
                divider
                toggleRow("text.cursor", "划词快捷工具栏", "选中文字后在旁显示「翻译 / 复制 / 保存」图标。", $model.selectionToolbarEnabled)
                divider
                toggleRow("text.viewfinder", "允许本机 OCR 补充识别", "需要屏幕录制权限；识别范围限于鼠标附近。", $model.ocrEnabled)
                divider
                row("keyboard", "全局快捷键", "在任意应用直接触发选区翻译或截图翻译。") {
                    HStack(spacing: 10) {
                        CossKbd(keys: "⌃⌥T", label: "译选区")
                        CossKbd(keys: "⌥S", label: "截图翻译")
                    }
                }
                divider
                row("timer", "悬停等待", "鼠标停留多久后显示译文。") {
                    slider($model.delay, 0.3...1.5, 0.1, "\(Int((model.delay * 1000).rounded())) ms")
                }
                divider
                row("xmark.circle", "移开后关闭", "适用于悬停译文；选区浮窗保留至点击外部或关闭。") {
                    slider($model.closeDelay, 0...1, 0.05, model.closeDelay == 0 ? "立即" : "\(Int((model.closeDelay * 1000).rounded())) ms")
                        .accessibilityLabel("移开后关闭等待时间")
                }
                divider
                row("text.word.spacing", "识别范围", "优先识别完整句子；OCR 会按行距与对齐合并同段内容。") {
                    Picker("识别范围", selection: $model.wordMode) {
                        Text("句子").tag(false)
                        Text("单词").tag(true)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 140)
                }
            }

            CossCardFrame {
                Text("摘录保存").font(.system(size: 12.5, weight: .semibold))
            } content: {
                row("bookmark", "本地 Markdown 文件", "点击「保存」时非破坏性追加到该文件；可指向 Obsidian 笔记库或任意文件夹。") {
                    HStack(spacing: 8) {
                        Button("选择位置…") { model.chooseSnippetsMarkdownLocation() }.buttonStyle(CossButtonStyle(variant: .outline))
                        Button("在访达中显示") { model.revealSnippetsMarkdownFile() }.buttonStyle(CossButtonStyle(variant: .outline))
                    }
                }
                HStack(spacing: 10) {
                    Text(model.snippetsMarkdownPath)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Coss.mutedForeground)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    if model.snippetsMarkdownPath != SnippetStore.defaultMarkdownURL.path {
                        Button("恢复默认") { model.resetSnippetsMarkdownPath() }
                            .buttonStyle(CossButtonStyle(variant: .ghost, compact: true))
                    }
                }
                .padding(.top, 10).padding(.leading, 45)
            }

            Text("不自动监视剪贴板，不记录浏览历史，截图仅在本机识别；仅主动点击「保存」的摘录会写入本地摘录本与 Markdown 文件。使用 Apple 离线语言包时全程离线；选用 AI 服务时仅将待翻译文字发送至所选服务。关闭窗口后仍可从菜单栏使用；退出可按 ⌘Q。")
                .font(.system(size: 11)).foregroundStyle(Coss.mutedForeground).lineSpacing(4)
        }
        .onAppear { model.refreshPermissions(); Task { await model.refreshLanguage() } }
    }

    private var divider: some View {
        Rectangle().fill(Coss.border).frame(height: 1).padding(.vertical, 14)
    }

    private var packLanguages: [String] {
        TextLogic.languages.map(\.id).filter { !TextLogic.sameLanguage($0, model.targetLanguage) }
    }

    private var packPicker: some View {
        let id = packLanguages.contains(model.selectedPack) ? model.selectedPack : (packLanguages.first ?? "en")
        let status = model.packStatus[id]
        let installed = packLanguages.filter { model.packStatus[$0] == .installed }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                languagePicker("语种", Binding(get: { id }, set: { model.selectedPack = $0 }), options: packLanguages)
                if status == .installed {
                    CossBadge(text: "已下载", symbol: "checkmark", tone: .success)
                } else if status == .unsupported {
                    CossBadge(text: "不支持", tone: .neutral)
                } else if status == nil {
                    ProgressView().controlSize(.small)
                } else {
                    Button(model.preparing && model.preparingSource == id ? "下载中…" : "下载") {
                        model.prepareLanguage(source: id, target: model.targetLanguage)
                    }.buttonStyle(CossButtonStyle(variant: .outline, compact: true)).disabled(model.preparing)
                }
                Button { Task { await model.refreshLanguage() } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11.5))
                }
                .buttonStyle(CossButtonStyle(variant: .ghost, compact: true))
                .help("重新检查语言包")
            }
            Text(["ja", "ko"].filter { packLanguages.contains($0) }.map { id in
                let state = model.packStatus[id]
                let label = state == nil ? "检查中" : state == .installed ? "已下载" : state == .unsupported ? "不支持" : "待下载"
                return TextLogic.displayName(id) + " · " + label
            }.joined(separator: "　")).font(.system(size: 11)).foregroundStyle(Coss.mutedForeground)
            Text(installed.isEmpty ? "还没有已下载的语种。" : "已下载：" + installed.map(TextLogic.displayName).joined(separator: "、"))
                .font(.system(size: 11)).foregroundStyle(Coss.mutedForeground)
        }
    }

    private var readyLabel: some View {
        CossBadge(text: "已就绪", symbol: "checkmark", tone: .success)
    }

    private var permissionHelp: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(model.accessibility ? "找不到浮译？" : "开关已开启，却仍未就绪？").font(.system(size: 12, weight: .semibold))
            if !model.accessibility {
                Text("旧版本或内部测试包的授权可能没有对当前版本生效。请移除旧条目，按下面的路径重新添加“浮译”，再返回这里点“重新检测”。")
                    .font(.system(size: 11)).foregroundStyle(Coss.mutedForeground).lineSpacing(3)
            }
            Text("在系统权限页点“添加 / +”后，按 ⇧⌘G，粘贴下面的应用路径，按回车，再点“打开”。随后开启“浮译”；如果系统要求，退出并重新打开浮译。")
                .font(.system(size: 11)).foregroundStyle(Coss.mutedForeground).lineSpacing(3)
            Text(model.applicationPath).font(.system(size: 10.5, design: .monospaced)).textSelection(.enabled)
            HStack {
                Button("复制应用路径") { model.copyApplicationPath() }.buttonStyle(CossButtonStyle(variant: .outline, compact: true))
                Button("在访达中显示浮译") { model.revealApplication() }.buttonStyle(CossButtonStyle(variant: .outline, compact: true))
            }
            if model.applicationPath.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path + "/Applications") {
                Text("浮译位于个人“应用程序”目录，系统添加窗口默认可能打开另一个“应用程序”目录。")
                    .font(.system(size: 10.5)).foregroundStyle(Coss.mutedForeground)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Coss.frame)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Coss.border, lineWidth: 1))
        .padding(.top, 14)
    }

    private func row<Control: View>(_ icon: String, _ title: String, _ subtitle: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 13) {
            CossIconTile(symbol: icon)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Coss.mutedForeground).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            control()
        }
    }

    private func toggleRow(_ icon: String, _ title: String, _ subtitle: String, _ value: Binding<Bool>) -> some View {
        row(icon, title, subtitle) {
            Toggle(title, isOn: value).toggleStyle(.switch).labelsHidden().tint(Coss.primary).controlSize(.small)
        }
    }

    private func languagePicker(_ title: String, _ selection: Binding<String>, options: [String]? = nil) -> some View {
        DropdownMenu(title: title, selection: selection, options: options ?? TextLogic.languages.map(\.id))
    }

    private func slider(_ value: Binding<Double>, _ range: ClosedRange<Double>, _ step: Double, _ label: String) -> some View {
        HStack(spacing: 10) {
            Slider(value: value, in: range, step: step).tint(Coss.primary).frame(width: 168)
            Text(label).font(.system(size: 11, design: .monospaced)).foregroundStyle(Coss.mutedForeground).frame(width: 54, alignment: .trailing)
        }
    }
}

/// Coss UI Select trigger: crisp border, subtle shadow, opens cleanly below field.
struct DropdownMenu: View {
    let title: String
    @Binding var selection: String
    let options: [String]
    private func label(_ id: String) -> String {
        TextLogic.displayName(id) + "  " + (TextLogic.languages.first { $0.id == id }?.name ?? id)
    }
    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { Text(label($0)).tag($0) }
            }.pickerStyle(.inline).labelsHidden()
        } label: {
            HStack {
                Text(label(selection)).font(.system(size: 12)).lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Coss.mutedForeground)
            }
            .padding(.horizontal, 10).frame(width: 192, height: 30)
            .background(Coss.card)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Coss.inputBorder, lineWidth: 1))
            .shadow(color: Coss.subtleShadow, radius: 1.5, y: 1)
            .contentShape(Rectangle())
        }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().accessibilityLabel(title)
    }
}

/// Coss UI Popover + CardFrame floating translation card.
struct TranslationCard: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("译")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Coss.primaryForeground)
                    .frame(width: 18, height: 18)
                    .background(Coss.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                languageMenu(source: true)
                Text("→").font(.system(size: 10)).foregroundStyle(Coss.mutedForeground)
                languageMenu(source: false)
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    if model.canToggleRegionMerge {
                        tool(model.regionMergeLines ? "text.alignleft" : "list.bullet",
                             help: model.regionMergeLines ? "已合并段落换行（点击保留原换行）" : "已保留原换行（点击合并段落）",
                             active: model.regionMergeLines) {
                            model.toggleRegionMerge()
                        }
                    }
                    if model.method == "截图 OCR" && !model.recognizingRegion {
                        tool(model.copiedSource ? "checkmark" : "doc.on.clipboard",
                             help: model.copiedSource ? "已复制提取原文" : "复制提取的原文",
                             active: model.copiedSource) {
                            model.copySource()
                        }
                    }
                    tool(model.savedCurrent ? "bookmark.fill" : "bookmark",
                         help: model.savedCurrent ? "已保存到摘录本" : "保存到摘录本",
                         active: model.savedCurrent) { model.saveCurrentCard() }
                        .disabled(model.recognizingRegion || TextLogic.clean(model.source).isEmpty)
                    tool(model.pinned ? "pin.fill" : "pin", help: model.pinned ? "取消固定" : "固定浮窗",
                         active: model.pinned) { model.pinned.toggle() }
                    tool(model.copied ? "checkmark" : "doc.on.doc", help: model.copied ? "已复制" : "复制译文",
                         active: model.copied) { model.copyResult() }.disabled(model.phase != .result)
                    tool("xmark", help: "关闭浮窗") { model.dismiss(force: true) }
                }
            }
            .padding(.leading, 14).padding(.trailing, 8).frame(height: CardLayout.headerHeight)

            Group {
                if model.method == "截图 OCR" {
                    ScrollView {
                        Text(model.source).font(.system(size: CardLayout.sourceFontSize)).lineSpacing(2)
                            .foregroundStyle(Coss.mutedForeground).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }.scrollIndicators(.automatic)
                } else {
                    Text(model.source).font(.system(size: CardLayout.sourceFontSize)).lineSpacing(2)
                        .lineLimit(CardLayout.sourceLineLimit).truncationMode(.tail)
                        .foregroundStyle(Coss.mutedForeground).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .frame(height: model.cardSourceHeight, alignment: .topLeading)
            .padding(.horizontal, 16).help(model.source)

            Rectangle().fill(Coss.border).frame(height: 1)
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 9)

            Group {
                if model.phase == .loading || model.phase == .idle {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.mini)
                        Text(model.recognizingRegion ? "正在识别截图文字…" : "正在翻译…")
                            .font(.system(size: 12)).foregroundStyle(Coss.mutedForeground)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.result)
                                .font(.system(size: CardLayout.translationFontSize, weight: model.phase == .failure ? .regular : .medium))
                                .foregroundStyle(model.phase == .failure ? Coss.mutedForeground : Coss.foreground)
                                .lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if model.phase == .failure {
                                if model.missingPack != nil {
                                    Button("下载语言包") { model.downloadMissingPack() }
                                        .buttonStyle(CossButtonStyle(variant: .outline, compact: true))
                                } else {
                                    Button("打开设置") { model.dismiss(force: true); model.settings() }
                                        .buttonStyle(CossButtonStyle(variant: .outline, compact: true))
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.scrollIndicators(.automatic)
                }
            }
            .frame(height: model.cardBodyHeight, alignment: .topLeading)
            .padding(.horizontal, 16).padding(.bottom, 14)

            if model.showsReplacementControls {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle().fill(Coss.border).frame(height: 1)
                    HStack(spacing: 8) {
                        Text("替换后可按 ⌘Z 撤销")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Coss.mutedForeground)
                        Spacer(minLength: 4)
                        Button { model.replaceSelection() } label: {
                            HStack(spacing: 4) {
                                if model.isReplacing { ProgressView().controlSize(.mini) }
                                Text(model.isReplacing ? "正在替换…" : "替换选中文字")
                            }
                        }
                        .buttonStyle(CossButtonStyle(variant: .primary, compact: true))
                        .disabled(!model.canReplaceSelection)
                        .opacity(model.canReplaceSelection || model.isReplacing ? 1 : 0.45)
                        .accessibilityLabel("替换选中文字")
                    }
                    .padding(.horizontal, 14).frame(height: 37)
                    if !model.replacementMessage.isEmpty {
                        Text(model.replacementMessage)
                            .font(.system(size: 10.5)).lineLimit(2)
                            .foregroundStyle(Coss.warningForeground)
                            .frame(maxWidth: .infinity, alignment: .leading).frame(height: 30, alignment: .top)
                            .padding(.horizontal, 14)
                    }
                }
                .background(Coss.frame)
            }
        }
        .frame(width: model.cardWidth, height: model.cardHeight, alignment: .top)
        .background(Coss.popover)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Coss.border, lineWidth: 1))
        .foregroundStyle(Coss.foreground)
        .onExitCommand { model.dismiss(force: true) }
    }

    private func languageMenu(source: Bool) -> some View {
        let current = source ? model.sourceLanguage : model.target
        return Menu {
            ForEach(TextLogic.languages, id: \.id) { language in
                Button {
                    if source {
                        model.sourceLanguage = language.id
                        let target = TextLogic.sameLanguage(language.id, model.target)
                            ? TextLogic.target(for: language.id, preferred: model.targetLanguage, native: model.nativeLanguage)
                            : model.target
                        model.translate(to: target)
                    } else {
                        model.translate(to: language.id)
                    }
                } label: {
                    if current == language.id { Label(TextLogic.displayName(language.id), systemImage: "checkmark") }
                    else { Text(TextLogic.displayName(language.id)) }
                }
            }
        } label: {
            Text(TextLogic.displayName(current))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Coss.foreground)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton).fixedSize().disabled(model.isReplacing)
        .accessibilityLabel(source ? "原文语言" : "译文语言")
    }

    private func tool(_ symbol: String, help: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 22)
                .foregroundStyle(active ? Coss.foreground : Coss.mutedForeground)
                .background(active ? Coss.accent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
