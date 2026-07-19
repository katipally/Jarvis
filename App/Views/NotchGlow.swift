import SwiftUI

/// Apple-Intelligence-style animated gradient that hugs the notch border and
/// bleeds gently outward from behind it. A blurred stroke — not a big halo — so
/// it never dominates or cuts through content. Respects Reduce Motion.
struct NotchGlow: View {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var intensity: CGFloat = 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            stroke(colors: [.blue, .purple, .pink, .blue], angle: .degrees(180))
                .opacity(0.7 * intensity)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate * 0.25
                let angle = Angle.degrees(sin(phase * 1.2) * 120 + 180)
                let breathe = 0.75 + 0.25 * sin(phase * 1.1)
                stroke(colors: colors(phase: phase), angle: angle)
                    .opacity(breathe * intensity)
            }
        }
    }

    private func colors(phase: Double) -> [Color] {
        (0...6).map { i in
            let base = Double(i) / 6.0
            let hue = (base + sin(phase * 0.9 + base * .pi * 2) * 0.08 + 1).truncatingRemainder(dividingBy: 1)
            let saturation = 0.85 + 0.15 * sin(phase * 0.7 + base * .pi)
            return Color(hue: hue, saturation: saturation, brightness: 1.0)
        }
    }

    private func stroke(colors: [Color], angle: Angle) -> some View {
        NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius)
            .stroke(
                AngularGradient(gradient: Gradient(colors: colors + [colors.first ?? .blue]), center: .center, angle: angle),
                lineWidth: 3
            )
            .blur(radius: 6)
    }
}
