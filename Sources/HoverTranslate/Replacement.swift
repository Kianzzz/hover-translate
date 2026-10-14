import AppKit
import ApplicationServices

struct SelectedCapture: Sendable {
    let text: CapturedText
    let replacement: ReplacementTarget?
}

enum ReplacementError: LocalizedError {
    case changed, unavailable, clipboard
    var errorDescription: String? {
        switch self {
        case .changed: return "输入框或选区已变化，请重新选中文字后翻译。"
        case .unavailable: return "当前输入框不支持安全替换，请使用复制。"
        case .clipboard: return "无法准备替换文字，原文未改动。"
        }
    }
}

// Immutable remote-process proxy. Never capture our own UI for background AX reads.
struct ReplacementTarget: @unchecked Sendable {
    let element: AXUIElement
    let pid: pid_t
    let edit: SelectionEdit

    private static func editable(_ element: AXUIElement) -> Bool {
        let role = TextCapture.attribute(element, kAXRoleAttribute) as? String ?? ""
        guard ["AXTextField", "AXTextArea", "AXComboBox"].contains(role),
              !TextCapture.isProtected(element),
              TextCapture.attribute(element, kAXEnabledAttribute) as? Bool != false else { return false }
        var settable: DarwinBoolean = false
        return (AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue)
            || TextCapture.attribute(element, "AXEditable") as? Bool == true
    }

    private static func selectedRange(_ element: AXUIElement) -> NSRange? {
        guard let ref = TextCapture.attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(ref as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    static func capture(element: AXUIElement, pid: pid_t, selected: String) -> ReplacementTarget? {
        var owner: pid_t = 0
        guard (try? TextCapture.requireExternalElement(element)) != nil,
              AXUIElementGetPid(element, &owner) == .success, owner == pid,
              editable(element), let range = selectedRange(element),
              let value = TextCapture.attribute(element, kAXValueAttribute) as? String else { return nil }
        let edit = SelectionEdit(value: value, selected: selected, range: range)
        guard edit.replacing(with: selected) != nil else { return nil }
        return ReplacementTarget(element: element, pid: pid, edit: edit)
    }

    // After a paste, the selection normally collapses to the end. On the next
    // explicit icon click, reselect only our unchanged span before restoring it.
    func prepareSpan() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            TextCapture.queue.async {
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.3)
                let caret = NSRange(location: edit.range.location + edit.range.length, length: 0)
                guard (try? TextCapture.requireExternalElement(element)) != nil,
                      let focused = TextCapture.attribute(app, kAXFocusedUIElementAttribute),
                      CFGetTypeID(focused) == AXUIElementGetTypeID(), CFEqual(focused, element),
                      Self.editable(element), TextCapture.attribute(element, kAXValueAttribute) as? String == edit.value,
                      let currentRange = Self.selectedRange(element), currentRange == edit.range || currentRange == caret else {
                    continuation.resume(throwing: ReplacementError.changed); return
                }
                if currentRange != edit.range {
                    var range = CFRange(location: edit.range.location, length: edit.range.length)
                    guard let ref = AXValueCreate(.cfRange, &range),
                          AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, ref) == .success else {
                        continuation.resume(throwing: ReplacementError.unavailable); return
                    }
                }
                continuation.resume()
            }
        }
    }

    func afterReplacing(with text: String) -> ReplacementTarget? {
        guard let value = edit.replacing(with: text) else { return nil }
        return ReplacementTarget(element: element, pid: pid,
            edit: SelectionEdit(value: value, selected: text,
                                range: NSRange(location: edit.range.location, length: text.utf16.count)))
    }

    func validate() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            TextCapture.queue.async {
                do {
                    try TextCapture.requireExternalElement(element)
                    let app = AXUIElementCreateApplication(pid)
                    AXUIElementSetMessagingTimeout(app, 0.3)
                    guard let focused = TextCapture.attribute(app, kAXFocusedUIElementAttribute),
                          CFGetTypeID(focused) == AXUIElementGetTypeID(), CFEqual(focused, element),
                          Self.editable(element), Self.selectedRange(element) == edit.range,
                          TextCapture.attribute(element, kAXValueAttribute) as? String == edit.value,
                          TextCapture.attribute(element, kAXSelectedTextAttribute) as? String == edit.selected else {
                        throw ReplacementError.changed
                    }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func currentValue() async -> String? {
        await withCheckedContinuation { continuation in
            TextCapture.queue.async {
                continuation.resume(returning: TextCapture.attribute(element, kAXValueAttribute) as? String)
            }
        }
    }
}

@MainActor
private final class PasteboardLease {
    private let items: [NSPasteboardItem]
    private let changeCount: Int
    init(text: String) throws {
        let board = NSPasteboard.general
        items = (board.pasteboardItems ?? []).map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        board.clearContents()
        guard board.setString(text, forType: .string) else {
            if !items.isEmpty { board.writeObjects(items) }
            throw ReplacementError.clipboard
        }
        changeCount = board.changeCount
    }

    func restore() {
        let board = NSPasteboard.general
        // A copy performed by the user meanwhile always wins.
        guard board.changeCount == changeCount else { return }
        board.clearContents()
        if !items.isEmpty { board.writeObjects(items) }
    }
}

@MainActor
enum TextReplacement {
    static func perform(_ target: ReplacementTarget, text: String,
                        stillCurrent: () -> Bool, releasePanelFocus: () -> Void) async throws -> Bool {
        guard let expected = target.edit.replacing(with: text),
              let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw ReplacementError.unavailable
        }
        try await target.validate()
        try Task.checkCancellation()
        guard stillCurrent(), NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid else {
            throw ReplacementError.changed
        }
        let lease = try PasteboardLease(text: text)
        releasePanelFocus()
        down.flags = .maskCommand
        up.flags = .maskCommand
        // Deliver one normal paste to the verified application. This preserves
        // editor input events and its undo stack, including web contenteditable.
        down.postToPid(target.pid)
        up.postToPid(target.pid)
        // Independent task: cancellation of the translation must not restore
        // the clipboard before the target has had time to consume the paste.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            lease.restore()
        }
        try await Task.sleep(nanoseconds: 800_000_000)
        lease.restore()
        // Never retry a paste whose result is uncertain: it could duplicate text.
        return await target.currentValue() == expected
    }
}
