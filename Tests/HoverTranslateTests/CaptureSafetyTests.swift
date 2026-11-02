import Foundation
import CoreGraphics

@main
struct CaptureSafetyChecks {
    static func main() async {
        do {
            _ = try await ScreenshotCapture.image(in: .zero) { _, completion in
                DispatchQueue.global().async { completion(nil, nil) }
            }
            DiagnosticCheck.fail("An empty screenshot must throw instead of crashing")
        } catch ScreenshotError.unavailable { }
        catch { DiagnosticCheck.fail("Unexpected empty-screenshot error: \(error)") }

        let failure = NSError(domain: "ScreenshotCheck", code: 7)
        do {
            _ = try await ScreenshotCapture.image(in: .zero) { _, completion in completion(nil, failure) }
            DiagnosticCheck.fail("Screenshot errors must be preserved")
        } catch {
            DiagnosticCheck.require((error as NSError).domain == failure.domain && (error as NSError).code == failure.code)
        }

        guard let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = context.makeImage() else { DiagnosticCheck.fail("Cannot create screenshot fixture") }
        do {
            let captured = try await ScreenshotCapture.image(in: CGRect(x: 10, y: 20, width: 2, height: 2)) { rect, completion in
                DiagnosticCheck.require(rect.origin == CGPoint(x: 10, y: 20), "Capture region must be preserved")
                completion(image, nil)
            }
            DiagnosticCheck.require(captured === image, "Successful captures preserve the original image")
        } catch { DiagnosticCheck.fail("Valid screenshot failed: \(error)") }

        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await ScreenshotCapture.image(in: .zero) { _, _ in
                    DiagnosticCheck.fail("Cancelled captures must not request a screenshot")
                }
                DiagnosticCheck.fail("Cancellation must propagate")
            } catch is CancellationError { }
            catch { DiagnosticCheck.fail("Unexpected cancellation error: \(error)") }
        }
        await cancelled.value

        let cancelledDuringCapture = Task {
            do {
                _ = try await ScreenshotCapture.image(in: .zero) { _, completion in
                    withUnsafeCurrentTask { $0?.cancel() }
                    completion(image, nil)
                }
                DiagnosticCheck.fail("An image delivered after cancellation must be discarded")
            } catch is CancellationError { }
            catch { DiagnosticCheck.fail("Unexpected late-cancellation error: \(error)") }
        }
        await cancelledDuringCapture.value

        var lifecycle = CaptureLifecycle()
        DiagnosticCheck.require(lifecycle.isReady(at: 100), "Normal startup allows capture")
        lifecycle.suspend(.systemSleep)
        lifecycle.suspend(.displaySleep)
        lifecycle.suspend(.inactiveSession)
        DiagnosticCheck.require(!lifecycle.isReady(at: 1000), "Sleep cannot expire on a timer")
        lifecycle.resume(.systemSleep, at: 1000)
        DiagnosticCheck.require(!lifecycle.isReady(at: 1010), "System wake cannot override display sleep")
        lifecycle.resume(.displaySleep, at: 1010)
        DiagnosticCheck.require(!lifecycle.isReady(at: 1020), "Display wake cannot override an inactive session")
        lifecycle.resume(.inactiveSession, at: 1020)
        DiagnosticCheck.require(!lifecycle.isReady(at: 1021.99), "Capture waits for display recovery")
        DiagnosticCheck.require(lifecycle.isReady(at: 1022), "Capture resumes after the recovery delay")
        lifecycle.deferCapture(at: 1021)
        DiagnosticCheck.require(!lifecycle.isReady(at: 1022), "Display reconfiguration extends the recovery delay")
        DiagnosticCheck.require(lifecycle.isReady(at: 1023))
        lifecycle.suspend(.displaySleep)
        DiagnosticCheck.require(!lifecycle.isReady(at: 2000), "A second sleep suspends capture again")
        lifecycle.resume(.displaySleep, at: 2000)
        DiagnosticCheck.require(lifecycle.isReady(at: 2002), "Repeated sleep/wake cycles recover")
        print("Capture safety checks passed: empty callback, original error, valid image, cancellation before/after capture, overlapping sleep/session states and recovery delay.")
    }
}
