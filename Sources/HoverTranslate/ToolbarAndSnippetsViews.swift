import SwiftUI
import AppKit

@MainActor
private final class ToolbarHoverState: ObservableObject {
    @Published var hovered: String?
}

struct SelectionToolbarView: View {
    @ObservedObject var model: AppModel
    @StateObject private var ui = ToolbarHoverState()

    var body: some View {
        HStack(spacing: 2) {
            actionButton(id: "translate", symbol: "character.bubble", title: "翻译", accent: true) {
                model.toolbarActionTranslate?()
            }
            divider
            actionButton(id: "copy", symbol: "doc.on.doc", title: "复制", accent: false) {
                model.toolbarActionCopy?()
            }
            divider
            actionButton(id: "save", symbol: "bookmark", title: "保存", accent: false) {
                model.toolbarActionSave?()
            }
        }
        .padding(.horizontal, 5)
        .frame(width: 204, height: 34)
        .background(Color.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.black.opacity(0.08), lineWidth: 0.5))
        .preferredColorScheme(.light)
    }

    private var divider: some View {
        Rectangle()
            .fill(MistCardPalette.secondary.opacity(0.18))
            .frame(width: 1, height: 14)
    }

    private func actionButton(id: String, symbol: String, title: String, accent: Bool, action: @escaping () -> Void) -> some View {
        let isHovered = ui.hovered == id
        return Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 11.5, weight: accent ? .semibold : .medium))
            }
            .foregroundStyle(accent ? MistCardPalette.accent : MistCardPalette.ink)
            .frame(maxWidth: .infinity, maxHeight: 26)
            .background(isHovered ? MistCardPalette.selected : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in ui.hovered = hovering ? id : (ui.hovered == id ? nil : ui.hovered) }
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
                subtitle: "划词点击「保存」或在翻译浮窗点书签图标，内容会保存在这里，并自动追加到你的本地 Markdown 文件。"
            )
            Panel(padding: 16) {
                HStack(spacing: 12) {
                    IconTile(symbol: "doc.text", size: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("同步的 Markdown 文件").font(.system(size: 12.5, weight: .semibold))
                        Text(model.snippetsMarkdownPath)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button("打开文件") { model.openSnippetsMarkdownFile() }.buttonStyle(SoftButton())
                    Button("更改位置…") { model.chooseSnippetsMarkdownLocation() }.buttonStyle(SoftButton())
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
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Palette.line, lineWidth: 1))
                Text("共 \(filtered.count) 条")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Palette.secondary)
            }
            if filtered.isEmpty {
                Panel(padding: 32) {
                    VStack(spacing: 10) {
                        IconTile(symbol: "bookmark", size: 42)
                        Text(model.snippets.isEmpty ? "还没有保存的摘录" : "没有找到匹配的摘录")
                            .font(.system(size: 14, weight: .semibold))
                        Text(model.snippets.isEmpty
                             ? "在任意应用选中文字，点击旁边工具栏里的「保存」，或在翻译浮窗点击书签即可记下。"
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
                    Text(app)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Palette.green)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Palette.mint)
                        .clipShape(Capsule())
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
                    .buttonStyle(SoftButton())
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
                        .font(.system(size: 11.5))
                        .foregroundStyle(ui.copiedID == item.id ? Palette.green : Palette.secondary)
                        .frame(width: 26, height: 26)
                        .background(Palette.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("复制内容")
                Button {
                    model.deleteSnippet(item.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.secondary)
                        .frame(width: 26, height: 26)
                        .background(Palette.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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
                    .foregroundStyle(Palette.green)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
