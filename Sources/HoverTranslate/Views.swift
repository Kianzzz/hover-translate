import SwiftUI
import AppKit
import Translation

enum Palette {
    static let paper = Color(red: 0.978, green: 0.981, blue: 0.969)
    static let sidebar = Color(red: 0.939, green: 0.950, blue: 0.927)
    static let ink = Color(red: 0.15, green: 0.21, blue: 0.18)
    static let secondary = Color(red: 0.46, green: 0.50, blue: 0.46)
    static let green = Color(red: 0.20, green: 0.35, blue: 0.28)
    static let lime = Color(red: 0.82, green: 0.93, blue: 0.65)
    static let line = Color(red: 0.88, green: 0.90, blue: 0.86)
}

struct SoftButton: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(prominent ? Color.white : Palette.ink)
            .background(prominent ? Palette.green : Color.white.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(prominent ? Color.clear : Palette.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct MainView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 0) {
                topbar
                ScrollView {
                    Group {
                        if model.page == "settings" { SettingsView(model: model) }
                        else if model.page == "try" { TryView(model: model) }
                        else { HomeView(model: model) }
                    }.padding(32)
                }.scrollIndicators(.hidden)
                HStack(spacing: 7) {
                    Circle().fill(model.enabled ? Palette.green : Palette.secondary).frame(width: 5, height: 5)
                    Text(model.status).font(.system(size: 11)).lineLimit(1)
                    Spacer()
                    Text("⌃ ⌥ T  翻译选区").font(.system(size: 10, design: .monospaced))
                }.foregroundStyle(Palette.secondary).padding(.horizontal, 32).padding(.vertical, 12)
            }.background(Palette.paper)
        }
        .frame(minWidth: 1040, minHeight: 740)
        .foregroundStyle(Palette.ink)
        .preferredColorScheme(.light)
        .translationTask(model.preparationConfig) { session in
            do {
                try await session.prepareTranslation()
                await model.refreshLanguage()
                model.preparationMessage = model.languageReady ? "语言包已就绪，可以开始翻译。" : "语言包仍未就绪，请重试。"
            } catch {
                model.preparationMessage = "准备失败：" + error.localizedDescription
                await model.refreshLanguage()
            }
            model.preparing = false
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13).fill(Palette.green).frame(width: 42, height: 42)
                    Image(systemName: "character.bubble.fill").font(.system(size: 21)).foregroundStyle(Palette.lime)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("浮译").font(.system(size: 23, weight: .semibold))
                    Text("HOVER TRANSLATE").font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1.1).foregroundStyle(Palette.secondary)
                }
            }.padding(.bottom, 46)
            nav("home", "开始使用", "square.grid.2x2")
            nav("try", "翻译试用", "text.bubble")
            nav("settings", "偏好设置", "slider.horizontal.3")
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "leaf").font(.system(size: 22)).foregroundStyle(Palette.green)
                Text("少一点打断，\n多一点理解。").font(.system(size: 15, weight: .medium)).lineSpacing(5)
                Text("识别与翻译均在本机进行").font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: 16))
            Text("v0.3.2  /  本地原型").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.secondary).padding(.top, 20)
        }.padding(.horizontal, 20).padding(.top, 54).padding(.bottom, 22)
            .frame(width: 204).background(Palette.sidebar)
    }

    private func nav(_ id: String, _ title: String, _ symbol: String) -> some View {
        Button { model.page = id } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol).font(.system(size: 14)).frame(width: 20)
                Text(title).font(.system(size: 13, weight: model.page == id ? .semibold : .regular))
                Spacer()
                if model.page == id { Circle().fill(Palette.green).frame(width: 5, height: 5) }
            }.padding(.horizontal, 12).padding(.vertical, 13)
                .background(model.page == id ? Color.white : Color.clear).clipShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).padding(.bottom, 6)
    }

    private var topbar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield").font(.system(size: 11))
                Text("本机处理 · 切换由你触发").font(.system(size: 11))
            }.foregroundStyle(Palette.secondary)
            Spacer()
            Button { model.toggleEnabled() } label: {
                HStack(spacing: 9) {
                    Circle().fill(model.enabled ? Palette.green : Palette.secondary).frame(width: 6, height: 6)
                    Text(model.enabled ? "全局翻译已开启" : "开启全局翻译").font(.system(size: 12, weight: .medium))
                    Image(systemName: "power").font(.system(size: 12))
                }.padding(.horizontal, 14).padding(.vertical, 9)
                    .background(model.enabled ? Palette.lime : Color.white)
                    .clipShape(Capsule()).overlay(Capsule().stroke(Palette.line, lineWidth: 1))
            }.buttonStyle(.plain)
        }.padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 17)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
}

struct SectionHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(Palette.green)
            Text(title).font(.system(size: 34, weight: .semibold)).tracking(-1)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(4)
        }
    }
}

struct HomeView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeading(eyebrow: "A LITTLE PAUSE. A LITTLE CLARITY.", title: "停一下，就读懂。", subtitle: "鼠标悬停看中文，选中文字自由切换语言。")
            HStack(alignment: .top, spacing: 18) {
                browserPreview
                VStack(alignment: .leading, spacing: 22) {
                    Label("轻一点的阅读方式", systemImage: "cursorarrow.rays").font(.system(size: 13, weight: .semibold))
                    step("01", "发现", "鼠标在英文上停留，出现小“译”图标。")
                    step("02", "移入", "鼠标移到图标，自动展开译文，无需点击。")
                    step("03", "继续", "移开后收起；移入浮窗可继续阅读。")
                    Spacer(minLength: 0)
                    Button { model.page = "try" } label: {
                        HStack { Text("试试自己的文字"); Image(systemName: "arrow.up.right") }
                    }.buttonStyle(SoftButton(prominent: true))
                }.padding(.vertical, 18).frame(width: 204, alignment: .leading)
            }
            HStack(spacing: 14) {
                feature("cursorarrow", "移入图标看译文", "无需选中，也无需点击")
                feature("text.cursor", "选区双向翻译", "输入框先看译文，再决定是否替换")
                feature("pin", "固定与复制", "长内容慢慢读，译文随手用")
            }
            HStack(spacing: 12) {
                Image(systemName: ready ? "checkmark.seal.fill" : "sparkle").foregroundStyle(Palette.green).font(.system(size: 22))
                VStack(alignment: .leading, spacing: 4) {
                    Text(ready ? "取词与识图均已就绪" : "覆盖范围受限 · 请完成权限准备").font(.system(size: 13, weight: .medium))
                    Text("辅助功能：\(model.accessibility ? "已授权" : "待授权")   ·   语言包：\(model.languageReady ? "已就绪" : "待准备")   ·   识图：\(model.screenPermission ? "已授权" : "系统选项 / 图片需要授权")")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button("检查设置") { model.page = "settings" }.buttonStyle(SoftButton())
            }.padding(18).background(Palette.sidebar).clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
    private var ready: Bool { model.accessibility && model.languageReady && model.screenPermission && model.ocrEnabled }

    private var browserPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                ForEach([Color(red: 0.91, green: 0.62, blue: 0.56), Color(red: 0.92, green: 0.79, blue: 0.49), Color(red: 0.63, green: 0.77, blue: 0.57)], id: \.self) { color in
                    Circle().fill(color).frame(width: 7, height: 7)
                }
                Spacer()
                Text("交互预览").font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }.padding(.horizontal, 18).padding(.vertical, 13).background(Palette.sidebar.opacity(0.6))
            VStack(alignment: .leading, spacing: 17) {
                Text("THE QUIET INTERNET").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.8).foregroundStyle(Palette.secondary)
                Text("Read without breaking\nyour flow.").font(.system(size: 25, weight: .medium, design: .serif)).lineSpacing(2)
                DemoSentence(model: model, english: "Good design makes complex things feel simple.")
                DemoSentence(model: model, english: "Stay curious. There is always more to discover.")
                HStack(spacing: 5) {
                    Image(systemName: "cursorarrow").font(.system(size: 10))
                    Text("悬停英文后，移到“译”图标查看译文").font(.system(size: 10))
                }.foregroundStyle(Palette.green).padding(.top, 3)
                Text("这里使用本机真实翻译，无需开启全局权限即可试用。")
                    .font(.system(size: 9)).foregroundStyle(Palette.secondary)
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        }.background(Color.white).clipShape(RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(Palette.line, lineWidth: 1))
    }

    private func step(_ n: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text(n).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Palette.green).padding(.top, 3)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(text).font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(Palette.green)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(text).font(.system(size: 10)).foregroundStyle(Palette.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.line, lineWidth: 1))
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
        VStack(alignment: .leading, spacing: 24) {
            SectionHeading(eyebrow: "TRY YOUR OWN WORDS", title: "把语言切换一下。", subtitle: "输入或粘贴一段中英文。浮窗显示译文，输入的原文保持不变。")
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("原文", systemImage: "text.alignleft").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(model.manualText.count) / 8,000").font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.secondary)
                }
                TextEditor(text: $model.manualText).font(.system(size: 17)).lineSpacing(6)
                    .scrollContentBackground(.hidden).padding(14).frame(height: 210)
                    .background(Palette.paper).clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
                    .accessibilityLabel("要翻译的原文")
                HStack {
                    Text("Apple 本机翻译 · \(model.languageStatus)").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    Spacer()
                    Button { model.manualTranslate() } label: { Label("打开翻译浮窗", systemImage: "arrow.up.right") }
                        .buttonStyle(SoftButton(prominent: true)).disabled(TextLogic.clean(model.manualText).isEmpty)
                }
            }.padding(22).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 17))
                .overlay(RoundedRectangle(cornerRadius: 17).stroke(Palette.line, lineWidth: 1))
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "text.cursor").font(.system(size: 23)).foregroundStyle(Palette.green)
                VStack(alignment: .leading, spacing: 7) {
                    Text("在其他应用里试试选区翻译").font(.system(size: 14, weight: .semibold))
                    Text("开启全局翻译后，选中文字会打开译文浮窗。选择中文或英文查看结果；可编辑输入框还可点击“替换选中文字”，再在原输入框按 ⌘Z 撤销。也可以选中后按 ⌃ ⌥ T。")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(5)
                    Text("应用未开放选区时：复制文字 → 菜单栏“翻译剪贴板”。")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Palette.sidebar).clipShape(RoundedRectangle(cornerRadius: 15))
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionHeading(eyebrow: "MAKE IT FEEL RIGHT", title: "按你的节奏来。", subtitle: "先准备语言包，再授权全局取词。随时可以从菜单栏暂停。")
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("运行准备").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button("重新检测") { model.recheckPermissions() }.buttonStyle(SoftButton())
                }.padding(.bottom, 16)
                permission("accessibility", "设备控制与数据访问 / 辅助功能", model.accessibility ? "当前运行版本已获得系统取词权限。" : "当前运行版本未就绪；请确认授权的是此处的“浮译”。", model.accessibility, "打开权限设置") { model.requestAccessibility() }
                Divider().padding(.vertical, 14)
                permission("viewfinder", "屏幕录制 · 扩展识别范围", "识别图片、系统界面和无法直接取词的文字，仅截取鼠标附近。", model.screenPermission, "前往授权") { model.requestScreen() }
                if !model.accessibility || !model.screenPermission {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.accessibility ? "找不到浮译？" : "开关已开启，却仍未就绪？").font(.system(size: 12, weight: .semibold))
                        if !model.accessibility {
                            Text("旧版本或内部测试包的授权可能没有对当前版本生效。请移除旧条目，按下面的路径重新添加“浮译”，再返回这里点“重新检测”。")
                                .font(.system(size: 11)).lineSpacing(4)
                        }
                        Text("在系统权限页点“添加 / +”后，按 ⇧⌘G，粘贴下面的应用路径，按回车，再点“打开”。随后开启“浮译”；如果系统要求，退出并重新打开浮译。")
                            .font(.system(size: 11)).lineSpacing(4)
                        Text(model.applicationPath).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                        HStack {
                            Button("复制应用路径") { model.copyApplicationPath() }.buttonStyle(SoftButton())
                            Button("在访达中显示浮译") { model.revealApplication() }.buttonStyle(SoftButton())
                        }
                        Text("浮译位于个人“应用程序”目录，系统添加窗口默认可能打开另一个“应用程序”目录。")
                            .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.paper).clipShape(RoundedRectangle(cornerRadius: 10)).padding(.top, 12)
                }
                Divider().padding(.vertical, 14)
                permission("character.bubble", "中英文语言包", model.languageStatus, model.languageReady, model.preparing ? "准备中…" : "准备语言包") { model.prepareLanguage() }
                if !model.preparationMessage.isEmpty {
                    Text(model.preparationMessage).font(.system(size: 11)).foregroundStyle(Palette.secondary).padding(.top, 12)
                }
            }.padding(22).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line, lineWidth: 1))
            VStack(alignment: .leading, spacing: 17) {
                Text("触发与识别").font(.system(size: 14, weight: .semibold))
                settingToggle("悬停翻译", "先出现“译”图标，鼠标移入图标后展开译文，无需点击。", $model.hoverEnabled)
                settingToggle("选中文字后显示翻译工具", "统一显示译文浮窗；可编辑输入框提供替换按钮。", $model.selectionEnabled)
                settingToggle("允许本机 OCR 补充识别", "需要屏幕录制权限；识别范围限于鼠标附近。", $model.ocrEnabled)
                Divider()
                HStack {
                    Text("图标出现等待").font(.system(size: 12))
                    Slider(value: $model.delay, in: 0.3...1.5, step: 0.1).tint(Palette.green).frame(maxWidth: 250)
                    Text("\(Int(model.delay * 1000)) ms").font(.system(size: 11, design: .monospaced)).frame(width: 65)
                    Spacer()
                }
                HStack {
                    Text("移开后关闭").font(.system(size: 12))
                    Slider(value: $model.closeDelay, in: 0...1, step: 0.05).tint(Palette.green).frame(maxWidth: 250)
                        .accessibilityLabel("移开后关闭等待时间")
                    Text(model.closeDelay == 0 ? "立即关闭" : "\(Int((model.closeDelay * 1000).rounded())) ms")
                        .font(.system(size: 11, design: .monospaced)).frame(width: 65)
                    Spacer()
                    Button("立即关闭") { model.closeDelay = 0 }.buttonStyle(SoftButton())
                }
                Text("此设置适用于悬停译文。选区工具保留至点击外部或关闭；固定浮窗不受此设置影响。")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                HStack {
                    Text("识别范围").font(.system(size: 12))
                    Picker("识别范围", selection: $model.wordMode) {
                        Text("句子 / 短语").tag(false)
                        Text("单词").tag(true)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 235)
                    Spacer()
                }
                Text("优先识别完整句子；OCR 会按行距与对齐合并同段内容，屏幕外文字无法识别。")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }.padding(22).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line, lineWidth: 1))
            Text("不自动读取剪贴板，不记录翻译历史，不上传截图或文字。关闭窗口后仍可从菜单栏使用；退出可按 ⌘ Q。")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(4)
        }.onAppear { model.refreshPermissions() }
    }

    private func permission(_ icon: String, _ title: String, _ description: String, _ ready: Bool, _ actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon).font(.system(size: 19)).foregroundStyle(Palette.green).frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(description).font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 10)
            if ready { Label("已就绪", systemImage: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Palette.green) }
            else { Button(actionTitle, action: action).buttonStyle(SoftButton()).disabled(title == "中英文语言包" && model.preparing) }
        }
    }

    private func settingToggle(_ title: String, _ subtitle: String, _ value: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
            Spacer()
            Toggle(title, isOn: value).toggleStyle(.switch).labelsHidden().tint(Palette.green).controlSize(.small)
        }
    }
}

private enum MistCardPalette {
    static let ink = Color(red: 0.21, green: 0.25, blue: 0.22)
    static let secondary = Color(red: 0.56, green: 0.60, blue: 0.57)
    static let accent = Color(red: 0.38, green: 0.48, blue: 0.37)
    static let selected = Color(red: 0.92, green: 0.95, blue: 0.90)
}

struct TranslationCard: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text("译").font(.system(size: 12, weight: .medium)).foregroundStyle(MistCardPalette.accent)
                    .frame(width: 16).help("浮译")
                HStack(spacing: 2) {
                    tab("原文", "original")
                    tab("中文", "zh-Hans")
                    tab("EN", "en")
                }
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    tool(model.pinned ? "pin.fill" : "pin", help: model.pinned ? "取消固定" : "固定浮窗",
                         active: model.pinned) { model.pinned.toggle() }
                    tool(model.copied ? "checkmark" : "doc.on.doc", help: model.copied ? "已复制" : "复制译文",
                         active: model.copied) { model.copyResult() }.disabled(model.phase != .result)
                    tool("xmark", help: "关闭浮窗") { model.dismiss(force: true) }
                }
            }.padding(.leading, 10).padding(.trailing, 8).frame(height: CardLayout.headerHeight)
            VStack(alignment: .leading, spacing: 4) {
                if model.showsCardSource {
                    Text(model.source).font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
                        .foregroundStyle(MistCardPalette.secondary).frame(height: 16, alignment: .leading)
                        .help(model.source)
                }
                Group {
                    if model.phase == .choose {
                        Text("选择上方语言查看译文").font(.system(size: 12)).foregroundStyle(MistCardPalette.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if model.phase == .loading {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.mini)
                            Text("正在本机翻译…").font(.system(size: 12)).foregroundStyle(MistCardPalette.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(model.result).font(.system(size: CardLayout.translationFontSize, weight: .regular))
                                    .lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if model.phase == .failure {
                                    Button("打开设置") { model.dismiss(force: true); model.settings() }
                                        .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(MistCardPalette.accent)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.scrollIndicators(.automatic)
                    }
                }.frame(height: model.cardBodyHeight, alignment: .topLeading)
            }.padding(.horizontal, 12).padding(.top, 3).padding(.bottom, 11)
            if model.showsReplacementControls {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle().fill(MistCardPalette.secondary.opacity(0.15)).frame(height: 1)
                    HStack(spacing: 8) {
                        Text("⌘Z 撤销").font(.system(size: 9)).foregroundStyle(MistCardPalette.secondary)
                        Spacer(minLength: 4)
                        Button { model.replaceSelection() } label: {
                            HStack(spacing: 4) {
                                if model.isReplacing { ProgressView().controlSize(.mini) }
                                Text(model.isReplacing ? "正在替换…" : "替换选中文字")
                            }.font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(MistCardPalette.selected).clipShape(RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain).disabled(!model.canReplaceSelection)
                            .opacity(model.canReplaceSelection || model.isReplacing ? 1 : 0.45)
                            .accessibilityLabel("替换选中文字")
                    }.padding(.horizontal, 12).frame(height: 33)
                    if !model.replacementMessage.isEmpty {
                        Text(model.replacementMessage).font(.system(size: 10)).lineLimit(2)
                            .foregroundStyle(MistCardPalette.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).frame(height: 30, alignment: .top)
                            .padding(.horizontal, 12)
                    }
                }
            }
        }.frame(width: model.cardWidth, height: model.cardHeight, alignment: .top)
            .background(Color.white.opacity(0.86))
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.95), lineWidth: 1))
            .preferredColorScheme(.light).foregroundStyle(MistCardPalette.ink)
            .onExitCommand { model.dismiss(force: true) }
    }

    private func tab(_ name: String, _ language: String) -> some View {
        let active = model.phase != .choose && model.target == language
        return Button { model.translate(to: language) } label: {
            Text(name).font(.system(size: 9, weight: .medium)).padding(.horizontal, 7).padding(.vertical, 3)
                .foregroundStyle(active ? MistCardPalette.accent : MistCardPalette.secondary)
                .background(active ? MistCardPalette.selected : Color.clear).clipShape(RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain).disabled(model.isReplacing).help(language == "en" ? "译成英文" : (language == "zh-Hans" ? "译成中文" : "查看原文"))
    }

    private func tool(_ symbol: String, help: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .regular)).frame(width: 21, height: 21)
                .foregroundStyle(active ? MistCardPalette.accent : MistCardPalette.secondary)
                .background(active ? MistCardPalette.selected : Color.clear).clipShape(RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
}
