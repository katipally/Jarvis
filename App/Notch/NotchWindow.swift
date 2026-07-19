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
        // Take keyboard only when a text field is clicked — not on hover/buttons.
        becomesKeyOnlyIfNeeded = true
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

    // Must become key so text fields (composer, API key entry) accept input.
    // .nonactivatingPanel keeps the underlying app active while we take keyboard.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The panel never becomes key, so views must accept the first mouse click
/// or taps get swallowed by window activation.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
