import SwiftUI
import AppKit
import Translation

enum Palette {
    static let paper = Color(red: 0.969, green: 0.969, blue: 0.957)
    static let sidebar = Color(red: 0.937, green: 0.941, blue: 0.925)
    static let surface = Color.white
    static let ink = Color(red: 0.12, green: 0.16, blue: 0.14)
    static let secondary = Color(red: 0.45, green: 0.48, blue: 0.46)
    static let green = Color(red: 0.18, green: 0.37, blue: 0.29)
    static let lime = Color(red: 0.86, green: 0.93, blue: 0.86)
    static let mint = Color(red: 0.93, green: 0.96, blue: 0.93)
    static let line = Color(red: 0.89, green: 0.90, blue: 0.88)
}

/// Signature capsule button shared across the entire window & tool views.
struct CapsuleButton: ButtonStyle {
    var prominent = false
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11 : 12, weight: .medium))
            .padding(.horizontal, compact ? 12 : 15)
            .padding(.vertical, compact ? 6 : 8)
            .foregroundStyle(prominent ? Color.white : Palette.ink)
            .background(prominent ? Palette.green : Palette.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(prominent ? Color.clear : Palette.line, lineWidth: 1))
            .shadow(color: prominent ? Palette.green.opacity(0.20) : .black.opacity(0.035),
                    radius: prominent ? 6 : 2.5, y: 1.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

/// Compact capsule status / category pill.
struct CapsulePill: View {
    let text: String
    var symbol: String? = nil
    var accent = false
    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            }
            Text(text).font(.system(size: 10.5, weight: .medium, design: .rounded))
        }
        .foregroundStyle(accent ? Palette.green : Palette.secondary)
        .padding(.horizontal, 9).padding(.vertical, 3.5)
        .background(accent ? Palette.mint : Palette.sidebar)
        .clipShape(Capsule())
    }
}

/// White rounded panel shared by every content section.
struct Panel<Content: View>: View {
    var padding: CGFloat = 22
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.035), radius: 10, y: 3)
    }
}

struct IconTile: View {
    let symbol: String
    var size: CGFloat = 32
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .medium))
            .foregroundStyle(Palette.green)
            .frame(width: size, height: size)
            .background(Palette.mint)
            .clipShape(Circle())
    }
}

struct MainView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Palette.line).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    Group {
                        if model.page == "settings" { SettingsView(model: model) }
                        else if model.page == "snippets" { SnippetsView(model: model) }
                        else if model.page == "try" { TryView(model: model) }
                        else { HomeView(model: model) }
                    }.padding(.horizontal, 40).padding(.top, 48).padding(.bottom, 32)
                        .frame(maxWidth: 860, alignment: .leading)
                }.scrollIndicators(.hidden)
                HStack(spacing: 8) {
                    Circle().fill(model.enabled ? Palette.green : Palette.secondary.opacity(0.55)).frame(width: 6, height: 6)
                    Text(model.status).font(.system(size: 11)).lineLimit(1)
                    Spacer()
                    CapsulePill(text: "⌃⌥T 翻译选区", accent: false)
                    CapsulePill(text: "⌥S 截图翻译", accent: false)
                }.foregroundStyle(Palette.secondary).padding(.horizontal, 40).padding(.vertical, 12)
                    .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
            }.background(Palette.paper)
        }
        .frame(minWidth: 1040, minHeight: 740)
        .foregroundStyle(Palette.ink)
        .preferredColorScheme(.light)
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
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.6.3"
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Text("译").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(LinearGradient(colors: [Color(red: 0.26, green: 0.47, blue: 0.37), Palette.green],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(Circle())
                    .shadow(color: Palette.green.opacity(0.25), radius: 6, y: 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text("浮译").font(.system(size: 19, weight: .semibold))
                    Text("Hover Translate").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.secondary)
                }
            }.padding(.horizontal, 6).padding(.bottom, 34)
            nav("home", "开始使用", "sparkles")
            nav("snippets", "摘录本", "bookmark", badge: model.snippets.isEmpty ? nil : "\(model.snippets.count)")
            nav("try", "翻译试用", "text.bubble")
            nav("settings", "偏好设置", "slider.horizontal.3")
            Spacer()
            powerCard
            Text("v\(appVersion) · \(model.provider.rawValue)").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                .padding(.top, 14).padding(.horizontal, 6)
        }.padding(.horizontal, 14).padding(.top, 52).padding(.bottom, 20)
            .frame(width: 214).background(Palette.sidebar)
    }

    private var powerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("全局翻译").font(.system(size: 12, weight: .semibold))
                Spacer()
                Toggle("全局翻译", isOn: Binding(get: { model.enabled }, set: { _ in model.toggleEnabled() }))
                    .toggleStyle(.switch).labelsHidden().tint(Palette.green).controlSize(.mini)
            }
            Text(model.enabled ? "悬停外语、划词圆球已启用" : "已暂停，不会读取屏幕文字")
                .font(.system(size: 10)).foregroundStyle(Palette.secondary).lineSpacing(2)
            HStack(spacing: 5) {
                CapsulePill(text: TextLogic.displayName(model.nativeLanguage), accent: true)
                Text("→").font(.system(size: 9.5)).foregroundStyle(Palette.secondary)
                CapsulePill(text: TextLogic.displayName(model.targetLanguage), accent: true)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface).clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Palette.line, lineWidth: 1))
    }

    private func nav(_ id: String, _ title: String, _ symbol: String, badge: String? = nil) -> some View {
        let active = model.page == id
        return Button { model.page = id } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 12.5, weight: .medium)).frame(width: 18)
                    .foregroundStyle(active ? Palette.green : Palette.secondary)
                Text(title).font(.system(size: 13, weight: active ? .semibold : .regular))
                Spacer()
                if let badge {
                    Text(badge).font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(active ? Palette.green : Palette.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(active ? Palette.mint : Palette.paper)
                        .clipShape(Capsule())
                }
            }.padding(.horizontal, 12).padding(.vertical, 8.5)
                .background(active ? Palette.surface : Color.clear)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(active ? 0.055 : 0), radius: 4, y: 1.5)
                .contentShape(Capsule())
        }.buttonStyle(.plain).padding(.bottom, 4)
    }
}

struct SectionHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsulePill(text: eyebrow, accent: true)
            Text(title).font(.system(size: 30, weight: .bold)).tracking(-0.6)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(4)
        }
    }
}

struct HomeView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionHeading(
                eyebrow: "开始使用",
                title: "停一下，就读懂。",
                subtitle: "悬停查看一行胶囊译文，划词依次弹出三个快捷圆球，按 ⌥S 随时截图翻译。原文自动识别，默认译成\(TextLogic.displayName(model.targetLanguage))。"
            )
            HStack(alignment: .top, spacing: 18) {
                browserPreview
                VStack(alignment: .leading, spacing: 20) {
                    step("1", "悬停外语", "停留片刻显示一行胶囊译文；\(TextLogic.displayName(model.nativeLanguage))文字不打扰。")
                    step("2", "划词圆球", "拖选或双击依次弹出「译 / 复制 / 保存」小圆球，也可按 ⌃⌥T 直接翻译。")
                    step("3", "截图翻译 ⌥S", "全局按 ⌥S 框选任意区域，自动合段提取文字并翻译。")
                    Spacer(minLength: 0)
                    Button { model.startScreenshot?() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "viewfinder")
                            Text("截图翻译  ⌥S")
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(CapsuleButton(prominent: true))
                    Button { model.page = "try" } label: {
                        HStack(spacing: 6) {
                            Text("试试自己的文字")
                            Image(systemName: "arrow.right")
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(CapsuleButton())
                }.padding(.vertical, 6).frame(width: 214, alignment: .leading)
            }
            HStack(spacing: 14) {
                feature("globe", "多语种原文", "自动识别英、日、韩、法、德等语言")
                feature("bookmark", "一键摘录保存", "存入内置摘录本并同步至本地 Markdown")
                feature("lock", "本地优先", "默认 Apple 离线翻译，可选本机 AI CLI")
            }
            HStack(spacing: 14) {
                IconTile(symbol: ready ? "checkmark.seal.fill" : "exclamationmark.triangle", size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ready ? "取词、识图与翻译均已就绪" : "还差一步 · 检查权限与翻译服务").font(.system(size: 13, weight: .semibold))
                    Text("取词 \(model.accessibility ? "已授权" : "待授权")  ·  识图 \(!model.ocrEnabled ? "已关闭" : (model.screenPermission ? "已授权" : "待授权"))  ·  \(model.provider.rawValue)")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button("检查设置") { model.page = "settings" }.buttonStyle(CapsuleButton())
            }.padding(16).background(Palette.sidebar.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var ready: Bool {
        model.accessibility
            && (model.provider == .apple ? model.languageReady : model.availableProviders.contains(model.provider))
            && (!model.ocrEnabled || model.screenPermission)
    }

    private var browserPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach([Color(red: 1.0, green: 0.37, blue: 0.34), Color(red: 1.0, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.79, blue: 0.25)], id: \.self) { color in
                    Circle().fill(color.opacity(0.85)).frame(width: 9, height: 9)
                }
                Spacer()
                CapsulePill(text: "交互预览", accent: false)
            }.padding(.horizontal, 16).padding(.vertical, 10)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
            VStack(alignment: .leading, spacing: 14) {
                Text("THE QUIET INTERNET").font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(Palette.secondary)
                    .modifier(PreviewHover(model: model, text: "THE QUIET INTERNET"))
                Text("Read without breaking\nyour flow.").font(.system(size: 24, weight: .semibold, design: .serif)).lineSpacing(1)
                    .modifier(PreviewHover(model: model, text: "Read without breaking your flow."))
                DemoSentence(model: model, english: "Good design makes complex things feel simple.")
                DemoSentence(model: model, english: "Stay curious. There is always more to discover.")
                HStack(spacing: 5) {
                    Image(systemName: "cursorarrow.rays").font(.system(size: 10))
                    Text("悬停在句子上体验胶囊译文，或拖选文字体验快捷圆球").font(.system(size: 10.5, weight: .medium))
                }.foregroundStyle(Palette.green).padding(.top, 2)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.background(Palette.surface).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
    }

    private func step(_ n: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text(n).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Palette.green)
                .frame(width: 22, height: 22).background(Palette.mint).clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text).font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        Panel(padding: 16) {
            IconTile(symbol: symbol, size: 30).padding(.bottom, 12)
            Text(title).font(.system(size: 13, weight: .semibold)).padding(.bottom, 4)
            Text(text).font(.system(size: 11)).foregroundStyle(Palette.secondary)
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
        Text(english).font(.system(size: 13)).lineSpacing(5)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 9)
            .background(Palette.paper)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

/// Zero-idle-CPU hover sensor for in-app preview sentences: listens to local
/// mouseMoved events only while attached to a visible window, so it works
/// reliably inside ScrollView and alongside `.textSelection(.enabled)`.
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
        nonisolated(unsafe) private var monitor: Any?
        private var inside = false

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private var screenRect: CGRect {
            guard let window else { return .zero }
            return window.convertToScreen(convert(bounds, to: nil))
        }

        private func checkPointer() {
            guard let window, window.isVisible else {
                if inside { inside = false; changed?(false, .zero) }
                return
            }
            if NSEvent.pressedMouseButtons != 0 {
                if inside { inside = false; changed?(false, screenRect) }
                return
            }
            let local = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            let nowInside = bounds.contains(local) && !visibleRect.isEmpty && visibleRect.contains(local)
            if nowInside != inside {
                inside = nowInside
                changed?(nowInside, screenRect)
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            if window != nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseUp, .scrollWheel]) { [weak self] event in
                    self?.checkPointer()
                    return event
                }
            } else if inside {
                inside = false
                changed?(false, .zero)
            }
        }
    }
}

/// Signature frosted-glass capsule pill for hover translations and quick toast feedback.
struct HoverSubtitle: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let isToast = !model.toastMessage.isEmpty
        HStack(spacing: 5) {
            if isToast {
                Image(systemName: model.toastMessage.contains("已") ? "checkmark.circle.fill" : "info.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(model.toastMessage.contains("已") ? Palette.green : Color.secondary)
            } else if model.phase == .failure {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            }
            Text(model.subtitleText)
                .font(.system(size: 12, weight: isToast ? .medium : .regular))
                .foregroundStyle(!isToast && model.phase == .failure ? Color.secondary : Color.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}

struct TryView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionHeading(
                eyebrow: "翻译试用",
                title: "输入任意语言试试。",
                subtitle: "自动识别原文语种，也可直接在下方框内拖选局部文字体验划词圆球。"
            )
            Panel {
                HStack {
                    Text("原文").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    CapsulePill(text: "\(model.manualText.count) / 8,000", accent: false)
                        .foregroundStyle(model.manualText.count > 8000 ? Color.red : Palette.secondary)
                }.padding(.bottom, 12)
                SelectionEditor(text: $model.manualText, translate: { model.presentSelection($0) })
                    .padding(14).frame(height: 200)
                    .background(Palette.paper).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.line, lineWidth: 1))
                HStack {
                    CapsulePill(text: "\(model.provider.rawValue) · 译成\(TextLogic.displayName(model.targetLanguage))", accent: true)
                    Spacer()
                    Button { model.manualTranslate() } label: {
                        HStack(spacing: 5) {
                            Text("打开翻译浮窗")
                            Image(systemName: "arrow.up.right").font(.system(size: 11))
                        }
                    }
                    .buttonStyle(CapsuleButton(prominent: true))
                    .disabled(TextLogic.clean(model.manualText).isEmpty)
                }.padding(.top, 14)
            }
            HStack(alignment: .top, spacing: 14) {
                IconTile(symbol: "text.cursor", size: 34)
                VStack(alignment: .leading, spacing: 6) {
                    Text("在其他应用里使用划词圆球与截图翻译").font(.system(size: 13, weight: .semibold))
                    Text("拖选或双击任意文字后，旁边会依次弹出「译 / 复制 / 保存」三个小圆球；也可以直接按 ⌃⌥T 翻译选区，或按 ⌥S 框选截图翻译。")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(4)
                    Text("支持浏览器、Electron 编辑器、PDF 与终端，无需右键寻找菜单。")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.sidebar.opacity(0.75)).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeading(
                eyebrow: "偏好设置",
                title: "按你的习惯来。",
                subtitle: "设置母语、译文语言、权限与摘录保存路径。随时可以从菜单栏暂停。"
            )
            Panel {
                cardTitle("语言与服务")
                row("sparkles", "翻译服务", "选用 AI 后，待翻译的文字会发送至对应服务并使用账号额度。截图在本机识别。") {
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
                        }.buttonStyle(CapsuleButton(compact: true)).disabled(model.checkingProviders)
                    }
                }
                if !model.providerCheckMessage.isEmpty {
                    Text(model.providerCheckMessage)
                        .font(.system(size: 10.5)).foregroundStyle(Palette.secondary)
                        .padding(.top, 8).padding(.leading, 45)
                }
                Divider().padding(.vertical, 14)
                row("person.wave.2", "母语", "悬停时跳过母语文字；划词或快捷键仍可翻译。") {
                    languagePicker("母语", $model.nativeLanguage)
                }
                Divider().padding(.vertical, 14)
                toggleRow("character.book.closed", "纯汉字按日语翻译", "阅读日文时可开启，例如「受付」。开启后，中文汉字也可能按日语处理。", $model.japaneseKanji)
                Divider().padding(.vertical, 14)
                row("character.bubble", "译成", "原文语种自动识别。原文已是该语言时，改译成母语或英文。") {
                    languagePicker("译成", $model.targetLanguage)
                }
                Divider().padding(.vertical, 14)
                row("arrow.down.circle", "语言包", model.provider == .apple
                    ? "把各语种译成\(TextLogic.displayName(model.targetLanguage))需要先下载对应的离线语言包。"
                    : "当前使用 AI 翻译，以下语言包仅用于 Apple 离线翻译。") {
                    Button("在系统设置中下载") { model.openSystemTranslationSettings() }.buttonStyle(CapsuleButton(compact: true))
                }
                packPicker.padding(.top, 14).padding(.leading, 45)
                Text(model.preparationMessage.isEmpty ? "系统设置 → 通用 → 语言与地区 → 翻译语言，可查看下载进度。" : model.preparationMessage)
                    .font(.system(size: 10.5)).foregroundStyle(Palette.secondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10).padding(.leading, 45)
            }
            Panel {
                HStack {
                    cardTitle("运行准备")
                    Spacer()
                    Button("重新检测") { model.recheckPermissions() }.buttonStyle(CapsuleButton(compact: true)).padding(.bottom, 16)
                }
                row("hand.point.up.left", "设备控制与数据访问 / 辅助功能", model.accessibility ? "当前运行版本已获得系统取词权限。" : "当前运行版本未就绪；请确认授权的是此处的“浮译”。") {
                    if model.accessibility { readyLabel } else { Button("打开权限设置") { model.requestAccessibility() }.buttonStyle(CapsuleButton(compact: true)) }
                }
                Divider().padding(.vertical, 14)
                row("viewfinder", "屏幕录制 · 扩展识别范围", "识别图片、系统界面和框选截图，仅在本机处理。") {
                    if model.screenPermission { readyLabel } else { Button("前往授权") { model.requestScreen() }.buttonStyle(CapsuleButton(compact: true)) }
                }
                if !model.accessibility || !model.screenPermission { permissionHelp }
            }
            Panel {
                cardTitle("触发与快捷键")
                toggleRow("cursorarrow.rays", "悬停翻译", "停留后在原文下显示一行胶囊译文。", $model.hoverEnabled)
                Divider().padding(.vertical, 14)
                toggleRow("text.cursor", "划词快捷圆球", "选中文字后依次弹出「译 / 复制 / 保存」三个小圆球。", $model.selectionToolbarEnabled)
                Divider().padding(.vertical, 14)
                toggleRow("text.viewfinder", "允许本机 OCR 补充识别", "需要屏幕录制权限；识别范围限于鼠标附近。", $model.ocrEnabled)
                Divider().padding(.vertical, 14)
                row("keyboard", "全局快捷键", "无论当前在哪个应用，都可直接触发选区翻译或截图翻译。") {
                    HStack(spacing: 8) {
                        CapsulePill(text: "⌃⌥T 译选区", accent: true)
                        CapsulePill(text: "⌥S 截图翻译", accent: true)
                    }
                }
                Divider().padding(.vertical, 14)
                row("timer", "悬停等待", "鼠标停留多久后显示译文。") {
                    slider($model.delay, 0.3...1.5, 0.1, "\(Int((model.delay * 1000).rounded())) ms")
                }
                Divider().padding(.vertical, 14)
                row("xmark.circle", "移开后关闭", "适用于悬停译文；选区浮窗保留至点击外部或关闭。") {
                    slider($model.closeDelay, 0...1, 0.05, model.closeDelay == 0 ? "立即" : "\(Int((model.closeDelay * 1000).rounded())) ms")
                        .accessibilityLabel("移开后关闭等待时间")
                }
                Divider().padding(.vertical, 14)
                row("text.word.spacing", "识别范围", "优先识别完整句子；OCR 会按行距与对齐合并同段内容。") {
                    Picker("识别范围", selection: $model.wordMode) {
                        Text("句子").tag(false)
                        Text("单词").tag(true)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 140)
                }
            }
            Panel {
                cardTitle("摘录保存")
                row("bookmark", "本地 Markdown 文件", "点击「保存」时同步追加到该文件；可指向 Obsidian 笔记库或任意文件夹。") {
                    HStack(spacing: 8) {
                        Button("选择位置…") { model.chooseSnippetsMarkdownLocation() }.buttonStyle(CapsuleButton(compact: true))
                        Button("在访达中显示") { model.revealSnippetsMarkdownFile() }.buttonStyle(CapsuleButton(compact: true))
                    }
                }
                HStack(spacing: 10) {
                    Text(model.snippetsMarkdownPath)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    if model.snippetsMarkdownPath != SnippetStore.defaultMarkdownURL.path {
                        Button("恢复默认") { model.resetSnippetsMarkdownPath() }
                            .buttonStyle(CapsuleButton(compact: true))
                    }
                }
                .padding(.top, 10).padding(.leading, 45)
            }
            Text("不自动监视剪贴板，不记录浏览历史，截图仅在本机识别；仅主动点击「保存」的摘录会写入本地摘录本与 Markdown 文件。使用 Apple 离线语言包时全程离线；选用 AI 服务时仅将待翻译文字发送至所选服务。关闭窗口后仍可从菜单栏使用；退出可按 ⌘Q。")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(4)
        }.onAppear { model.refreshPermissions(); Task { await model.refreshLanguage() } }
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
                    CapsulePill(text: "已下载", symbol: "checkmark", accent: true)
                } else if status == .unsupported {
                    CapsulePill(text: "不支持", accent: false)
                } else if status == nil {
                    ProgressView().controlSize(.small)
                } else {
                    Button(model.preparing && model.preparingSource == id ? "下载中…" : "下载") {
                        model.prepareLanguage(source: id, target: model.targetLanguage)
                    }.buttonStyle(CapsuleButton(compact: true)).disabled(model.preparing)
                }
                Button { Task { await model.refreshLanguage() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondary)
                        .frame(width: 26, height: 26)
                        .background(Palette.paper)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("重新检查语言包")
            }
            Text(["ja", "ko"].filter { packLanguages.contains($0) }.map { id in
                let state = model.packStatus[id]
                let label = state == nil ? "检查中" : state == .installed ? "已下载" : state == .unsupported ? "不支持" : "待下载"
                return TextLogic.displayName(id) + " · " + label
            }.joined(separator: "　")).font(.system(size: 11)).foregroundStyle(Palette.secondary)
            Text(installed.isEmpty ? "还没有已下载的语种。" : "已下载：" + installed.map(TextLogic.displayName).joined(separator: "、"))
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
        }
    }

    private var readyLabel: some View {
        CapsulePill(text: "已就绪", symbol: "checkmark", accent: true)
    }

    private var permissionHelp: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(model.accessibility ? "找不到浮译？" : "开关已开启，却仍未就绪？").font(.system(size: 12, weight: .semibold))
            if !model.accessibility {
                Text("旧版本或内部测试包的授权可能没有对当前版本生效。请移除旧条目，按下面的路径重新添加“浮译”，再返回这里点“重新检测”。")
                    .font(.system(size: 11)).lineSpacing(3)
            }
            Text("在系统权限页点“添加 / +”后，按 ⇧⌘G，粘贴下面的应用路径，按回车，再点“打开”。随后开启“浮译”；如果系统要求，退出并重新打开浮译。")
                .font(.system(size: 11)).lineSpacing(3)
            Text(model.applicationPath).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
            HStack {
                Button("复制应用路径") { model.copyApplicationPath() }.buttonStyle(CapsuleButton(compact: true))
                Button("在访达中显示浮译") { model.revealApplication() }.buttonStyle(CapsuleButton(compact: true))
            }
            if model.applicationPath.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path + "/Applications") {
                Text("浮译位于个人“应用程序”目录，系统添加窗口默认可能打开另一个“应用程序”目录。")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.paper).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)).padding(.top, 14)
    }

    private func cardTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 14, weight: .semibold)).padding(.bottom, 16)
    }

    private func row<Control: View>(_ icon: String, _ title: String, _ subtitle: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 13) {
            IconTile(symbol: icon)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            control()
        }
    }

    private func toggleRow(_ icon: String, _ title: String, _ subtitle: String, _ value: Binding<Bool>) -> some View {
        row(icon, title, subtitle) {
            Toggle(title, isOn: value).toggleStyle(.switch).labelsHidden().tint(Palette.green).controlSize(.small)
        }
    }

    private func languagePicker(_ title: String, _ selection: Binding<String>, options: [String]? = nil) -> some View {
        DropdownMenu(title: title, selection: selection, options: options ?? TextLogic.languages.map(\.id))
    }

    private func slider(_ value: Binding<Double>, _ range: ClosedRange<Double>, _ step: Double, _ label: String) -> some View {
        HStack(spacing: 10) {
            Slider(value: value, in: range, step: step).tint(Palette.green).frame(width: 170)
            Text(label).font(.system(size: 11, design: .rounded)).foregroundStyle(Palette.secondary).frame(width: 52, alignment: .trailing)
        }
    }
}

/// Capsule-shaped pull-down menu that always opens cleanly below its field.
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
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.secondary)
            }.padding(.horizontal, 13).frame(width: 192, height: 30)
                .background(Palette.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
                .contentShape(Capsule())
        }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().accessibilityLabel(title)
    }
}

enum MistCardPalette {
    static let ink = Color(red: 0.13, green: 0.16, blue: 0.14)
    static let secondary = Color(red: 0.47, green: 0.51, blue: 0.48)
    static let accent = Color(red: 0.20, green: 0.40, blue: 0.31)
    static let selected = Color(red: 0.90, green: 0.95, blue: 0.91)
}

struct TranslationCard: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("译").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 18, height: 18).background(MistCardPalette.accent).clipShape(Circle())
                languageMenu(source: true)
                Text("→").font(.system(size: 10)).foregroundStyle(MistCardPalette.secondary)
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
            }.padding(.leading, 14).padding(.trailing, 8).frame(height: CardLayout.headerHeight)
            Group {
                if model.method == "截图 OCR" {
                    ScrollView {
                        Text(model.source).font(.system(size: CardLayout.sourceFontSize)).lineSpacing(2)
                            .foregroundStyle(MistCardPalette.secondary).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }.scrollIndicators(.automatic)
                } else {
                    Text(model.source).font(.system(size: CardLayout.sourceFontSize)).lineSpacing(2)
                        .lineLimit(CardLayout.sourceLineLimit).truncationMode(.tail)
                        .foregroundStyle(MistCardPalette.secondary).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .frame(height: model.cardSourceHeight, alignment: .topLeading)
            .padding(.horizontal, 16).help(model.source)
            Rectangle().fill(MistCardPalette.secondary.opacity(0.14)).frame(height: 1)
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 9)
            Group {
                if model.phase == .loading || model.phase == .idle {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.mini)
                        Text(model.recognizingRegion ? "正在识别截图文字…" : "正在翻译…")
                            .font(.system(size: 12)).foregroundStyle(MistCardPalette.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.result).font(.system(size: CardLayout.translationFontSize, weight: model.phase == .failure ? .regular : .medium))
                                .foregroundStyle(model.phase == .failure ? MistCardPalette.secondary : MistCardPalette.ink)
                                .lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if model.phase == .failure {
                                if model.missingPack != nil {
                                    Button("下载语言包") { model.downloadMissingPack() }.buttonStyle(CardButton())
                                } else {
                                    Button("打开设置") { model.dismiss(force: true); model.settings() }.buttonStyle(CardButton())
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.scrollIndicators(.automatic)
                }
            }.frame(height: model.cardBodyHeight, alignment: .topLeading).padding(.horizontal, 16).padding(.bottom, 14)
            if model.showsReplacementControls {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle().fill(MistCardPalette.secondary.opacity(0.14)).frame(height: 1)
                    HStack(spacing: 8) {
                        Text("替换后可按 ⌘Z 撤销").font(.system(size: 10)).foregroundStyle(MistCardPalette.secondary)
                        Spacer(minLength: 4)
                        Button { model.replaceSelection() } label: {
                            HStack(spacing: 4) {
                                if model.isReplacing { ProgressView().controlSize(.mini) }
                                Text(model.isReplacing ? "正在替换…" : "替换选中文字")
                            }
                        }.buttonStyle(CardButton(prominent: true)).disabled(!model.canReplaceSelection)
                            .opacity(model.canReplaceSelection || model.isReplacing ? 1 : 0.45)
                            .accessibilityLabel("替换选中文字")
                    }.padding(.horizontal, 14).frame(height: 37)
                    if !model.replacementMessage.isEmpty {
                        Text(model.replacementMessage).font(.system(size: 10)).lineLimit(2)
                            .foregroundStyle(MistCardPalette.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).frame(height: 30, alignment: .top)
                            .padding(.horizontal, 14)
                    }
                }.background(MistCardPalette.selected.opacity(0.35))
            }
        }.frame(width: model.cardWidth, height: model.cardHeight, alignment: .top)
            .background(Color.white.opacity(0.90))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.black.opacity(0.07), lineWidth: 0.5))
            .preferredColorScheme(.light).foregroundStyle(MistCardPalette.ink)
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
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(MistCardPalette.ink)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(MistCardPalette.selected.opacity(0.65))
                .clipShape(Capsule())
                .lineLimit(1)
        }.menuStyle(.borderlessButton).fixedSize().disabled(model.isReplacing)
            .accessibilityLabel(source ? "原文语言" : "译文语言")
    }

    private func tool(_ symbol: String, help: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium)).frame(width: 22, height: 22)
                .foregroundStyle(active ? MistCardPalette.accent : MistCardPalette.secondary)
                .background(active ? MistCardPalette.selected : .clear)
                .clipShape(Circle())
                .contentShape(Circle())
        }.buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
}

struct CardButton: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 5)
            .foregroundStyle(prominent ? Color.white : MistCardPalette.accent)
            .background(prominent ? MistCardPalette.accent : Color.white.opacity(0.9))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(prominent ? Color.clear : MistCardPalette.accent.opacity(0.24), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
