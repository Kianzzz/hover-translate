import Foundation
import NaturalLanguage
import AppKit

enum TextLogic {
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Languages offered in settings; identifiers match Apple Translation.
    static let languages: [(id: String, name: String)] = [
        ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"), ("en", "English"), ("ja", "日本語"),
        ("ko", "한국어"), ("fr", "Français"), ("de", "Deutsch"), ("es", "Español"),
        ("it", "Italiano"), ("pt-BR", "Português"), ("ru", "Русский"), ("ar", "العربية"),
        ("th", "ไทย"), ("vi", "Tiếng Việt"), ("id", "Bahasa Indonesia"), ("tr", "Türkçe"),
        ("nl", "Nederlands"), ("pl", "Polski"), ("uk", "Українська"), ("hi", "हिन्दी")
    ]

    static func displayName(_ id: String) -> String {
        let chinese = ["zh-Hans": "中文", "zh-Hant": "繁体中文", "en": "英语", "ja": "日语", "ko": "韩语",
                       "fr": "法语", "de": "德语", "es": "西班牙语", "it": "意大利语", "pt-BR": "葡萄牙语",
                       "ru": "俄语", "ar": "阿拉伯语", "th": "泰语", "vi": "越南语", "id": "印尼语",
                       "tr": "土耳其语", "nl": "荷兰语", "pl": "波兰语", "uk": "乌克兰语", "hi": "印地语"]
        return chinese[id] ?? Locale(identifier: "zh-Hans").localizedString(forIdentifier: id) ?? id
    }

    /// Script decides CJK; the statistical recognizer only chooses among the
    /// offered languages, and Latin text must be clearly non-English to switch.
    static func language(of text: String) -> String {
        func count(_ ranges: [ClosedRange<UInt32>]) -> Int {
            text.unicodeScalars.filter { scalar in ranges.contains { $0.contains(scalar.value) } }.count
        }
        // Exclude ・ and ー: Chinese text uses them too.
        let kana = count([0x3040...0x309F, 0x30A0...0x30FA, 0x30FD...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F])
        let hangul = count([0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF])
        let han = count([0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF])
        let latin = count([0x41...0x5A, 0x61...0x7A, 0xC0...0x24F])
        if kana > 0, kana + han >= latin { return "ja" }
        if hangul > 0, hangul >= latin { return "ko" }
        if han > 0, han * 2 > latin {
            let recognizer = NLLanguageRecognizer()
            recognizer.languageConstraints = [.simplifiedChinese, .traditionalChinese]
            recognizer.processString(text)
            return recognizer.dominantLanguage == .traditionalChinese ? "zh-Hant" : "zh-Hans"
        }
        let candidates: [NLLanguage: String] = [
            .english: "en", .french: "fr", .german: "de", .spanish: "es", .italian: "it", .portuguese: "pt-BR",
            .russian: "ru", .arabic: "ar", .thai: "th", .vietnamese: "vi", .indonesian: "id", .turkish: "tr",
            .dutch: "nl", .polish: "pl", .ukrainian: "uk", .hindi: "hi"
        ]
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = Array(candidates.keys)
        recognizer.processString(text)
        guard let (top, confidence) = recognizer.languageHypotheses(withMaximum: 3).max(by: { $0.value < $1.value }),
              let id = candidates[top] else { return "en" }
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        // Short UI labels and loanword-heavy phrases are mostly English in practice.
        if latin * 2 >= letters, top != .english {
            let words = text.split { !$0.isLetter && $0 != "'" && $0 != "-" }.count
            return words >= 4 && confidence >= 0.8 ? id : "en"
        }
        return id
    }

    /// Latin-only OCR turns CJK glyphs into letter soup. Keep a result only when
    /// most of its words are real words in the detected language's dictionary.
    static func plausibleOCR(_ text: String) -> Bool {
        let words = text.split { !$0.isLetter && $0 != "'" }.filter { $0.count >= 2 }.count
        guard words > 0 else { return false }
        let checker = NSSpellChecker.shared
        let language = baseLanguage(language(of: text))
        let nsText = text as NSString
        var misspelled = 0, start = 0
        while start < nsText.length {
            let range = checker.checkSpelling(of: text, startingAt: start, language: language, wrap: false,
                                              inSpellDocumentWithTag: 0, wordCount: nil)
            guard range.location != NSNotFound, range.length > 0 else { break }
            misspelled += 1
            start = NSMaxRange(range)
        }
        return misspelled * 3 <= words
    }

    /// Chinese scripts count as one language when deciding what is "native".
    static func baseLanguage(_ id: String) -> String {
        String(id.split(separator: "-").first ?? Substring(id))
    }

    /// Short Chinese is often ambiguous between scripts, so scripts never count as a translation.
    static func sameLanguage(_ left: String, _ right: String) -> Bool {
        baseLanguage(left) == baseLanguage(right)
    }

    /// Hover only offers translation for real words outside the native language.
    static func isForeign(_ text: String, native: String) -> Bool {
        text.range(of: "\\p{L}{2,}", options: .regularExpression) != nil
            && baseLanguage(language(of: text)) != baseLanguage(native)
    }

    /// Text already in the preferred language falls back to native, then English.
    static func target(for source: String, preferred: String, native: String) -> String {
        [preferred, native, "en", "zh-Hans"].first { !sameLanguage(source, $0) } ?? preferred
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
        // Bounds taller than about two lines are usually a padded control or text
        // block; their edges can be far from the pointer, so stay by the pointer.
        if !source.isEmpty, !source.isInfinite, !source.isNull, source.height <= 40 {
            let options = [
                clamped(pointer.x - size / 2, source.minY - gap - size),
                clamped(pointer.x - size / 2, source.maxY + gap),
                clamped(source.maxX + gap, pointer.y - size / 2),
                clamped(source.minX - gap - size, pointer.y - size / 2)
            ].filter { !$0.intersects(source.insetBy(dx: -3, dy: -3)) }
            if let closest = options.min(by: { distance(pointer, to: $0) < distance(pointer, to: $1) }),
               distance(pointer, to: closest) <= 24 { return closest }
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
    static let translationFontSize: CGFloat = 15
    static let headerHeight: CGFloat = 32
    static let maximumBodyHeight: CGFloat = 260
    static let sourceFontSize: CGFloat = 12
    static let sourceLineLimit = 3

    /// The source stays readable but compact: at most three lines above the translation.
    static func sourceHeight(source: String, width: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: sourceFontSize)
        let line = ceil(font.ascender - font.descender + font.leading) + 2
        let measured = ceil((source as NSString).boundingRect(with: CGSize(width: width - 32, height: 10000),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).height)
        let lines = max(1, min(CGFloat(sourceLineLimit), (measured / max(1, ceil(font.ascender - font.descender + font.leading))).rounded(.up)))
        return lines * line
    }

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
        let measured = ceil((result as NSString).boundingRect(with: CGSize(width: width - 32, height: 10000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: translationFontSize), .paragraphStyle: paragraph]).height)
        return failure ? min(96, max(50, measured + 32)) : min(maximumBodyHeight, max(20, measured + 2))
    }
}
