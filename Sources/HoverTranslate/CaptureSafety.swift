import Foundation
import CoreGraphics
import ScreenCaptureKit

enum ScreenshotError: LocalizedError {
    case unavailable
    var errorDescription: String? { "屏幕暂不可用，请在屏幕恢复后重试。" }
}

enum ScreenshotCapture {
    typealias Completion = @Sendable (CGImage?, Error?) -> Void
    typealias Request = (CGRect, @escaping Completion) -> Void

    static func image(in rect: CGRect, using request: Request = { rect, completion in
        SCScreenshotManager.captureImage(in: rect, completionHandler: completion)
    }) async throws -> CGImage {
        try Task.checkCancellation()
        // During display sleep ScreenCaptureKit can return both image and error
        // as nil. Its generated async bridge force-unwraps that missing image.
        let image: CGImage = try await withCheckedThrowingContinuation { continuation in
            request(rect) { image, error in
                if let error { continuation.resume(throwing: error) }
                else if let image { continuation.resume(returning: image) }
                else { continuation.resume(throwing: ScreenshotError.unavailable) }
            }
        }
        try Task.checkCancellation()
        return image
    }
}

struct CaptureLifecycle {
    enum Suspension: Hashable { case systemSleep, displaySleep, inactiveSession }
    private var suspensions = Set<Suspension>()
    private var readyAfter: TimeInterval = 0

    func isReady(at uptime: TimeInterval) -> Bool {
        suspensions.isEmpty && uptime >= readyAfter
    }

    mutating func suspend(_ reason: Suspension) {
        suspensions.insert(reason)
    }

    mutating func resume(_ reason: Suspension, at uptime: TimeInterval) {
        suspensions.remove(reason)
        deferCapture(at: uptime)
    }

    mutating func deferCapture(at uptime: TimeInterval) {
        readyAfter = max(readyAfter, uptime + 2)
    }
}
