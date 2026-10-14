import Foundation

@main
struct DiagnosticExitChecks {
    static func main() {
        if CommandLine.arguments.contains("--fail") {
            DiagnosticCheck.require(false, "Deliberate diagnostic failure")
        }
        DiagnosticCheck.require(true, "Success must continue")
        print("Diagnostic success path passed.")
    }
}
