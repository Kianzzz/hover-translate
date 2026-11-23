import SwiftUI
import AppKit

@MainActor
private final class ToolbarOrbState: ObservableObject {
    @Published var hovered: String?
    @Published var revealed: [Bool] = [false, false, false]
    private var sequenceTask: Task<Void, Never>?

    func playPopIn() {
        sequenceTask?.cancel()
        hovered = nil
        revealed = [false, false, false]
        sequenceTask = Task { @MainActor [weak self] in
            let delays: [UInt64] = [15_000_000, 65_000_000, 65_000_000]
            for (index, delay) in delays.enumerated() {
                try? await Task.sleep(nanoseconds: delay)
                guard let self, !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.66)) {
                    self.revealed[index] = true
                }
            }
        }
    }

    func reset() {
        sequenceTask?.cancel()
        sequenceTask = nil
        hovered = nil
        revealed = [false, false, false]
    }
}

/// Three refined minimalist circular orbs in the frosted-glass + forest-green
/// capsule aesthetic that pop in sequentially beside selected text:
/// Translate, Copy, and Save.
struct SelectionToolbarView: View {
    @ObservedObject var model: AppModel
    @StateObject private var ui = ToolbarOrbState()

    var body: some View {
        HStack(spacing: 10) {
            orb(index: 0, id: "translate", title: "翻译", accentRest: true) {
                Text("译")
                    .font(.system(size: 11.5, weight: .semibold))
            } action: {
                model.toolbarActionTranslate?()
            }
            orb(index: 1, id: "copy", title: "复制", accentRest: false) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10.5, weight: .medium))
            } action: {
                model.toolbarActionCopy?()
            }
            orb(index: 2, id: "save", title: "保存", accentRest: false) {
                Image(systemName: "bookmark")
                    .font(.system(size: 10.5, weight: .medium))
            } action: {
                model.toolbarActionSave?()
            }
        }
        .padding(.bottom, 12)
        .frame(width: 136, height: 64, alignment: .bottom)
        .background(Color.clear)
        .preferredColorScheme(.light)
        .onAppear {
            if model.toolbarShown { ui.playPopIn() }
        }
        .onChange(of: model.toolbarAppearance) { _, _ in
            if model.toolbarShown { ui.playPopIn() }
        }
        .onChange(of: model.toolbarShown) { _, shown in
            if !shown { ui.reset() }
        }
    }

    private func orb<Icon: View>(
        index: Int,
        id: String,
        title: String,
        accentRest: Bool,
        @ViewBuilder icon: () -> Icon,
        action: @escaping () -> Void
    ) -> some View {
        let shown = ui.revealed.indices.contains(index) ? ui.revealed[index] : false
        let isHovered = shown && ui.hovered == id

        return Button(action: action) {
            ZStack {
                Circle()
                    .fill(.regularMaterial)
                Circle()
                    .fill(isHovered ? Palette.accent : Color.white.opacity(0.84))
                Circle()
                    .stroke(isHovered ? Palette.accent : Color.black.opacity(0.08), lineWidth: 0.75)
                icon()
                    .foregroundStyle(isHovered ? Color.white : Palette.ink)
            }
            .frame(width: 28, height: 28)
            .shadow(
                color: Color.black.opacity(isHovered ? 0.20 : 0.11),
                radius: isHovered ? 7 : 4.5,
                x: 0,
                y: isHovered ? 3 : 2
            )
            .contentShape(Circle())
            .overlay(alignment: .top) {
                if isHovered {
                    Text(title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white)
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Palette.accent)
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.16), radius: 4, y: 1.5)
                        .offset(y: -23)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .bottom)))
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(shown ? (isHovered ? 1.12 : 1.0) : 0.32)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? (isHovered ? -2 : 0) : 10)
        .allowsHitTesting(shown)
        .animation(.spring(response: 0.22, dampingFraction: 0.74), value: isHovered)
        .onHover { hovering in
            ui.hovered = hovering ? id : (ui.hovered == id ? nil : ui.hovered)
        }
        .accessibilityLabel(title)
    }
}

@MainActor
private final class SnippetsViewState: ObservableObject {
    @Published var query = ""
    @Published var copiedID: UUID?
}

struct SnippetsView: View {
    @ObservedObject var model: AppModel
    @StateObject private var ui = SnippetsViewState()

    private var filtered: [Snippet] {
        let q = ui.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return model.snippets }
        return model.snippets.filter { item in
            item.text.localizedCaseInsensitiveContains(q)
                || (item.translation?.localizedCaseInsensitiveContains(q) ?? false)
                || (item.appName?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeading(
                eyebrow: "摘录本",
                title: "收藏好句子。",
                subtitle: "划词点击「保存」圆球或在翻译浮窗点书签图标，内容会保存在这里，并自动非破坏性追加到你的本地 Markdown 文件。"
            )
            Panel(padding: 16) {
                HStack(spacing: 12) {
                    IconTile(symbol: "doc.text", size: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text("同步的 Markdown 文件").font(.system(size: 12.5, weight: .semibold))
                            CapsulePill(text: "自动追加", accent: true)
                        }
                        Text(model.snippetsMarkdownPath)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button("打开文件") { model.openSnippetsMarkdownFile() }
                        .buttonStyle(CapsuleButton(compact: true))
                    Button("更改位置…") { model.chooseSnippetsMarkdownLocation() }
                        .buttonStyle(CapsuleButton(compact: true))
                }
            }
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    TextField("搜索原文、译文或来源应用…", text: $ui.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                    if !ui.query.isEmpty {
                        Button { ui.query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Palette.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.025), radius: 3, y: 1)

                CapsulePill(text: "共 \(filtered.count) 条", accent: false)
            }
            if filtered.isEmpty {
                Panel(padding: 34) {
                    VStack(spacing: 10) {
                        IconTile(symbol: "bookmark", size: 42)
                        Text(model.snippets.isEmpty ? "还没有保存的摘录" : "没有找到匹配的摘录")
                            .font(.system(size: 14, weight: .semibold))
                        Text(model.snippets.isEmpty
                             ? "在任意应用选中文字，点击弹出的「保存」小圆球，或在翻译浮窗点击书签即可记下。"
                             : "试试换一个关键词搜索。")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filtered) { item in
                        snippetCard(item)
                    }
                }
            }
        }
    }

    private func snippetCard(_ item: Snippet) -> some View {
        Panel(padding: 18) {
            HStack(spacing: 8) {
                if let app = item.appName, !app.isEmpty {
                    CapsulePill(text: app, accent: true)
                }
                Text(Self.dateFormatter.string(from: item.createdAt))
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(Palette.secondary)
                Spacer()
                if item.translation == nil {
                    Button {
                        model.translateSnippetInPlace(item)
                    } label: {
                        HStack(spacing: 4) {
                            if model.translatingSnippetID == item.id { ProgressView().controlSize(.mini) }
                            Text(model.translatingSnippetID == item.id ? "翻译中…" : "补充译文")
                        }
                    }
                    .buttonStyle(CapsuleButton(compact: true))
                    .disabled(model.translatingSnippetID != nil)
                }
                Button {
                    let combined = item.translation.map { "\(item.text)\n\($0)" } ?? item.text
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(combined, forType: .string)
                    ui.copiedID = item.id
                    model.status = "已复制摘录"
                } label: {
                    Image(systemName: ui.copiedID == item.id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(ui.copiedID == item.id ? Palette.ink : Palette.secondary)
                        .frame(width: 26, height: 26)
                        .background(ui.copiedID == item.id ? Palette.softTint : Palette.paper)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("复制内容")
                Button {
                    model.deleteSnippet(item.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondary)
                        .frame(width: 26, height: 26)
                        .background(Palette.paper)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("从摘录本删除（不会修改已写入的 Markdown 文件）")
            }
            .padding(.bottom, 10)

            Text(item.text)
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.ink)
                .lineSpacing(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if let translation = item.translation, !translation.isEmpty {
                Rectangle().fill(Palette.line).frame(height: 1).padding(.vertical, 10)
                Text(translation)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
