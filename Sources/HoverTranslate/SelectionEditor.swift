import AppKit
import SwiftUI

struct SelectionEditor: NSViewRepresentable {
    @Binding var text: String
    let translate: (String) -> Void

    final class Coordinator: NSObject, NSTextViewDelegate {
        var binding: Binding<String>
        init(_ binding: Binding<String>) { self.binding = binding }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            binding.wrappedValue = editor.string
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator($text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        let editor = SelectionTextView(frame: scroll.contentView.bounds)
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 16)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.lineFragmentPadding = 0
        editor.setAccessibilityLabel("要翻译的原文")
        editor.delegate = context.coordinator
        editor.translate = translate
        editor.string = text
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? SelectionTextView else { return }
        context.coordinator.binding = $text
        editor.translate = translate
        if editor.string != text { editor.string = text }
    }
}

final class SelectionTextView: NSTextView {
    var translate: ((String) -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let selection = selectedRange()
        let standard = super.menu(for: event)
        guard selection.length > 0, selection.location != NSNotFound else { return standard }
        let text = (string as NSString).substring(with: selection)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return standard }

        let menu = standard?.copy() as? NSMenu ?? NSMenu()
        let item = NSMenuItem(title: "浮译", action: #selector(translateText(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = text
        if !menu.items.isEmpty { menu.insertItem(.separator(), at: 0) }
        menu.insertItem(item, at: 0)
        return menu
    }

    @objc private func translateText(_ sender: NSMenuItem) {
        if let text = sender.representedObject as? String { translate?(text) }
    }
}
