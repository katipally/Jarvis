import SwiftUI

/// Shared animation constants — single source of truth for the notch's
/// open/close/tab springs so every call site stays in step.
enum NotchAnimation {
    static let open = Animation.spring(response: 0.40, dampingFraction: 0.78)
    static let close = Animation.spring(response: 0.34, dampingFraction: 0.9)
    static let tab = Animation.spring(response: 0.36, dampingFraction: 0.82)
}

/// Semantic palette — every status/accent color in the notch UI routes through
/// these so identical meanings always use identical colors.
extension Color {
    static let jarvisError = Color(red: 1.0, green: 0.45, blue: 0.45)
    static let jarvisSuccess = Color(red: 0.4, green: 0.85, blue: 0.5)
    static let jarvisWarning = Color(red: 1.0, green: 0.75, blue: 0.3)
    static let jarvisAccent = Color(red: 0.3, green: 0.55, blue: 1.0)
    static let jarvisLink = Color(red: 0.4, green: 0.7, blue: 1.0)
}

/// Type scale — identical roles use identical fonts across every view.
extension Font {
    static let jarvisTitle = Font.system(size: 15, weight: .semibold)
    static let jarvisBody = Font.system(size: 13)
    static let jarvisRow = Font.system(size: 12, weight: .medium)
    static let jarvisCaption = Font.system(size: 11)
    static let jarvisFootnote = Font.system(size: 10)
}

// MARK: - Surfaces on the pure-black notch

extension Color {
    /// Card / pill / row fill — bright enough to separate from the black body.
    static let jarvisSurface = Color.white.opacity(0.08)
    static let jarvisSurfaceHover = Color.white.opacity(0.13)
    /// Emphasized surface (user bubbles, selected states).
    static let jarvisSurfaceActive = Color.white.opacity(0.15)
    /// Hairline stroke that keeps surfaces from dissolving into the background.
    static let jarvisStroke = Color.white.opacity(0.10)
}
