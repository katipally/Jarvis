import SwiftUI

/// One attributed line of live transcript. `isYou` maps mic → "You" and captured
/// system audio → "Them".
struct MeetingLine: Identifiable, Sendable {
    let id: String
    let isYou: Bool
    let text: String
}

/// Compact live-transcript card shown in HomeView while a meeting is being
/// captured: a recording indicator, the app name, a stop button, and the last
/// few attributed lines.
struct MeetingTranscriptCard: View {
    let appName: String
    let lines: [MeetingLine]
    var onStop: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                RecordingDot()
                Text("Transcribing — \(appName)")
                    .font(.jarvisRow)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Spacer()
                Button(action: onStop) {
                    Text("Stop")
                        .font(.jarvisFootnote.weight(.semibold))
                        .foregroundStyle(Color.jarvisError)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.jarvisError.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .accessibilityLabel("Stop transcribing")
            }

            if lines.isEmpty {
                Text("Listening…")
                    .font(.jarvisFootnote)
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(lines.suffix(4)) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Text(line.isYou ? "You" : "Them")
                                .font(.jarvisFootnote.weight(.semibold))
                                .foregroundStyle(line.isYou ? Color.jarvisAccent : Color.jarvisSuccess)
                                .frame(width: 34, alignment: .leading)
                            Text(line.text)
                                .font(.jarvisFootnote)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.jarvisSurface))
    }
}

/// "● Transcribing — <App>" pill for the closed notch (NotchView) — a small,
/// non-interactive indicator that a meeting is being captured.
struct TranscribingPill: View {
    let appName: String

    var body: some View {
        HStack(spacing: 6) {
            RecordingDot()
            Text("Transcribing — \(appName)")
                .font(.jarvisFootnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.jarvisSurfaceHover)
                .strokeBorder(Color.jarvisStroke, lineWidth: 1)
        )
    }
}

/// Pulsing red capture dot, shared by the card and the pill.
private struct RecordingDot: View {
    @State private var on = false

    var body: some View {
        Circle()
            .fill(Color.jarvisError)
            .frame(width: 7, height: 7)
            .opacity(on ? 1 : 0.35)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
