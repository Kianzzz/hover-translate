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

struct SoftButton: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 13).padding(.vertical, 8)
            .foregroundStyle(prominent ? Color.white : Palette.ink)
            .background(prominent ? Palette.green : Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(prominent ? Color.clear : Palette.line, lineWidth: 1))
            .shadow(color: .black.opacity(prominent ? 0.12 : 0.03), radius: prominent ? 6 : 2, y: 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
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
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.035), radius: 10, y: 3)
    }
}

struct IconTile: View {
    let symbol: String
    var size: CGFloat = 32
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.45, weight: .medium)).foregroundStyle(Palette.green)
            .frame(width: size, height: size).background(Palette.mint)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
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
                        else if model.page == "try" { TryView(model: model) }
                        else { HomeView(model: model) }
                    }.padding(.horizontal, 40).padding(.top, 48).padding(.bottom, 32)
                        .frame(maxWidth: 860, alignment: .leading)
                }.scrollIndicators(.hidden)
                HStack(spacing: 8) {
                    Circle().fill(model.enabled ? Palette.green : Palette.secondary.opacity(0.6)).frame(width: 6, height: 6)
                    Text(model.status).font(.system(size: 11)).lineLimit(1)
                    Spacer()
                    Text("⌃⌥T 翻译选区").font(.system(size: 10, weight: .medium, design: .rounded))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Palette.sidebar).clipShape(Capsule())
                }.foregroundStyle(Palette.secondary).padding(.horizontal, 40).padding(.vertical, 12)
                    .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
            }.background(Palette.paper)
        }
        .frame(minWidth: 1040, minHeight: 740)
        .foregroundStyle(Palette.ink)
        .preferredColorScheme(.light)
        .translationTask(model.preparationConfig) { session in
            do {
                try await session.prepareTranslation()
                await model.refreshLanguage()
                model.preparationMessage = "语言包已下载，可以开始翻译。"
            } catch {
                model.preparationMessage = "准备失败：" + error.localizedDescription
                await model.refreshLanguage()
            }
            model.preparing = false
            model.preparingSource = nil
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Text("译").font(.system(size: 19, weight: .medium)).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(LinearGradient(colors: [Color(red: 0.26, green: 0.47, blue: 0.37), Palette.green],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .shadow(color: Palette.green.opacity(0.25), radius: 6, y: 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text("浮译").font(.system(size: 19, weight: .semibold))
                    Text("Hover Translate").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.secondary)
                }
            }.padding(.horizontal, 6).padding(.bottom, 34)
            nav("home", "开始使用", "sparkles")
            nav("try", "翻译试用", "text.bubble")
            nav("settings", "偏好设置", "slider.horizontal.3")
            Spacer()
            powerCard
            Text("v0.4.0 · 本地处理").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                .padding(.top, 14).padding(.horizontal, 6)
        }.padding(.horizontal, 14).padding(.top, 52).padding(.bottom, 20)
            .frame(width: 212).background(Palette.sidebar)
    }

    private var powerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("全局翻译").font(.system(size: 12, weight: .semibold))
                Spacer()
                Toggle("全局翻译", isOn: Binding(get: { model.enabled }, set: { _ in model.toggleEnabled() }))
                    .toggleStyle(.switch).labelsHidden().tint(Palette.green).controlSize(.mini)
            }
            Text(model.enabled ? "悬停外语、选中文字即可翻译" : "已暂停，不会读取屏幕文字")
                .font(.system(size: 10)).foregroundStyle(Palette.secondary).lineSpacing(2)
            HStack(spacing: 6) {
                Text("母语 " + TextLogic.displayName(model.nativeLanguage))
                Text("·")
                Text("译成 " + TextLogic.displayName(model.targetLanguage))
            }.font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.green)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface).clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Palette.line, lineWidth: 1))
    }

    private func nav(_ id: String, _ title: String, _ symbol: String) -> some View {
        let active = model.page == id
        return Button { model.page = id } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium)).frame(width: 18)
                    .foregroundStyle(active ? Palette.green : Palette.secondary)
                Text(title).font(.system(size: 13, weight: active ? .semibold : .regular))
                Spacer()
            }.padding(.horizontal, 10).padding(.vertical, 9)
                .background(active ? Palette.surface : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .shadow(color: .black.opacity(active ? 0.05 : 0), radius: 3, y: 1)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.bottom, 3)
    }
}

struct SectionHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.green)
            Text(title).font(.system(size: 30, weight: .bold)).tracking(-0.6)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(4)
        }
    }
}

struct HomeView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionHeading(eyebrow: "开始使用", title: "停一下，就读懂。",
                           subtitle: "悬停外语出现“译”图标，选中任意文字也能翻译。原文语种自动识别，默认译成\(TextLogic.displayName(model.targetLanguage))。")
            HStack(alignment: .top, spacing: 18) {
                browserPreview
                VStack(alignment: .leading, spacing: 20) {
                    step("1", "悬停外语", "停留片刻出现“译”图标；\(TextLogic.displayName(model.nativeLanguage))文字不打扰。")
                    step("2", "选中文字", "任何语言选中后都会出现图标。")
                    step("3", "移入图标", "自动展开原文与译文，无需点击。")
                    Spacer(minLength: 0)
                    Button { model.page = "try" } label: {
                        HStack(spacing: 6) { Text("试试自己的文字"); Image(systemName: "arrow.right") }
                    }.buttonStyle(SoftButton(prominent: true))
                }.padding(.vertical, 6).frame(width: 214, alignment: .leading)
            }
            HStack(spacing: 14) {
                feature("globe", "多语种原文", "自动识别英、日、韩、法、德等语言")
                feature("text.cursor", "选区翻译与替换", "输入框先看译文，再决定是否替换")
                feature("lock", "全部本机完成", "离线翻译，不上传文字与截图")
            }
            HStack(spacing: 14) {
                IconTile(symbol: ready ? "checkmark.seal.fill" : "exclamationmark.triangle", size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ready ? "取词、识图与语言包均已就绪" : "还差一步 · 完成权限与语言包准备").font(.system(size: 13, weight: .semibold))
                    Text("取词 \(model.accessibility ? "已授权" : "待授权")  ·  识图 \(model.screenPermission ? "已授权" : "待授权")  ·  语言包 \(model.languageReady ? "已就绪" : "待下载")")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button("检查设置") { model.page = "settings" }.buttonStyle(SoftButton())
            }.padding(16).background(Palette.sidebar.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
    private var ready: Bool { model.accessibility && model.languageReady && model.screenPermission && model.ocrEnabled }

    private var browserPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach([Color(red: 1.0, green: 0.37, blue: 0.34), Color(red: 1.0, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.79, blue: 0.25)], id: \.self) { color in
                    Circle().fill(color.opacity(0.85)).frame(width: 9, height: 9)
                }
                Spacer()
                Text("交互预览").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.secondary)
            }.padding(.horizontal, 16).padding(.vertical, 11)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
            VStack(alignment: .leading, spacing: 14) {
                Text("THE QUIET INTERNET").font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(Palette.secondary)
                Text("Read without breaking\nyour flow.").font(.system(size: 24, weight: .semibold, design: .serif)).lineSpacing(1)
                DemoSentence(model: model, english: "Good design makes complex things feel simple.")
                DemoSentence(model: model, english: "Stay curious. There is always more to discover.")
                HStack(spacing: 5) {
                    Image(systemName: "cursorarrow.rays").font(.system(size: 10))
                    Text("悬停上面的句子，再移到“译”图标").font(.system(size: 10, weight: .medium))
                }.foregroundStyle(Palette.green).padding(.top, 2)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.background(Palette.surface).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.line, lineWidth: 1))
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
    @Published var hovering = false
    var task: Task<Void, Never>?
}

struct DemoSentence: View {
    @ObservedObject var model: AppModel
    let english: String
    @StateObject private var interaction = DemoInteraction()
    var body: some View {
        Text(english).font(.system(size: 13)).lineSpacing(5)
            .frame(maxWidth: .infinity, alignment: .leading).padding(9)
            .background(interaction.hovering ? Palette.lime.opacity(0.55) : Palette.paper)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .background(HoverSampleSensor { inside, rect in
                interaction.hovering = inside; interaction.task?.cancel()
                if inside {
                    interaction.task = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64(model.delay * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        model.preview(english, bounds: rect)
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
        var polling: Timer?
        var inside = false
        var debugTicks = 0
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            polling?.invalidate()
            guard window != nil else { return }
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.sample() }
            }
            polling = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        func sample() {
            guard let window else { polling?.invalidate(); return }
            let rect = window.convertToScreen(convert(bounds, to: nil))
            if ProcessInfo.processInfo.environment["HOVER_TRANSLATE_DEBUG"] == "1" {
                debugTicks += 1
                if debugTicks % 10 == 0 { NSLog("HTSensor rect=%@ point=%@ active=%d key=%d hidden=%d", NSStringFromRect(rect), NSStringFromPoint(NSEvent.mouseLocation), NSApp.isActive, window.isKeyWindow, isHiddenOrHasHiddenAncestor) }
            }
            let nowInside = NSApp.isActive && window.isKeyWindow && !isHiddenOrHasHiddenAncestor && NSEvent.pressedMouseButtons == 0 && rect.contains(NSEvent.mouseLocation)
            if nowInside != inside { inside = nowInside; changed?(inside, rect) }
        }
        deinit { polling?.invalidate() }
    }
}

// Green “墨色小点” badges invert their surface against the system appearance.
private enum GreenBadgeLayout {
    static let visibleSize: CGFloat = 28
}

private enum GreenBadgePalette {
    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.16, green: 0.32, blue: 0.25) : Color(red: 0.92, green: 0.97, blue: 0.93)
    }
    static func surface(_ scheme: ColorScheme) -> [Color] {
        scheme == .dark
            ? [Color(red: 0.91, green: 0.96, blue: 0.92), Color(red: 0.79, green: 0.88, blue: 0.82)]
            : [Color(red: 0.24, green: 0.39, blue: 0.31), Color(red: 0.13, green: 0.26, blue: 0.20)]
    }
}

private struct GreenBadgeSurface: View {
    @Environment(\.colorScheme) private var scheme
    var circular = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: circular ? 50 : 9, style: .continuous)
        LinearGradient(colors: GreenBadgePalette.surface(scheme), startPoint: .topLeading, endPoint: .bottomTrailing)
            .clipShape(shape)
            .overlay(shape.stroke(Color.white.opacity(scheme == .dark ? 0.65 : 0.16), lineWidth: 0.6))
            .allowsHitTesting(false)
    }
}

struct HoverBadgeView: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text("译").font(.system(size: 13, weight: .light))
            .foregroundStyle(GreenBadgePalette.ink(scheme))
            .frame(width: GreenBadgeLayout.visibleSize, height: GreenBadgeLayout.visibleSize).background(GreenBadgeSurface(circular: true))
            .frame(width: 30, height: 30).contentShape(Rectangle())
            .accessibilityLabel("悬停翻译，鼠标移入展开译文")
    }
}

struct TryView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionHeading(eyebrow: "翻译试用", title: "输入任意语言试试。",
                           subtitle: "自动识别原文语种，浮窗只显示原文和译文，输入的内容保持不变。")
            Panel {
                HStack {
                    Text("原文").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(model.manualText.count) / 8,000").font(.system(size: 11, design: .rounded)).foregroundStyle(Palette.secondary)
                }.padding(.bottom, 12)
                TextEditor(text: $model.manualText).font(.system(size: 16)).lineSpacing(6)
                    .scrollContentBackground(.hidden).padding(14).frame(height: 200)
                    .background(Palette.paper).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.line, lineWidth: 1))
                    .accessibilityLabel("要翻译的原文")
                HStack {
                    Text("Apple 本机翻译 · 译成\(TextLogic.displayName(model.targetLanguage))").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    Spacer()
                    Button { model.manualTranslate() } label: { Label("打开翻译浮窗", systemImage: "arrow.up.right") }
                        .buttonStyle(SoftButton(prominent: true)).disabled(TextLogic.clean(model.manualText).isEmpty)
                }.padding(.top, 14)
            }
            HStack(alignment: .top, spacing: 14) {
                IconTile(symbol: "text.cursor", size: 34)
                VStack(alignment: .leading, spacing: 6) {
                    Text("在其他应用里试试选区翻译").font(.system(size: 13, weight: .semibold))
                    Text("开启全局翻译后，选中文字会出现“译”图标，鼠标移入即展开译文；可编辑输入框还可点击“替换选中文字”，再按 ⌘Z 撤销。也可以选中后按 ⌃⌥T 直接打开。")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(4)
                    Text("应用未开放选区时：复制文字 → 菜单栏“翻译剪贴板”。")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.sidebar.opacity(0.7)).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeading(eyebrow: "偏好设置", title: "按你的习惯来。", subtitle: "设置母语和译文语言，再授权全局取词。随时可以从菜单栏暂停。")
            Panel {
                cardTitle("语言")
                row("person.wave.2", "母语", "悬停时不为母语文字显示图标；选中母语文字仍可翻译。") {
                    languagePicker("母语", $model.nativeLanguage)
                }
                Divider().padding(.vertical, 14)
                row("character.bubble", "译成", "原文语种自动识别。原文已是该语言时，改译成母语或英文。") {
                    languagePicker("译成", $model.targetLanguage)
                }
                Divider().padding(.vertical, 14)
                row("arrow.down.circle", "语言包", "把各语种译成\(TextLogic.displayName(model.targetLanguage))需要先下载对应的离线语言包。") {
                    Button("在系统设置中下载") { model.openSystemTranslationSettings() }.buttonStyle(SoftButton())
                }
                packPicker.padding(.top, 14).padding(.leading, 45)
                Text(model.preparationMessage.isEmpty ? "系统设置 → 通用 → 语言与地区 → 翻译语言，可查看下载进度。" : model.preparationMessage)
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10).padding(.leading, 45)
            }
            Panel {
                HStack {
                    cardTitle("运行准备")
                    Spacer()
                    Button("重新检测") { model.recheckPermissions() }.buttonStyle(SoftButton()).padding(.bottom, 16)
                }
                row("hand.point.up.left", "设备控制与数据访问 / 辅助功能", model.accessibility ? "当前运行版本已获得系统取词权限。" : "当前运行版本未就绪；请确认授权的是此处的“浮译”。") {
                    if model.accessibility { readyLabel } else { Button("打开权限设置") { model.requestAccessibility() }.buttonStyle(SoftButton()) }
                }
                Divider().padding(.vertical, 14)
                row("viewfinder", "屏幕录制 · 扩展识别范围", "识别图片、系统界面和无法直接取词的文字，仅截取鼠标附近。") {
                    if model.screenPermission { readyLabel } else { Button("前往授权") { model.requestScreen() }.buttonStyle(SoftButton()) }
                }
                if !model.accessibility || !model.screenPermission { permissionHelp }
            }
            Panel {
                cardTitle("触发与识别")
                toggleRow("cursorarrow.rays", "悬停翻译", "悬停外语先出现“译”图标，移入图标后展开译文。", $model.hoverEnabled)
                Divider().padding(.vertical, 14)
                toggleRow("text.cursor", "选中文字后显示图标", "移入图标打开译文；可编辑输入框提供替换按钮。", $model.selectionEnabled)
                Divider().padding(.vertical, 14)
                toggleRow("text.viewfinder", "允许本机 OCR 补充识别", "需要屏幕录制权限；识别范围限于鼠标附近。", $model.ocrEnabled)
                Divider().padding(.vertical, 14)
                row("timer", "图标出现等待", "鼠标停留多久后出现“译”图标。") {
                    slider($model.delay, 0.3...1.5, 0.1, "\(Int(model.delay * 1000)) ms")
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
            Text("不自动读取剪贴板，不记录翻译历史，不上传截图或文字。关闭窗口后仍可从菜单栏使用；退出可按 ⌘Q。")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(4)
        }.onAppear { model.refreshPermissions(); Task { await model.refreshLanguage() } }
    }

    private var packLanguages: [String] {
        TextLogic.languages.map(\.id).filter { !TextLogic.sameLanguage($0, model.targetLanguage) }
    }

    /// One menu instead of a wall of chips: pick a language, see its status, act on it.
    private var packPicker: some View {
        let id = packLanguages.contains(model.selectedPack) ? model.selectedPack : (packLanguages.first ?? "en")
        let status = model.packStatus[id]
        let installed = packLanguages.filter { model.packStatus[$0] == .installed }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                languagePicker("语种", Binding(get: { id }, set: { model.selectedPack = $0 }), options: packLanguages)
                if status == .installed {
                    Label("已下载", systemImage: "checkmark.circle.fill").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.green)
                } else if status == .unsupported {
                    Text("本机翻译不支持").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                } else if status == nil {
                    ProgressView().controlSize(.small)
                } else {
                    Button(model.preparing && model.preparingSource == id ? "下载中…" : "下载") {
                        model.prepareLanguage(source: id, target: model.targetLanguage)
                    }.buttonStyle(SoftButton()).disabled(model.preparing)
                }
                Button { Task { await model.refreshLanguage() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(Palette.secondary).help("重新检查语言包")
            }
            Text(installed.isEmpty ? "还没有已下载的语种。" : "已下载：" + installed.map(TextLogic.displayName).joined(separator: "、"))
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
        }
    }

    private var readyLabel: some View {
        Label("已就绪", systemImage: "checkmark.circle.fill").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.green)
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
                Button("复制应用路径") { model.copyApplicationPath() }.buttonStyle(SoftButton())
                Button("在访达中显示浮译") { model.revealApplication() }.buttonStyle(SoftButton())
            }
            Text("浮译位于个人“应用程序”目录，系统添加窗口默认可能打开另一个“应用程序”目录。")
                .font(.system(size: 10)).foregroundStyle(Palette.secondary)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.paper).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous)).padding(.top, 14)
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

/// A pull-down that always opens below its field, unlike a pop-up picker
/// which covers the field with the selected row.
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
            }.padding(.horizontal, 11).frame(width: 190, height: 28)
                .background(Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Palette.line, lineWidth: 1))
                .contentShape(Rectangle())
        }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().accessibilityLabel(title)
    }
}

private enum MistCardPalette {
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
                    .frame(width: 17, height: 17).background(MistCardPalette.accent).clipShape(Circle())
                Text("\(TextLogic.displayName(model.sourceLanguage)) → \(TextLogic.displayName(model.target))")
                    .font(.system(size: 10.5, weight: .medium)).foregroundStyle(MistCardPalette.secondary).lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 1) {
                    tool(model.pinned ? "pin.fill" : "pin", help: model.pinned ? "取消固定" : "固定浮窗",
                         active: model.pinned) { model.pinned.toggle() }
                    tool(model.copied ? "checkmark" : "doc.on.doc", help: model.copied ? "已复制" : "复制译文",
                         active: model.copied) { model.copyResult() }.disabled(model.phase != .result)
                    tool("xmark", help: "关闭浮窗") { model.dismiss(force: true) }
                }
            }.padding(.leading, 14).padding(.trailing, 8).frame(height: CardLayout.headerHeight)
            Text(model.source).font(.system(size: CardLayout.sourceFontSize)).lineSpacing(2)
                .lineLimit(CardLayout.sourceLineLimit).truncationMode(.tail)
                .foregroundStyle(MistCardPalette.secondary).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading).frame(height: model.cardSourceHeight, alignment: .topLeading)
                .padding(.horizontal, 16).help(model.source)
            Rectangle().fill(MistCardPalette.secondary.opacity(0.14)).frame(height: 1)
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 9)
            Group {
                if model.phase == .loading || model.phase == .idle {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.mini)
                        Text("正在本机翻译…").font(.system(size: 12)).foregroundStyle(MistCardPalette.secondary)
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
            .background(Color.white.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.black.opacity(0.06), lineWidth: 0.5))
            .preferredColorScheme(.light).foregroundStyle(MistCardPalette.ink)
            .onExitCommand { model.dismiss(force: true) }
    }

    private func tool(_ symbol: String, help: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .regular)).frame(width: 22, height: 22)
                .foregroundStyle(active ? MistCardPalette.accent : MistCardPalette.secondary)
                .background(active ? MistCardPalette.selected : Color.clear).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
}

private struct CardButton: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(prominent ? Color.white : MistCardPalette.accent)
            .background(prominent ? MistCardPalette.accent : MistCardPalette.selected)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
