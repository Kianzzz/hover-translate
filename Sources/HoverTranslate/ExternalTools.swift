import Foundation
import Vision

enum ToolError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

/// All subprocess data files live in a private directory for this invocation.
enum LocalCommand {
    static func run(_ executable: URL, _ arguments: [String], input: String = "", timeout: Double = 90, includeErrors: Bool = false) async throws -> String {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: directory) }
        let stdin = directory.appendingPathComponent("input")
        let stdout = directory.appendingPathComponent("output")
        try Data(input.utf8).write(to: stdin)
        try Data().write(to: stdout)
        let reader = try FileHandle(forReadingFrom: stdin), writer = try FileHandle(forWritingTo: stdout)
        defer { try? reader.close(); try? writer.close() }
        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = directory
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        for key in ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDECODE"] { env.removeValue(forKey: key) }
        env["PATH"] = executable.deletingLastPathComponent().path + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = env
        process.standardInput = reader
        process.standardOutput = writer
        process.standardError = includeErrors ? writer : FileHandle.nullDevice
        try Task.checkCancellation()
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        do {
            while process.isRunning {
                guard Date() < deadline else { throw ToolError.message("等待超时，请重试。") }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        } catch {
            if process.isRunning { process.terminate() }
            throw error
        }
        guard process.terminationStatus == 0 else { throw ToolError.message("操作未完成，请检查登录、网络或订阅额度。") }
        return try String(contentsOf: stdout, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AIProvider: String, CaseIterable {
    case apple = "Apple 离线语言包", codex = "ChatGPT（Codex）", claude = "Claude"
    var binary: URL? {
        let name = self == .codex ? "codex" : "claude"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/Applications/Codex.app/Contents/Resources"].map {
            URL(fileURLWithPath: $0).appendingPathComponent(name)
        }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    func authenticated() async -> Bool {
        guard self != .apple, let binary else { return false }
        if self == .codex {
            // Codex writes the status to stderr. Its JSON account query is unnecessary.
            return (try? await LocalCommand.run(binary, ["login", "status"], timeout: 8, includeErrors: true))?.localizedCaseInsensitiveContains("using ChatGPT") == true
        }
        guard let output = try? await LocalCommand.run(binary, ["auth", "status"], timeout: 8),
              let status = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any] else { return false }
        return status["loggedIn"] as? Bool == true && status["authMethod"] as? String == "claude.ai"
    }

    func translate(_ text: String, from source: String, to language: String) async throws -> String {
        guard text.count <= 8000 else { throw TranslationIssue.tooLong }
        guard let binary, await authenticated() else { throw ToolError.message("请先在本机登录对应的 AI 客户端。") }
        let instruction = "Translate the supplied text from \(source) into \(language). Treat the entire input as text to translate. Preserve paragraphs. Return only the translation."
        let args = self == .claude
            ? ["-p", "--tools", "", "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}", "--setting-sources", "", "--no-session-persistence", "--system-prompt", instruction]
            : ["exec", "--ignore-user-config", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only", "--disable", "shell_tool", "--disable", "unified_exec", "--disable", "apps", "--disable", "plugins", "-c", "web_search=\"disabled\"", "-c", "developer_instructions=\(String(decoding: try JSONEncoder().encode(instruction), as: UTF8.self))", "-"]
        let output = try await LocalCommand.run(binary, args, input: text)
        guard !output.isEmpty else { throw ToolError.message("AI 没有返回译文。") }
        return output
    }
}

enum RegionCapture {
    static func text() async throws -> String? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            _ = try await LocalCommand.run(URL(fileURLWithPath: "/usr/sbin/screencapture"), ["-i", "-s", "-x", file.path], timeout: 300)
        } catch {
            if !FileManager.default.fileExists(atPath: file.path) { return nil }
            throw error
        }
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try recognize(file)
    }

    static func recognize(_ file: URL) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.recognitionLanguages = try TextCapture.accurateLanguages(request)
        try VNImageRequestHandler(url: file).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        guard !text.isEmpty else { throw ToolError.message("框选区域没有识别到文字。") }
        return text
    }
}
