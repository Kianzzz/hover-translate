import AppKit

@main
struct SelectionMenuChecks {
    @MainActor static func main() {
        let app = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 180),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let editor = SelectionTextView(frame: window.contentView!.bounds)
        window.contentView!.addSubview(editor)
        window.makeFirstResponder(editor)
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 20, y: 16),
                                       modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        for text in ["Good design", "日本語", "한국어"] {
            editor.string = "🌱 " + text + " sample"
            editor.setSelectedRange((editor.string as NSString).range(of: text))
            let menu = editor.menu(for: event)!
            menu.update()
            guard let item = menu.items.first, item.title == "浮译", item.submenu == nil,
                  item.isEnabled, menu.items.filter({ $0.title == "浮译" }).count == 1 else {
                fatalError("Expected one enabled top-level 浮译 command")
            }
            var received: String?
            editor.translate = { received = $0 }
            guard app.sendAction(item.action!, to: item.target, from: item), received == text else {
                fatalError("Menu action did not deliver the selected substring")
            }
            print("Passed first-level menu and action:", text)
        }
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        precondition(editor.menu(for: event)?.items.contains(where: { $0.title == "浮译" }) != true)
    }
}
