import Foundation

/// Diagnostic failures must fail the command, not crash a GUI application and
/// summon macOS Problem Reporter. Production safety guards remain independent.
enum DiagnosticCheck {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String = "Condition failed",
                        file: StaticString = #fileID, line: UInt = #line) {
        if !condition() { fail(message, file: file, line: line) }
    }

    static func fail(_ message: String, file: StaticString = #fileID, line: UInt = #line) -> Never {
        let output = "CHECK FAILED: \(file):\(line): \(message)\n"
        FileHandle.standardError.write(Data(output.utf8))
        exit(EXIT_FAILURE)
    }
}
