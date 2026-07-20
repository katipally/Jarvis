import SwiftUI

/// The compact listening presentation: a live waveform beside the camera plus
/// the streaming transcript. Shown in place of the closed notch while holding ⌥.
struct ListeningView: View {
    let voice: VoiceController
    let cameraWidth: CGFloat
    let cameraHeight: CGFloat
    let morphNamespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 3) {
            // Symmetric reactive bars mirror on both sides of the camera, tight to
            // its edges, pulsing with your voice.
            HStack(spacing: 0) {
                Waveform(level: voice.level, active: voice.phase == .listening)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 7)
                    .accessibilityHidden(true)
                    .morphAnchor(MorphID.leftFlank, in: morphNamespace, active: !reduceMotion)
                Color.clear.frame(width: cameraWidth + NotchMetrics.cameraSideReserve)
                    .morphAnchor(MorphID.camera, in: morphNamespace, active: !reduceMotion)
                Waveform(level: voice.level, active: voice.phase == .listening)
                    .scaleEffect(x: -1, y: 1) // mirror so the tall bars hug the camera
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 7)
                    .accessibilityHidden(true)
                    .morphAnchor(MorphID.rightFlank, in: morphNamespace, active: !reduceMotion)
            }
            .frame(height: cameraHeight)

            if voice.phase == .review {
                // Review before send: the full transcript, scrollable, with an
                // explicit send/cancel pair (⏎ / Esc work globally too).
                VStack(spacing: 8) {
                    ScrollView {
                        Text(voice.transcript.trimmingCharacters(in: .whitespaces))
                            .font(.jarvisCaption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxHeight: 46)
                    .padding(.horizontal, 16)

                    HStack(spacing: 10) {
                        reviewButton("Cancel", symbol: "xmark", prominent: false) { voice.cancel() }
                        reviewButton("Send", symbol: "arrow.up", prominent: true) { voice.confirmSend() }
                    }
                    .padding(.bottom, 8)
                }
            } else {
                // Below the camera: the hold-to-talk mic ring + live transcript.
                HStack(spacing: 7) {
                    HoldMicRing(active: voice.phase == .listening)
                    Text(displayText)
                        .font(.jarvisCaption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
            }
        }
    }

    private var displayText: String {
        let text = voice.transcript.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { return text }
        return voice.phase == .processing ? "Thinking…" : "Listening…"
    }

    private func reviewButton(_ title: String, symbol: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                Text(title).font(.jarvisCaption.weight(.medium))
            }
            .foregroundStyle(prominent ? .black : .white.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(prominent ? .white.opacity(0.92) : .white.opacity(0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .accessibilityLabel(title == "Send" ? "Send dictation" : "Discard dictation")
    }
}

/// A voice-reactive bar cluster that ramps from short (outer edge) to tall
/// (next to the camera), blue-tinted. Mirror it for the opposite flank. Holds a
/// calm static profile under Reduce Motion or when not actively listening.
private struct Waveform: View {
    let level: Float
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barCount = 6

    var body: some View {
        if reduceMotion || !active {
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
                    .fill(Color.jarvisLink.opacity(active ? 0.95 : 0.5))
                    .frame(width: 2.5, height: height(i))
            }
        }
    }

    /// Short at the outer edge → tall next to the camera (trailing bar).
    private func ramp(_ index: Int) -> Double {
        0.35 + 0.65 * (Double(index) / Double(max(1, barCount - 1)))
    }

    private func staticHeight(index: Int) -> CGFloat {
        guard active else { return 3 }
        return 3 + CGFloat(ramp(index)) * 5
    }

    private func barHeight(index: Int, time: Double) -> CGFloat {
        let wobble = 0.5 + 0.5 * sin(time * 6 + Double(index) * 0.9)
        let amplitude = CGFloat(level) * CGFloat(ramp(index)) * wobble
        return max(3, 3 + amplitude * 13)
    }
}

/// Hold-to-talk affordance: a mic with a rotating blue ring that makes 'I'm
/// capturing' obvious while you hold. Calm (no ring) when idle; static ring
/// under Reduce Motion.
private struct HoldMicRing: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if active {
                if reduceMotion {
                    Circle().strokeBorder(Color.jarvisLink.opacity(0.8), lineWidth: 1.5)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        let a = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 1.6) / 1.6
                        Circle()
                            .strokeBorder(
                                AngularGradient(colors: [.clear, Color.jarvisLink, .clear],
                                                center: .center),
                                lineWidth: 1.5
                            )
                            .rotationEffect(.degrees(a * 360))
                    }
                }
            }
            Image(systemName: "mic.fill")
                .font(.system(size: 9))
                .foregroundStyle(active ? Color.jarvisLink : .white.opacity(0.7))
                .symbolEffect(.pulse, isActive: active && !reduceMotion)
        }
        .frame(width: 20, height: 20)
    }
}
