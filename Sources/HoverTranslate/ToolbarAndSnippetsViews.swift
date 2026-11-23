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

/// Three refined minimalist circular orbs in coss.com/ui style that pop in
/// sequentially beside selected text: Translate, Copy, and Save.
struct SelectionToolbarView: View {
    @ObservedObject var model: AppModel
    @StateObject private var ui = ToolbarOrbState()

    var body: some View {
        HStack(spacing: 10) {
            orb(index: 0, id: "translate", title: "翻译") {
                Text("译")
                    .font(.system(size: 11.5, weight: .semibold))
            } action: {
                model.toolbarActionTranslate?()
            }
            orb(index: 1, id: "copy", title: "复制") {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10.5, weight: .medium))
            } action: {
                model.toolbarActionCopy?()
            }
            orb(index: 2, id: "save", title: "保存") {
                Image(systemName: "bookmark")
                    .font(.system(size: 10.5, weight: .medium))
            } action: {
                model.toolbarActionSave?()
            }
        }
        .padding(.bottom, 12)
        .frame(width: 136, height: 64, alignment: .bottom)
        .background(Color.clear)
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
        @ViewBuilder icon: () -> Icon,
        action: @escaping () -> Void
    ) -> some View {
        let shown = ui.revealed.indices.contains(index) ? ui.revealed[index] : false
        let isHovered = shown && ui.hovered == id

        return Button(action: action) {
            ZStack {
                Circle()
                    .fill(isHovered ? Coss.primary : Coss.popover)
                Circle()
                    .stroke(isHovered ? Coss.primary : Coss.inputBorder, lineWidth: 1)
                if !isHovered {
                    Circle()
                        .stroke(Coss.innerHighlight, lineWidth: 0.5)
                        .padding(0.75)
                }
                icon()
                    .foregroundStyle(isHovered ? Coss.primaryForeground : Coss.foreground)
            }
            .frame(width: 28, height: 28)
            .shadow(
                color: Color.black.opacity(isHovered ? 0.22 : 0.14),
                radius: isHovered ? 7 : 4.5,
                x: 0,
                y: isHovered ? 3 : 2
            )
            .contentShape(Circle())
            .overlay(alignment: .top) {
                if isHovered {
                    Text(title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Coss.primaryForeground)
                        .fixedSize()
                        .padding(.horizontal, 6.5)
                        .padding(.vertical, 2)
                        .background(Coss.primary)
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
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(
                eyebrow: "SNIPPETS",
                title: "摘录本",
                subtitle: "划词点击「保存」或在翻译浮窗点击书签即可收藏到这里，并自动非破坏性追加到本地 Markdown 文件。"
            )
            CossCardFrame(contentPadding: 14) {
                HStack {
                    Text("Markdown 同步文件").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    CossBadge(text: "自动追加", tone: .success)
                }
            } content: {
                HStack(spacing: 12) {
                    CossIconTile(symbol: "doc.text", size: 32)
                    Text(model.snippetsMarkdownPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Coss.mutedForeground)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    Button("打开文件") { model.openSnippetsMarkdownFile() }
                        .buttonStyle(CossButtonStyle(variant: .outline, compact: true))
                    Button("更改位置…") { model.chooseSnippetsMarkdownLocation() }
                        .buttonStyle(CossButtonStyle(variant: .outline, compact: true))
                }
            }

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(Coss.mutedForeground)
                    TextField("搜索原文、译文或来源应用…", text: $ui.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                    if !ui.query.isEmpty {
                        Button { ui.query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Coss.mutedForeground)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(Coss.card)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Coss.inputBorder, lineWidth: 1))
                .shadow(color: Coss.subtleShadow, radius: 1.5, y: 1)

                CossBadge(text: "\(filtered.count) 条", tone: .outline)
            }

            if filtered.isEmpty {
                CossCard(padding: 36) {
                    VStack(spacing: 10) {
                        CossIconTile(symbol: "bookmark", size: 40)
                        Text(model.snippets.isEmpty ? "还没有保存的摘录" : "没有找到匹配的摘录")
                            .font(.system(size: 14, weight: .semibold))
                        Text(model.snippets.isEmpty
                             ? "在任意应用拖选或双击文字，点击旁边工具栏里的「保存」，或在翻译浮窗点击书签即可记下。"
                             : "试试换一个关键词搜索。")
                            .font(.system(size: 12))
                            .foregroundStyle(Coss.mutedForeground)
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
        CossCardFrame(contentPadding: 16) {
            HStack(spacing: 8) {
                if let app = item.appName, !app.isEmpty {
                    CossBadge(text: app, tone: .outline)
                }
                Text(Self.dateFormatter.string(from: item.createdAt))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Coss.mutedForeground)
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
                    .buttonStyle(CossButtonStyle(variant: .outline, compact: true))
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
                        .foregroundStyle(ui.copiedID == item.id ? Coss.success : Coss.mutedForeground)
                        .frame(width: 24, height: 24)
                        .background(Coss.card)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Coss.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("复制内容")
                Button {
                    model.deleteSnippet(item.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(Coss.mutedForeground)
                        .frame(width: 24, height: 24)
                        .background(Coss.card)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Coss.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("从摘录本删除（不会修改已写入的 Markdown 文件）")
            }
        } content: {
            Text(item.text)
                .font(.system(size: 13.5))
                .foregroundStyle(Coss.foreground)
                .lineSpacing(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if let translation = item.translation, !translation.isEmpty {
                Rectangle().fill(Coss.border).frame(height: 1).padding(.vertical, 10)
                Text(translation)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Coss.mutedForeground)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
