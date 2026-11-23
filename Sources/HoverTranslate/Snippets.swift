import Foundation

struct Snippet: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var text: String
    var translation: String?
    var sourceLanguage: String?
    var targetLanguage: String?
    var appName: String?
    let createdAt: Date

    init(id: UUID = UUID(), text: String, translation: String? = nil,
         sourceLanguage: String? = nil, targetLanguage: String? = nil,
         appName: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.translation = translation
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.appName = appName
        self.createdAt = createdAt
    }

    func markdownEntry(dateFormatter: DateFormatter) -> String {
        let timestamp = dateFormatter.string(from: createdAt)
        let header = appName.map { !($0.isEmpty) ? "## \(timestamp) · \($0)" : "## \(timestamp)" } ?? "## \(timestamp)"
        let quoted = text.components(separatedBy: .newlines).map { "> \($0)" }.joined(separator: "\n")
        var lines = [header, "", quoted]
        if let translation, !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append(translation)
        }
        lines.append("")
        lines.append("---")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}

enum SnippetStore {
    static let defaultMarkdownURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("浮译摘录.md")
    }()

    static let indexURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("HoverTranslate", isDirectory: true)
            .appendingPathComponent("snippets.json")
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    static func load(from url: URL = indexURL) -> [Snippet] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Snippet].self, from: data)) ?? []
    }

    static func saveIndex(_ snippets: [Snippet], to url: URL = indexURL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snippets)
        try data.write(to: url, options: .atomic)
    }

    /// Appends a snippet non-destructively so user edits or Obsidian notes in the target file are preserved.
    static func appendMarkdown(_ snippet: Snippet, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let entry = snippet.markdownEntry(dateFormatter: formatter)
        if !fm.fileExists(atPath: url.path) {
            let initial = "# 浮译摘录\n\n" + entry
            try initial.write(to: url, atomically: true, encoding: .utf8)
            return
        }
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let prefix = existing.isEmpty ? "# 浮译摘录\n\n" : (existing.hasSuffix("\n\n") ? "" : (existing.hasSuffix("\n") ? "\n" : "\n\n"))
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        if let data = (prefix + entry).data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
    }

    static func exportMarkdown(_ snippets: [Snippet]) -> String {
        var output = "# 浮译摘录\n\n"
        for snippet in snippets {
            output += snippet.markdownEntry(dateFormatter: formatter) + "\n"
        }
        return output
    }
}
