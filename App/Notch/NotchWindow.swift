import AppKit
import SwiftUI

final class NotchWindow: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)

        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = Self.normalLevel
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
    }

    /// Above the menu bar — the notch must cover the menu-bar strip.
    static let normalLevel: NSWindow.Level = .mainMenu + 3

    /// While a system permission/auth dialog is up, drop below it so the user
    /// can actually see and answer it (the notch would otherwise cover it).
    func setYieldsToSystemDialog(_ yields: Bool) {
        level = yields ? .floating : Self.normalLevel
    }

    /// The panel takes the keyboard only while it's expanded (see
    /// NotchScreenManager.updateKeyboardCapture): opening focuses the composer so
    /// you can type straight in; closing hands the keyboard back to your app.
    /// .nonactivatingPanel keeps the underlying app active throughout.
    var keyboardCaptureAllowed = false {
        didSet {
            guard oldValue != keyboardCaptureAllowed else { return }
            if keyboardCaptureAllowed {
                makeKey()
            } else if isKeyWindow {
                // Give up key + first responder so the frontmost app's window
                // reclaims the keyboard (the notch stays on top at its level).
                makeFirstResponder(nil)
                resignKey()
            }
        }
    }
    override var canBecomeKey: Bool { keyboardCaptureAllowed }
    override var canBecomeMain: Bool { false }
}

/// The panel never becomes key, so views must accept the first mouse click
/// or taps get swallowed by window activation.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
