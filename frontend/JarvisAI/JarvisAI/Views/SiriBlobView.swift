import SwiftUI

/// Native macOS-style animated orb that responds to conversation state
/// Uses system colors and subtle animations for a refined look
struct SiriBlobView: View {
    let state: ConversationState
    let audioLevel: Float
    let speakingLevel: Float
    
    @State private var animationPhase: CGFloat = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var glowIntensity: CGFloat = 0.5
    @State private var waveOffset: CGFloat = 0
    
    private let orbSize: CGFloat = 100
    
    var body: some View {
        ZStack {
            // Ambient glow layer
            Circle()
                .fill(ambientGradient)
                .frame(width: orbSize * 1.8, height: orbSize * 1.8)
                .blur(radius: 40)
                .opacity(glowIntensity * 0.6)
            
            // Audio reactive rings (only when active)
            if state == .listening || state == .speaking || state == .interrupted {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(primaryColor.opacity(0.2 - Double(index) * 0.05), lineWidth: 2)
                        .frame(width: orbSize + CGFloat(index) * 30 + waveOffset * CGFloat(index + 1) * 10,
                               height: orbSize + CGFloat(index) * 30 + waveOffset * CGFloat(index + 1) * 10)
                        .opacity(effectiveAudioLevel > 0.1 ? 1 : 0)
                }
            }
            
            // Main orb with glass effect
            ZStack {
                // Base circle with gradient
                Circle()
                    .fill(orbGradient)
                    .frame(width: orbSize, height: orbSize)
                
                // Glass highlight overlay
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.4),
                                .white.opacity(0.1),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: orbSize, height: orbSize)
                
                // Inner shadow for depth
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.2)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 3
                    )
                    .frame(width: orbSize - 3, height: orbSize - 3)
            }
            .scaleEffect(pulseScale)
            .shadow(color: shadowColor, radius: 15, x: 0, y: 8)
            
            // State icon with subtle animation
            stateIcon
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                .scaleEffect(pulseScale * 0.95)
        }
        .onAppear {
            startAnimations()
        }
        .onChange(of: state) { newState in
            withAnimation(.easeInOut(duration: 0.3)) {
                updateAnimations(for: newState)
            }
        }
        .onChange(of: audioLevel) { newLevel in
            withAnimation(.easeOut(duration: 0.1)) {
                waveOffset = CGFloat(newLevel)
            }
        }
    }
    
    // MARK: - State Icon
    @ViewBuilder
    private var stateIcon: some View {
        switch state {
        case .idle:
            Image(systemName: "waveform")
        case .listening, .interrupted:
            Image(systemName: "mic.fill")
        case .processing:
            Image(systemName: "brain")
        case .speaking:
            Image(systemName: "speaker.wave.3.fill")
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        }
    }
    
    // MARK: - Computed Properties
    private var effectiveAudioLevel: Float {
        switch state {
        case .listening, .interrupted:
            return audioLevel
        case .speaking:
            return speakingLevel
        default:
            return 0.1
        }
    }
    
    // MARK: - Colors
    private var primaryColor: Color {
        switch state {
        case .idle: return .blue
        case .listening, .interrupted: return .green
        case .processing: return .orange
        case .speaking: return .purple
        case .error: return .red
        }
    }
    
    private var orbGradient: LinearGradient {
        switch state {
        case .idle:
            return LinearGradient(
                colors: [
                    Color(red: 0.3, green: 0.5, blue: 0.95),
                    Color(red: 0.2, green: 0.35, blue: 0.8)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .listening, .interrupted:
            return LinearGradient(
                colors: [
                    Color(red: 0.2, green: 0.75, blue: 0.5),
                    Color(red: 0.15, green: 0.55, blue: 0.45)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .processing:
            return LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.6, blue: 0.2),
                    Color(red: 0.85, green: 0.4, blue: 0.25)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .speaking:
            return LinearGradient(
                colors: [
                    Color(red: 0.55, green: 0.35, blue: 0.9),
                    Color(red: 0.45, green: 0.25, blue: 0.75)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .error:
            return LinearGradient(
                colors: [
                    Color(red: 0.9, green: 0.35, blue: 0.35),
                    Color(red: 0.7, green: 0.25, blue: 0.25)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    private var ambientGradient: RadialGradient {
        RadialGradient(
            colors: [primaryColor.opacity(0.5), primaryColor.opacity(0)],
            center: .center,
            startRadius: 0,
            endRadius: orbSize
        )
    }
    
    private var shadowColor: Color {
        primaryColor.opacity(0.4)
    }
    
    // MARK: - Animations
    private func startAnimations() {
        updateAnimations(for: state)
    }
    
    private func updateAnimations(for state: ConversationState) {
        // Reset scale first
        pulseScale = 1.0
        
        switch state {
        case .idle:
            glowIntensity = 0.4
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                pulseScale = 1.03
                glowIntensity = 0.6
            }
        case .listening, .interrupted:
            glowIntensity = 0.7
            let scale = 1.0 + CGFloat(audioLevel) * 0.15
            withAnimation(.easeOut(duration: 0.15)) {
                pulseScale = scale
            }
        case .processing:
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                pulseScale = 1.08
                glowIntensity = 0.8
            }
        case .speaking:
            glowIntensity = 0.75
            let scale = 1.0 + CGFloat(speakingLevel) * 0.12
            withAnimation(.easeOut(duration: 0.2)) {
                pulseScale = scale
            }
        case .error:
            glowIntensity = 0.5
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulseScale = 0.97
            }
        }
    }
}

// MARK: - Blob Shape
struct BlobShape: Shape {
    var animationPhase: CGFloat
    var audioLevel: CGFloat
    var complexity: Int
    
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(animationPhase, audioLevel) }
        set {
            animationPhase = newValue.first
            audioLevel = newValue.second
        }
    }
    
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        
        var path = Path()
        let points = complexity * 2
        
        for i in 0..<points {
            let angle = (CGFloat(i) / CGFloat(points)) * 2 * .pi
            let phase = animationPhase * 2 * .pi
            
            // Create organic wobble
            let wobble1 = sin(angle * 3 + phase) * 0.1
            let wobble2 = cos(angle * 2 + phase * 1.5) * 0.08
            let audioWobble = sin(angle * CGFloat(complexity) + phase * 2) * audioLevel * 0.15
            
            let r = radius * (1 + wobble1 + wobble2 + audioWobble)
            
            let x = center.x + cos(angle) * r
            let y = center.y + sin(angle) * r
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                // Use quadratic curves for smoother blob
                let prevAngle = (CGFloat(i - 1) / CGFloat(points)) * 2 * .pi
                let midAngle = (angle + prevAngle) / 2
                
                let controlR = radius * (1 + sin(midAngle * 4 + phase) * 0.12)
                let controlX = center.x + cos(midAngle) * controlR
                let controlY = center.y + sin(midAngle) * controlR
                
                path.addQuadCurve(to: CGPoint(x: x, y: y),
                                  control: CGPoint(x: controlX, y: controlY))
            }
        }
        
        path.closeSubpath()
        return path
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 40) {
        SiriBlobView(state: .idle, audioLevel: 0.1, speakingLevel: 0)
        SiriBlobView(state: .listening, audioLevel: 0.5, speakingLevel: 0)
        SiriBlobView(state: .processing, audioLevel: 0, speakingLevel: 0)
        SiriBlobView(state: .speaking, audioLevel: 0, speakingLevel: 0.6)
    }
    .padding()
    .background(Color.black)
}
