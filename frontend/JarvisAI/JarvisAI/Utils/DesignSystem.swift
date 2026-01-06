import SwiftUI

// MARK: - App Theme
enum AppTheme: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}

/// Liquid Glass Design System for macOS 26
/// Based on Apple's 2026 design language evolution
struct LiquidGlass: ViewModifier {
    var material: Material = .ultraThinMaterial
    var opacity: Double = 0.7
    var cornerRadius: CGFloat = 20
    var shadowRadius: CGFloat = 15
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(material)
                    .opacity(opacity)
                    .shadow(color: Color.black.opacity(0.1), radius: shadowRadius, y: 5)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
            )
    }
}

extension View {
    func liquidGlass(
        material: Material = .ultraThinMaterial,
        opacity: Double = 0.7,
        cornerRadius: CGFloat = 20,
        shadowRadius: CGFloat = 15
    ) -> some View {
        self.modifier(LiquidGlass(
            material: material,
            opacity: opacity,
            cornerRadius: cornerRadius,
            shadowRadius: shadowRadius
        ))
    }
}

/// Native Material Presets for macOS 26
struct MacOS26Materials {
    static var sidebar: some View {
        VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
            .ignoresSafeArea()
    }
    
    static var toolBar: some View {
        VisualEffectView(material: .headerView, blendingMode: .withinWindow)
    }
    
    static var chatBackground: some View {
        VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
            .ignoresSafeArea()
    }
    
    static var focusBackground: some View {
        VisualEffectView(material: .fullScreenUI, blendingMode: .behindWindow)
            .ignoresSafeArea()
    }
    
    static var siriPill: some View {
        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
    }
}

/// AppKit bridging for advanced material effects
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// iMessage style bubble colors for macOS 26
struct iMessageColors {
    static let sent = Color(red: 0.0, green: 0.48, blue: 1.0)
    static let receivedLight = Color(nsColor: NSColor(red: 0.9, green: 0.9, blue: 0.92, alpha: 1.0))
    static let receivedDark = Color(nsColor: NSColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1.0))
    
    static func received(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? receivedDark : receivedLight
    }
}

// MARK: - Siri-Style Focus Mode Design
struct SiriColors {
    static let gradientStart = Color(red: 0.4, green: 0.2, blue: 0.8)
    static let gradientEnd = Color(red: 0.2, green: 0.4, blue: 0.9)
    static let glowPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    static let glowBlue = Color(red: 0.3, green: 0.5, blue: 1.0)
    static let glowPink = Color(red: 1.0, green: 0.4, blue: 0.6)
    
    static var animatedGradient: LinearGradient {
        LinearGradient(
            colors: [glowPurple, glowBlue, glowPink, glowPurple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Animated Siri-style glow ring
struct SiriGlowRing: View {
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1.0
    let isActive: Bool
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            SiriColors.glowPurple,
                            SiriColors.glowBlue,
                            SiriColors.glowPink,
                            SiriColors.glowPurple
                        ],
                        center: .center,
                        startAngle: .degrees(rotation),
                        endAngle: .degrees(rotation + 360)
                    ),
                    lineWidth: 3
                )
                .frame(width: size, height: size)
                .blur(radius: 8)
                .opacity(isActive ? 0.8 : 0.3)
            
            // Inner ring
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            SiriColors.glowPurple.opacity(0.8),
                            SiriColors.glowBlue.opacity(0.8),
                            SiriColors.glowPink.opacity(0.8),
                            SiriColors.glowPurple.opacity(0.8)
                        ],
                        center: .center,
                        startAngle: .degrees(rotation),
                        endAngle: .degrees(rotation + 360)
                    ),
                    lineWidth: 2
                )
                .frame(width: size - 10, height: size - 10)
        }
        .scaleEffect(scale)
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            if isActive {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    scale = 1.05
                }
            }
        }
    }
}

