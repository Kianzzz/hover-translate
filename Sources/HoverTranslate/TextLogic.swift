import Foundation
import NaturalLanguage
import AppKit

enum TextLogic {
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func language(of text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        if recognizer.dominantLanguage == .simplifiedChinese || recognizer.dominantLanguage == .traditionalChinese { return "zh-Hans" }
        if recognizer.dominantLanguage == .english { return "en" }
        let chinese = text.unicodeScalars.filter { (0x3400...0x9FFF).contains($0.value) }.count
        let latin = text.unicodeScalars.filter { (65...90).contains($0.value) || (97...122).contains($0.value) }.count
        return chinese > latin / 2 ? "zh-Hans" : "en"
    }

    static func hasEnglish(_ text: String) -> Bool {
        text.range(of: "[A-Za-z]{2,}", options: .regularExpression) != nil && language(of: text) == "en"
    }

    static func segment(_ text: String, utf16Offset: Int, word: Bool) -> String? {
        guard !text.isEmpty, utf16Offset >= 0, utf16Offset < text.utf16.count else { return nil }
        let utfIndex = text.utf16.index(text.utf16.startIndex, offsetBy: utf16Offset)
        guard let index = String.Index(utfIndex, within: text) else { return nil }
        let tokenizer = NLTokenizer(unit: word ? .word : .sentence)
        tokenizer.string = text
        let range = tokenizer.tokenRange(at: index)
        let result = clean(String(text[range]))
        return !result.isEmpty && result.count <= 1200 ? result : nil
    }

    /// Cocoa uses bottom-left screen coordinates; AX and screen capture use top-left.
    static func quartzPoint(_ cocoa: CGPoint, desktopTop: CGFloat) -> CGPoint {
        CGPoint(x: cocoa.x, y: desktopTop - cocoa.y)
    }

    static func cocoaRect(_ quartz: CGRect, desktopTop: CGFloat) -> CGRect {
        CGRect(x: quartz.minX, y: desktopTop - quartz.maxY, width: quartz.width, height: quartz.height)
    }

    static func panelFrame(anchor: CGRect, size: CGSize, visible: CGRect) -> CGRect {
        let x = min(max(anchor.minX, visible.minX + 12), visible.maxX - size.width - 12)
        var y = anchor.minY - size.height - 12
        if y < visible.minY + 12 { y = anchor.maxY + 12 }
        y = min(max(y, visible.minY + 12), visible.maxY - size.height - 12)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    static func badgeFrame(pointer: CGPoint, visible: CGRect) -> CGRect {
        let size: CGFloat = 30
        var x = pointer.x + 14
        var y = pointer.y - size - 10
        if x + size > visible.maxX - 6 { x = pointer.x - size - 14 }
        if y < visible.minY + 6 { y = pointer.y + 12 }
        x = min(max(x, visible.minX + 6), visible.maxX - size - 6)
        y = min(max(y, visible.minY + 6), visible.maxY - size - 6)
        return CGRect(x: x, y: y, width: size, height: size)
    }

    static func hoverTransitContains(_ point: CGPoint, from source: CGRect, to destination: CGRect) -> Bool {
        // A narrow bridge keeps the icon reachable without retaining unrelated screen areas.
        let start = CGPoint(x: min(max(destination.midX, source.minX), source.maxX),
                            y: min(max(destination.midY, source.minY), source.maxY))
        let end = CGPoint(x: destination.midX, y: destination.midY)
        let dx = end.x - start.x, dy = end.y - start.y
        let denominator = dx * dx + dy * dy
        let t = denominator > 0 ? min(1, max(0, ((point.x-start.x)*dx + (point.y-start.y)*dy) / denominator)) : 0
        return hypot(point.x - (start.x + t*dx), point.y - (start.y + t*dy)) <= 15
    }
}

struct CapturedText: Sendable {
    let text: String
    let bounds: CGRect
    let method: String
}

struct SelectionEdit: Sendable {
    let value: String
    let selected: String
    let range: NSRange

    func replacing(with translation: String) -> String? {
        let text = value as NSString
        guard range.location != NSNotFound, range.location >= 0, range.length > 0,
              range.location <= text.length, range.length <= text.length - range.location,
              text.substring(with: range) == selected else { return nil }
        return text.replacingCharacters(in: range, with: translation)
    }
}

enum CardLayout {
    static let minimumWidth: CGFloat = 240
    static let maximumWidth: CGFloat = 520
    static let translationFontSize: CGFloat = 14
    static let headerHeight: CGFloat = 30

    static func width(source: String, result: String) -> CGFloat {
        func measured(_ text: String, size: CGFloat) -> CGFloat {
            text.components(separatedBy: .newlines).map {
                ($0 as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size)]).width
            }.max() ?? 0
        }
        // Include the source at reading size so an ordinary sentence stays wide
        // enough when its shorter Chinese translation replaces the loading state.
        let content = max(measured(source, size: translationFontSize), measured(result, size: translationFontSize))
        var desired = content + 32
        if content > 240 { desired = max(360, desired) }
        if content > 488 { desired = maximumWidth }
        return min(maximumWidth, max(minimumWidth, ceil(desired)))
    }

    static func bodyHeight(result: String, width: CGFloat, loading: Bool, choosing: Bool, failure: Bool) -> CGFloat {
        if loading || choosing { return 20 }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        let measured = ceil((result as NSString).boundingRect(with: CGSize(width: width - 24, height: 10000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: translationFontSize), .paragraphStyle: paragraph]).height)
        return failure ? min(88, max(42, measured + 24)) : min(60, max(20, measured))
    }
}
