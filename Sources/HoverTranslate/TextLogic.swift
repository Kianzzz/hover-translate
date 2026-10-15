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

    /// Keep UTF16 offsets stable while treating soft line wraps as spaces.
    /// Blank lines remain paragraph boundaries; never truncate a sentence mid-way.
    static func segmentRange(_ text: String, utf16Offset: Int, word: Bool) -> NSRange? {
        let raw = text as NSString
        guard raw.length > 0, utf16Offset >= 0, utf16Offset < raw.length else { return nil }
        var start = 0, end = raw.length
        if !word {
            guard let breaks = try? NSRegularExpression(pattern: "\\n[ \\t\\r]*\\n|\\r[ \\t]*\\r") else { return nil }
            for boundary in breaks.matches(in: text, range: NSRange(location: 0, length: raw.length)) {
                if NSMaxRange(boundary.range) <= utf16Offset { start = NSMaxRange(boundary.range) }
                else if boundary.range.location > utf16Offset { end = boundary.range.location; break }
                else { return nil }
            }
        }
        let paragraph = raw.substring(with: NSRange(location: start, length: end - start))
            .replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        let offset = utf16Offset - start
        let utf = paragraph.utf16.index(paragraph.utf16.startIndex, offsetBy: offset)
        guard let index = String.Index(utf, within: paragraph) else { return nil }
        let tokenizer = NLTokenizer(unit: word ? .word : .sentence)
        tokenizer.string = paragraph
        let token = NSRange(tokenizer.tokenRange(at: index), in: paragraph)
        guard token.length > 0 else { return nil }
        return NSRange(location: start + token.location, length: token.length)
    }

    static func segment(_ text: String, utf16Offset: Int, word: Bool) -> String? {
        guard let range = segmentRange(text, utf16Offset: utf16Offset, word: word) else { return nil }
        let result = clean((text as NSString).substring(with: range)
            .replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " "))
        return !result.isEmpty && result.count <= 4000 ? result : nil
    }

    struct OCRLine {
        let text: String
        let bounds: CGRect
    }

    /// Vision boxes use top-left coordinates here. Follow only the same column,
    /// with normal line spacing, stopping at paragraph gaps or neighboring UI.
    static func ocrSentence(lines: [OCRLine], hit: Int, offset: Int) -> String? {
        guard lines.indices.contains(hit) else { return nil }
        func follows(_ top: OCRLine, _ bottom: OCRLine) -> Bool {
            let height = max(top.bounds.height, bottom.bounds.height)
            let gap = bottom.bounds.minY - top.bounds.maxY
            let aligned = abs(top.bounds.minX - bottom.bounds.minX) <= max(20, height * 1.3)
            let prose = max(top.text.count, bottom.text.count) >= 32
                && max(top.bounds.width, bottom.bounds.width) >= 160
            return aligned && prose && bottom.bounds.midY > top.bounds.midY
                && gap >= -height * 0.2 && gap <= height * 1.15
        }
        let order = lines.indices.sorted { lines[$0].bounds.midY < lines[$1].bounds.midY }
        guard let position = order.firstIndex(of: hit) else { return nil }
        var block = [hit]
        var current = hit
        for index in order[..<position].reversed() {
            if lines[index].bounds.midY >= lines[current].bounds.minY { continue }
            if follows(lines[index], lines[current]) {
                block.insert(index, at: 0); current = index
                if block.count >= 14 { break }
            } else if abs(lines[index].bounds.minX - lines[current].bounds.minX) <= 30 { break }
        }
        current = hit
        for index in order[(position + 1)...] {
            if lines[index].bounds.midY <= lines[current].bounds.maxY { continue }
            if follows(lines[current], lines[index]) {
                block.append(index); current = index
                if block.count >= 28 { break }
            } else if abs(lines[index].bounds.minX - lines[current].bounds.minX) <= 30 { break }
        }
        var joined = "", hitOffset = 0
        for index in block {
            if !joined.isEmpty { joined += " " }
            if index == hit { hitOffset = joined.utf16.count + min(max(0, offset), max(0, lines[index].text.utf16.count - 1)) }
            joined += lines[index].text
        }
        return segment(joined, utf16Offset: hitOffset, word: false)
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

    static func badgeFrame(pointer: CGPoint, visible: CGRect, source: CGRect = .zero) -> CGRect {
        let size: CGFloat = 30, gap: CGFloat = 6
        let safe = visible.insetBy(dx: 6, dy: 6)
        func clamped(_ x: CGFloat, _ y: CGFloat) -> CGRect {
            CGRect(x: min(max(x, safe.minX), safe.maxX - size),
                   y: min(max(y, safe.minY), safe.maxY - size), width: size, height: size)
        }
        // Use real text bounds when available. Prefer the closest edge, not the
        // end of a long sentence. Keep the badge fixed while the pointer travels.
        if !source.isEmpty, !source.isInfinite, !source.isNull {
            let options = [
                clamped(pointer.x - size / 2, source.minY - gap - size),
                clamped(pointer.x - size / 2, source.maxY + gap),
                clamped(source.maxX + gap, pointer.y - size / 2),
                clamped(source.minX - gap - size, pointer.y - size / 2)
            ].filter { !$0.intersects(source.insetBy(dx: -3, dy: -3)) }
            if let closest = options.min(by: { distance(pointer, to: $0) < distance(pointer, to: $1) }),
               distance(pointer, to: closest) <= 64 { return closest }
        }
        // Some apps expose the entire container instead of a text line. Do not
        // send the icon to that container's distant edge.
        let x = pointer.x + gap + size <= safe.maxX ? pointer.x + gap : pointer.x - size - gap
        let y = pointer.y - size - gap >= safe.minY ? pointer.y - size - gap : pointer.y + gap
        return clamped(x, y)
    }

    static func distance(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        hypot(max(rect.minX - point.x, 0, point.x - rect.maxX),
              max(rect.minY - point.y, 0, point.y - rect.maxY))
    }

    static func movingTowardBadge(from previous: CGPoint, to point: CGPoint, badge: CGRect) -> Bool {
        let dx = point.x - previous.x, dy = point.y - previous.y
        let length = hypot(dx, dy)
        guard length >= 0.5 else { return false }
        let tx = badge.midX - previous.x, ty = badge.midY - previous.y
        let targetLength = hypot(tx, ty)
        guard targetLength > 0 else { return false }
        // A generous approach cone permits diagonal movement and curved paths.
        return (dx * tx + dy * ty) / (length * targetLength) >= 0.35
            && distance(point, to: badge) < distance(previous, to: badge)
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
    static let maximumBodyHeight: CGFloat = 260

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
        return failure ? min(88, max(42, measured + 24)) : min(maximumBodyHeight, max(20, measured + 2))
    }
}
