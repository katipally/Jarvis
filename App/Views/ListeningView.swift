import SwiftUI

/// The compact listening presentation: a live waveform beside the camera plus
/// the streaming transcript. Shown in place of the closed notch while holding ⌥.
struct ListeningView: View {
    let voice: VoiceController
    let cameraWidth: CGFloat
    let cameraHeight: CGFloat

    var body: some View {
        VStack(spacing: 1) {
            // Top row is exactly the camera height; the waveform + mic flank the
            // reserved camera cutout so nothing renders behind it.
            HStack(spacing: 0) {
                Waveform(level: voice.level, active: voice.phase == .listening)
                    .frame(maxWidth: .infinity)
                    .padding(.trailing, 8)
                    .accessibilityHidden(true)
                Color.clear.frame(width: cameraWidth + 22)
                Group {
                    if voice.phase == .processing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.85))
                            .symbolEffect(.pulse, isActive: voice.phase == .listening)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: cameraHeight)

            // Transcript sits below the camera cutout.
            Text(displayText)
                .font(.jarvisCaption.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
        }
    }

    private var displayText: String {
        let text = voice.transcript.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { return text }
        return voice.phase == .processing ? "Thinking…" : "Listening…"
    }
}

/// A symmetric bar waveform driven by the live audio level. With Reduce Motion
/// on, the bars hold a static mid-height profile instead of animating.
private struct Waveform: View {
    let level: Float
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barCount = 9

    var body: some View {
        if reduceMotion {
            bars { i in staticHeight(index: i) }
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                bars { i in barHeight(index: i, time: t) }
            }
        }
    }

    private func bars(height: @escaping (Int) -> CGFloat) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(0.85))
                    .frame(width: 2.5, height: height(i))
            }
        }
    }

    private func staticHeight(index: Int) -> CGFloat {
        guard active else { return 3 }
        let center = Double(barCount - 1) / 2
        let distance = abs(Double(index) - center) / center
        let falloff = 1.0 - distance * 0.6
        return 3 + CGFloat(falloff) * 6
    }

    private func barHeight(index: Int, time: Double) -> CGFloat {
        guard active else { return 3 }
        let center = Double(barCount - 1) / 2
        let distance = abs(Double(index) - center) / center
        let falloff = 1.0 - distance * 0.6
        let wobble = 0.5 + 0.5 * sin(time * 6 + Double(index) * 0.9)
        let amplitude = CGFloat(level) * falloff * wobble
        return max(3, 3 + amplitude * 12)
    }
}
