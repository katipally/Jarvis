import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

public struct CapturedFrame: Sendable {
    public var jpeg: Data
    public var phash: Int64
    public var appBundleID: String?
    public var appName: String?
    public var windowTitle: String?
    public var displayID: Int
    public var base64: String { jpeg.base64EncodedString() }
}

/// Captures the frontmost window via ScreenCaptureKit, downscaled to a small JPEG.
public enum ScreenCapture {
    public static let maxWidth = 1280
    public static let jpegQuality: CGFloat = 0.5

    public static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    public static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    public static var isScreenLocked: Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (info["CGSSessionScreenIsLocked"] as? Int) == 1
    }

    /// Capture the frontmost app's largest on-screen window.
    public static func captureFrontWindow() async throws -> CapturedFrame? {
        guard hasPermission else { throw ScreenError.permissionDenied }
        let frontPID = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let candidates = content.windows.filter { window in
            window.isOnScreen && window.frame.width > 120 && window.frame.height > 80 &&
            (frontPID == nil || window.owningApplication?.processID == frontPID)
        }
        guard let window = candidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            return nil
        }

        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width)
        config.height = Int(window.frame.height)
        config.showsCursor = false
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        guard let jpeg = encodeJPEG(cgImage) else { return nil }
        let phash = PerceptualHash.averageHash(cgImage)
        return CapturedFrame(
            jpeg: jpeg, phash: phash,
            appBundleID: window.owningApplication?.bundleIdentifier,
            appName: window.owningApplication?.applicationName,
            windowTitle: window.title,
            // SCWindow doesn't expose its display, so resolve it from the window's
            // center point (SCWindow.frame is in the CG global display space, which
            // is exactly what CGGetDisplaysWithPoint expects).
            displayID: Self.displayID(containing: window.frame)
        )
    }

    private static func displayID(containing frame: CGRect) -> Int {
        var display = CGDirectDisplayID(0)
        var count: UInt32 = 0
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if CGGetDisplaysWithPoint(center, 1, &display, &count) == .success, count > 0 {
            return Int(display)
        }
        return 0
    }

    static func encodeJPEG(_ image: CGImage) -> Data? {
        let scaled = downscale(image, maxWidth: maxWidth)
        let rep = NSBitmapImageRep(cgImage: scaled)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: jpegQuality])
    }

    private static func downscale(_ image: CGImage, maxWidth: Int) -> CGImage {
        guard image.width > maxWidth else { return image }
        let scale = CGFloat(maxWidth) / CGFloat(image.width)
        let w = maxWidth
        let h = Int(CGFloat(image.height) * scale)
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return image }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }
}

public enum ScreenError: Error, LocalizedError {
    case permissionDenied
    case noWindow
    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Screen Recording permission is required. Grant it in System Settings › Privacy & Security › Screen Recording."
        case .noWindow:
            "No capturable window is frontmost right now."
        }
    }
}
