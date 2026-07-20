import SwiftUI

/// Shared animation constants — single source of truth for the notch's
/// open/close/tab springs so every call site stays in step.
enum NotchAnimation {
    static let open = Animation.spring(response: 0.40, dampingFraction: 0.78)
    static let close = Animation.spring(response: 0.34, dampingFraction: 0.9)
    static let tab = Animation.spring(response: 0.36, dampingFraction: 0.82)
}

/// Single source of truth for the notch's fixed geometry constants. Every
/// camera-reserve gap, size delta, and corner radius routes through here so the
/// closed "bars" and the open header stay pixel-aligned — a hard requirement for
/// the matched-geometry morph, where a mismatched reserve makes content jump.
enum NotchMetrics {
    /// Notch size on displays without a physical notch.
    static let fallbackClosedSize = CGSize(width: 185, height: 32)
    /// Gap flanking the camera housing in the compact bars (listening/peek/meeting/working).
    static let cameraSideReserve: CGFloat = 22
    /// Central void reserved for the camera in the open tab header.
    static let headerCameraReserve: CGFloat = 28
    /// Width added to the closed notch for the slim status bar (meeting).
    static let statusExtraWidth: CGFloat = 150
    /// Width/height added to the closed notch for the listening chrome. Just
    /// enough for a small waveform hugging the left of the camera and a mic
    /// hugging the right, plus a one-line transcript below.
    static let listeningExtraWidth: CGFloat = 100
    static let listeningExtraHeight: CGFloat = 26
    /// The compact "working" bar: a touch wider than closed and only tall enough
    /// for two lines of status below the camera ("Searching the web: …").
    static let workingExtraWidth: CGFloat = 160
    static let workingExtraHeight: CGFloat = 32
    /// Extra height for the dictation-review state (transcript + send/cancel).
    static let reviewExtraHeight: CGFloat = 96
    /// Slack around the content so the fixed window can hold the glow bleed + shadow.
    static let shadowPadding: CGFloat = 22
    /// The floating glass tray (composer / Back-to-latest / Stop / Continue)
    /// lives BELOW the black body: this is the gap between the notch's bottom
    /// edge and the tray, and the tray's own height. The window reserves both so
    /// a max-height answer plus the tray still fits inside the fixed panel.
    static let trayGap: CGFloat = 10
    /// Hit-region + reserve height for the tray. Tall enough to hold the
    /// composer grown to its 3-line maximum (it grows downward from the body).
    static let trayHeight: CGFloat = 84
    static let trayReserve: CGFloat = 10 + 84 + 16 // gap + height + breathing room
    /// Corner radii: (top, bottom) for the closed notch and the open panel.
    static let cornerClosed: (top: CGFloat, bottom: CGFloat) = (6, 14)
    static let cornerOpen: (top: CGFloat, bottom: CGFloat) = (20, 26)
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

// MARK: - Text hierarchy

extension Color {
    /// Body text and titles.
    static let jarvisTextPrimary = Color.white.opacity(0.92)
    /// Supporting text: metadata, subtitles, row detail.
    static let jarvisTextSecondary = Color.white.opacity(0.65)
    /// De-emphasized text: timestamps, placeholders, empty states.
    static let jarvisTextTertiary = Color.white.opacity(0.45)
}

/// Corner-radius scale. Three steps: controls (badges, pills, small buttons),
/// cards (rows, surfaces), panels (composer, large containers).
enum JarvisRadius {
    static let control: CGFloat = 8
    static let card: CGFloat = 12
    static let panel: CGFloat = 20
}

// MARK: - Shared components

/// The single empty/placeholder state used by every pane. Optional call to
/// action so "empty" can explain how content appears instead of shrugging.
struct JarvisEmptyState: View {
    let symbol: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Color.jarvisTextTertiary)
            Text(title)
                .font(.jarvisRow)
                .foregroundStyle(Color.jarvisTextSecondary)
            if let message {
                Text(message)
                    .font(.jarvisCaption)
                    .foregroundStyle(Color.jarvisTextTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.jarvisRow)
                    .foregroundStyle(Color.jarvisLink)
                    .padding(.top, 2)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Centered spinner shown while a pane's first fetch is in flight, so panes
/// never flash their empty state before data arrives.
struct JarvisLoadingState: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The single uppercased section header used across Settings and panes.
struct JarvisSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.jarvisCaption.weight(.semibold))
                .foregroundStyle(Color.jarvisTextTertiary)
                .tracking(0.5)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.jarvisCaption)
                    .foregroundStyle(Color.jarvisLink)
            }
        }
    }
}
