import SwiftUI
import AppKit

// MARK: - macOS 26 Liquid Glass Design System
// Using official Apple APIs from WWDC25 "Build a SwiftUI app with the new design"

// MARK: - App Theme
enum AppTheme: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}

// MARK: - Agent Mode
enum AgentMode: String, CaseIterable, Codable {
    case reasoning = "reasoning"
    case fast = "fast"
    
    var displayName: String {
        switch self {
        case .reasoning: return "Reasoning"
        case .fast: return "Fast"
        }
    }
    
    var icon: String {
        switch self {
        case .reasoning: return "brain"
        case .fast: return "bolt.fill"
        }
    }
    
    var description: String {
        switch self {
        case .reasoning: return "Detailed analysis & planning"
        case .fast: return "Quick, direct responses"
        }
    }
}

// MARK: - Plan Step Status
enum PlanStepStatus: String, Codable {
    case pending = "pending"
    case running = "running"
    case completed = "completed"
    case failed = "failed"
    case skipped = "skipped"
    
    var icon: String {
        switch self {
        case .pending: return "circle"
        case .running: return "circle.dotted"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .skipped: return "minus.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .pending: return JarvisColors.textTertiary
        case .running: return JarvisColors.primary
        case .completed: return JarvisColors.success
        case .failed: return JarvisColors.error
        case .skipped: return JarvisColors.textSecondary
        }
    }
}

// MARK: - Jarvis Color System
struct JarvisColors {
    // Primary Brand Colors
    static let primary = Color(hex: "#6366F1")        // Indigo
    static let primaryLight = Color(hex: "#818CF8")   // Light Indigo
    static let primaryDark = Color(hex: "#4F46E5")    // Dark Indigo
    
    // Accent Colors (Siri-inspired gradient)
    static let accentPurple = Color(hex: "#A855F7")   // Purple
    static let accentBlue = Color(hex: "#3B82F6")     // Blue
    static let accentPink = Color(hex: "#EC4899")     // Pink
    static let accentTeal = Color(hex: "#14B8A6")     // Teal
    
    // Semantic Colors
    static let success = Color(hex: "#22C55E")        // Green
    static let warning = Color(hex: "#F59E0B")        // Amber
    static let error = Color(hex: "#EF4444")          // Red
    static let info = Color(hex: "#3B82F6")           // Blue
    
    // Surface Colors (Dark Theme)
    static let backgroundPrimary = Color(hex: "#0A0A0F")
    static let backgroundSecondary = Color(hex: "#111118")
    static let surfaceElevated = Color(hex: "#1A1A24")
    static let surfaceOverlay = Color.white.opacity(0.05)
    
    // Surface Colors (Light Theme)
    static let backgroundPrimaryLight = Color(hex: "#FAFAFA")
    static let backgroundSecondaryLight = Color(hex: "#F5F5F5")
    
    // Text Colors
    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.70)
    static let textTertiary = Color.white.opacity(0.50)
    static let textDisabled = Color.white.opacity(0.30)
    
    // Glass Effects
    static let glassStroke = Color.white.opacity(0.15)
    static let glassHighlight = Color.white.opacity(0.20)
    static let glassShadow = Color.black.opacity(0.25)
    
    // Message Bubbles
    static let userBubble = Color(hex: "#6366F1")
    static let assistantBubble = Color(hex: "#1E1E2E")
    static let systemBubble = Color(hex: "#14B8A6").opacity(0.15)
    
    // Mode Indicators
    static let reasoningMode = Color(hex: "#A855F7")  // Purple for "thinking"
    static let fastMode = Color(hex: "#22C55E")       // Green for "quick"
    static let voiceActive = Color(hex: "#EC4899")    // Pink for "listening"
    
    // Gradients
    static var siriGradient: LinearGradient {
        LinearGradient(
            colors: [accentPurple, accentBlue, accentPink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static var planStepGradient: LinearGradient {
        LinearGradient(
            colors: [primary, accentTeal],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    static var reasoningGradient: LinearGradient {
        LinearGradient(
            colors: [accentPurple.opacity(0.8), accentBlue.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Hex Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Jarvis Typography
struct JarvisTypography {
    // Display (Hero text)
    static let displayLarge = Font.system(size: 34, weight: .bold, design: .rounded)
    static let displayMedium = Font.system(size: 28, weight: .bold, design: .rounded)
    static let displaySmall = Font.system(size: 24, weight: .semibold, design: .rounded)
    
    // Headlines
    static let headlineLarge = Font.system(size: 20, weight: .semibold)
    static let headlineMedium = Font.system(size: 17, weight: .semibold)
    static let headlineSmall = Font.system(size: 15, weight: .semibold)
    
    // Body
    static let bodyLarge = Font.system(size: 17, weight: .regular)
    static let bodyMedium = Font.system(size: 15, weight: .regular)
    static let bodySmall = Font.system(size: 13, weight: .regular)
    
    // Labels
    static let labelLarge = Font.system(size: 14, weight: .medium)
    static let labelMedium = Font.system(size: 12, weight: .medium)
    static let labelSmall = Font.system(size: 11, weight: .medium)
    
    // Code/Mono
    static let codeLarge = Font.system(size: 14, weight: .regular, design: .monospaced)
    static let codeMedium = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let codeSmall = Font.system(size: 12, weight: .regular, design: .monospaced)
}

// MARK: - Jarvis Animation System
struct JarvisAnimations {
    // Standard Durations
    static let instant: Double = 0.1
    static let fast: Double = 0.2
    static let normal: Double = 0.35
    static let slow: Double = 0.5
    
    // Spring Presets
    static let bouncy = Animation.spring(response: 0.4, dampingFraction: 0.7)
    static let smooth = Animation.spring(response: 0.5, dampingFraction: 0.85)
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.8)
    
    // Glass Morphing
    static let glassMorph = Animation.spring(response: 0.4, dampingFraction: 0.75)
    
    // Plan Step Transitions
    static let stepReveal = Animation.easeOut(duration: 0.3)
    static let stepComplete = Animation.spring(response: 0.3, dampingFraction: 0.6)
    
    // Message Animations
    static let messageAppear = Animation.spring(response: 0.35, dampingFraction: 0.8)
    static let streamingPulse = Animation.easeInOut(duration: 0.5).repeatForever()
    
    // Siri Blob
    static let blobIdle = Animation.easeInOut(duration: 2).repeatForever()
    static let blobListening = Animation.easeInOut(duration: 0.3)
    static let blobGradientRotation = Animation.linear(duration: 3).repeatForever(autoreverses: false)
    
    // Micro-interactions
    static let buttonPress = Animation.spring(response: 0.15, dampingFraction: 0.5)
    static let hoverScale = Animation.easeOut(duration: 0.15)
}

// MARK: - Liquid Glass Design System (macOS 26 / iOS 26)
// Official Apple Liquid Glass APIs from WWDC25

/// Liquid Glass modifier using official macOS 26 glassEffect when available
struct LiquidGlass: ViewModifier {
    var material: Material = .ultraThinMaterial
    var opacity: Double = 0.7
    var cornerRadius: CGFloat = 20
    var shadowRadius: CGFloat = 15
    var isInteractive: Bool = false
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // Use official macOS 26 glassEffect API
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            // Fallback for older systems
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(material)
                        .opacity(opacity)
                        .shadow(color: JarvisColors.glassShadow, radius: shadowRadius, y: 5)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [JarvisColors.glassHighlight, JarvisColors.glassStroke],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.5
                                )
                        )
                )
        }
    }
}

extension View {
    /// Apply Liquid Glass effect - uses official macOS 26 glassEffect on supported systems
    func liquidGlass(
        material: Material = .ultraThinMaterial,
        opacity: Double = 0.7,
        cornerRadius: CGFloat = 20,
        shadowRadius: CGFloat = 15,
        isInteractive: Bool = false
    ) -> some View {
        self.modifier(LiquidGlass(
            material: material,
            opacity: opacity,
            cornerRadius: cornerRadius,
            shadowRadius: shadowRadius,
            isInteractive: isInteractive
        ))
    }
    
    /// Glass card style with larger corner radius
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        self.liquidGlass(cornerRadius: cornerRadius, shadowRadius: 10)
    }
    
    /// Glass button style with smaller corner radius
    func glassButton() -> some View {
        self.liquidGlass(cornerRadius: 12, shadowRadius: 5, isInteractive: true)
    }
    
    /// Official macOS 26 glass effect with capsule shape
    @available(macOS 26.0, *)
    func glassCapsule() -> some View {
        self.glassEffect(.regular, in: Capsule())
    }
    
    /// Official macOS 26 glass effect for controls
    @available(macOS 26.0, *)
    func glassControl() -> some View {
        self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Native Material Presets
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

// MARK: - AppKit Bridging
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

// MARK: - iMessage Style Bubble Colors (Legacy Support)
struct iMessageColors {
    static let sent = JarvisColors.userBubble
    static let receivedLight = Color(nsColor: NSColor(red: 0.9, green: 0.9, blue: 0.92, alpha: 1.0))
    static let receivedDark = JarvisColors.assistantBubble
    
    static func received(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? receivedDark : receivedLight
    }
}

// MARK: - Siri Colors (Legacy Support)
struct SiriColors {
    static let gradientStart = JarvisColors.accentPurple
    static let gradientEnd = JarvisColors.accentBlue
    static let glowPurple = JarvisColors.accentPurple
    static let glowBlue = JarvisColors.accentBlue
    static let glowPink = JarvisColors.accentPink
    
    static var animatedGradient: LinearGradient {
        JarvisColors.siriGradient
    }
}

// MARK: - Siri Glow Ring
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
                            JarvisColors.accentPurple,
                            JarvisColors.accentBlue,
                            JarvisColors.accentPink,
                            JarvisColors.accentPurple
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
                            JarvisColors.accentPurple.opacity(0.8),
                            JarvisColors.accentBlue.opacity(0.8),
                            JarvisColors.accentPink.opacity(0.8),
                            JarvisColors.accentPurple.opacity(0.8)
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
            withAnimation(JarvisAnimations.blobGradientRotation) {
                rotation = 360
            }
            if isActive {
                withAnimation(JarvisAnimations.blobIdle) {
                    scale = 1.05
                }
            }
        }
    }
}

// MARK: - Mode Selector View
struct ModeSelectorView: View {
    @Binding var selectedMode: AgentMode
    var compact: Bool = false
    
    var body: some View {
        HStack(spacing: compact ? 4 : 8) {
            ForEach(AgentMode.allCases, id: \.self) { mode in
                Button(action: {
                    withAnimation(JarvisAnimations.snappy) {
                        selectedMode = mode
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.system(size: compact ? 10 : 12, weight: .semibold))
                        
                        if !compact {
                            Text(mode.displayName)
                                .font(JarvisTypography.labelSmall)
                        }
                    }
                    .foregroundColor(selectedMode == mode ? .white : JarvisColors.textSecondary)
                    .padding(.horizontal, compact ? 8 : 12)
                    .padding(.vertical, compact ? 4 : 6)
                    .background(
                        Capsule()
                            .fill(selectedMode == mode ?
                                  (mode == .reasoning ? JarvisColors.reasoningMode : JarvisColors.fastMode) :
                                    Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(JarvisColors.surfaceElevated)
                .overlay(
                    Capsule()
                        .stroke(JarvisColors.glassStroke, lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Plan Step View
struct PlanStepView: View {
    let step: PlanStep
    let index: Int
    let isLast: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Status indicator with line
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(step.status.color.opacity(0.2))
                        .frame(width: 28, height: 28)
                    
                    if step.status == .running {
                        Circle()
                            .stroke(step.status.color, lineWidth: 2)
                            .frame(width: 28, height: 28)
                            .rotationEffect(.degrees(-90))
                            .animation(JarvisAnimations.streamingPulse, value: step.status)
                    }
                    
                    Image(systemName: step.status.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(step.status.color)
                }
                
                if !isLast {
                    Rectangle()
                        .fill(step.status == .completed ? JarvisColors.success.opacity(0.5) : JarvisColors.glassStroke)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            
            // Step content
            VStack(alignment: .leading, spacing: 4) {
                Text(step.description)
                    .font(JarvisTypography.bodyMedium)
                    .foregroundColor(JarvisColors.textPrimary)
                
                if let toolName = step.toolName {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.fill")
                            .font(.system(size: 10))
                        Text(toolName)
                            .font(JarvisTypography.codeSmall)
                    }
                    .foregroundColor(JarvisColors.textTertiary)
                }
                
                if let result = step.result, !result.isEmpty {
                    Text(result)
                        .font(JarvisTypography.bodySmall)
                        .foregroundColor(JarvisColors.textSecondary)
                        .lineLimit(2)
                }
                
                if let error = step.error {
                    Text(error)
                        .font(JarvisTypography.bodySmall)
                        .foregroundColor(JarvisColors.error)
                        .lineLimit(2)
                }
            }
            .padding(.bottom, isLast ? 0 : 16)
            
            Spacer()
        }
    }
}

// MARK: - Plan Step Model
struct PlanStep: Identifiable, Codable {
    let id: String
    let description: String
    var status: PlanStepStatus
    var toolName: String?
    var toolArgs: [String: String]?
    var result: String?
    var error: String?
    
    init(id: String, description: String, status: PlanStepStatus = .pending, toolName: String? = nil, result: String? = nil, error: String? = nil) {
        self.id = id
        self.description = description
        self.status = status
        self.toolName = toolName
        self.result = result
        self.error = error
    }
}

// MARK: - Plan Stepper View (Live Progress Display)
struct PlanStepperView: View {
    let steps: [PlanStep]
    let summary: String
    @State private var isExpanded: Bool = true
    @State private var pulseAnimation: Bool = false
    
    var completedCount: Int {
        steps.filter { $0.status == .completed }.count
    }
    
    var runningCount: Int {
        steps.filter { $0.status == .running }.count
    }
    
    var isExecuting: Bool {
        runningCount > 0 || (completedCount < steps.count && completedCount > 0)
    }
    
    var currentStepIndex: Int {
        steps.firstIndex(where: { $0.status == .running }) ?? 
        steps.firstIndex(where: { $0.status == .pending }) ?? 
        steps.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with live status
            HStack(spacing: 10) {
                // Animated icon
                ZStack {
                    Circle()
                        .fill(isExecuting ? JarvisColors.primary.opacity(0.2) : JarvisColors.success.opacity(0.2))
                        .frame(width: 32, height: 32)
                    
                    if isExecuting {
                        Circle()
                            .stroke(JarvisColors.primary.opacity(0.5), lineWidth: 2)
                            .frame(width: 32, height: 32)
                            .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                            .opacity(pulseAnimation ? 0 : 1)
                    }
                    
                    Image(systemName: isExecuting ? "gearshape.2.fill" : "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isExecuting ? JarvisColors.primary : JarvisColors.success)
                        .rotationEffect(.degrees(isExecuting && pulseAnimation ? 30 : 0))
                }
                .onAppear {
                    if isExecuting {
                        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                            pulseAnimation = true
                        }
                    }
                }
                .onChange(of: isExecuting) { executing in
                    if executing {
                        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                            pulseAnimation = true
                        }
                    } else {
                        pulseAnimation = false
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.isEmpty ? "Execution Plan" : summary)
                        .font(JarvisTypography.labelLarge)
                        .foregroundColor(JarvisColors.textPrimary)
                        .lineLimit(1)
                    
                    // Status text
                    if isExecuting {
                        Text("Step \(currentStepIndex + 1) of \(steps.count) • Running...")
                            .font(JarvisTypography.labelSmall)
                            .foregroundColor(JarvisColors.primary)
                    } else if completedCount == steps.count {
                        Text("All \(steps.count) steps completed")
                            .font(JarvisTypography.labelSmall)
                            .foregroundColor(JarvisColors.success)
                    }
                }
                
                Spacer()
                
                // Progress badge
                HStack(spacing: 6) {
                    if isExecuting {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    }
                    
                    Text("\(completedCount)/\(steps.count)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(completedCount == steps.count ? JarvisColors.success.opacity(0.2) : JarvisColors.primary.opacity(0.2))
                        )
                        .foregroundColor(completedCount == steps.count ? JarvisColors.success : JarvisColors.primary)
                }
                
                // Expand/collapse button
                Button(action: {
                    withAnimation(JarvisAnimations.smooth) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(JarvisColors.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(JarvisColors.surfaceOverlay, in: Circle())
                }
                .buttonStyle(.plain)
            }
            
            // Animated progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(JarvisColors.surfaceElevated)
                        .frame(height: 6)
                    
                    // Progress fill with gradient
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [JarvisColors.primary, JarvisColors.accentTeal],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geo.size.width * CGFloat(completedCount) / CGFloat(max(steps.count, 1))), height: 6)
                    
                    // Running indicator (animated position)
                    if isExecuting && currentStepIndex < steps.count {
                        Circle()
                            .fill(JarvisColors.primary)
                            .frame(width: 10, height: 10)
                            .shadow(color: JarvisColors.primary.opacity(0.5), radius: 4)
                            .offset(x: geo.size.width * CGFloat(currentStepIndex) / CGFloat(max(steps.count, 1)) - 5)
                            .animation(.spring(response: 0.4), value: currentStepIndex)
                    }
                }
            }
            .frame(height: 6)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: completedCount)
            
            // Steps list - always show during execution
            if isExpanded && !steps.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(steps) { step in
                        LivePlanStepView(
                            step: step,
                            index: steps.firstIndex(where: { $0.id == step.id }) ?? 0,
                            isLast: step.id == steps.last?.id,
                            isActive: step.status == .running
                        )
                    }
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(JarvisColors.surfaceElevated.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            isExecuting ? JarvisColors.primary.opacity(0.3) : JarvisColors.glassStroke,
                            lineWidth: isExecuting ? 1.5 : 0.5
                        )
                )
                .shadow(color: isExecuting ? JarvisColors.primary.opacity(0.1) : .clear, radius: 8, y: 4)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: steps.count)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: completedCount)
        .animation(.easeInOut(duration: 0.3), value: isExecuting)
    }
}

// MARK: - Live Plan Step View (Enhanced for real-time updates)
struct LivePlanStepView: View {
    let step: PlanStep
    let index: Int
    let isLast: Bool
    let isActive: Bool
    @State private var shimmer: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Status indicator with animated line
            VStack(spacing: 0) {
                ZStack {
                    // Background circle
                    Circle()
                        .fill(step.status.color.opacity(0.15))
                        .frame(width: 28, height: 28)
                    
                    // Active pulse ring
                    if isActive {
                        Circle()
                            .stroke(step.status.color.opacity(0.5), lineWidth: 2)
                            .frame(width: 28, height: 28)
                            .scaleEffect(shimmer ? 1.4 : 1.0)
                            .opacity(shimmer ? 0 : 0.8)
                        
                        // Spinning indicator for running
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(step.status.color, lineWidth: 2)
                            .frame(width: 28, height: 28)
                            .rotationEffect(.degrees(shimmer ? 360 : 0))
                    }
                    
                    // Status icon
                    Image(systemName: step.status.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(step.status.color)
                }
                .onAppear {
                    if isActive {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            shimmer = true
                        }
                    }
                }
                .onChange(of: isActive) { active in
                    if active {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            shimmer = true
                        }
                    } else {
                        shimmer = false
                    }
                }
                
                // Connecting line
                if !isLast {
                    Rectangle()
                        .fill(
                            step.status == .completed ? 
                                JarvisColors.success.opacity(0.5) : 
                                (isActive ? JarvisColors.primary.opacity(0.3) : JarvisColors.glassStroke)
                        )
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            
            // Step content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(step.description)
                        .font(JarvisTypography.bodyMedium)
                        .foregroundColor(
                            step.status == .completed ? JarvisColors.textSecondary :
                            (isActive ? JarvisColors.textPrimary : JarvisColors.textSecondary)
                        )
                    
                    if isActive {
                        Text("Running")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(JarvisColors.primary.opacity(0.2), in: Capsule())
                            .foregroundColor(JarvisColors.primary)
                    }
                }
                
                if let toolName = step.toolName {
                    HStack(spacing: 4) {
                        Image(systemName: isActive ? "gear" : "wrench.fill")
                            .font(.system(size: 10))
                        Text(toolName)
                            .font(JarvisTypography.codeSmall)
                    }
                    .foregroundColor(isActive ? JarvisColors.primary : JarvisColors.textTertiary)
                }
                
                if let result = step.result, !result.isEmpty {
                    Text(result)
                        .font(JarvisTypography.bodySmall)
                        .foregroundColor(JarvisColors.textSecondary)
                        .lineLimit(2)
                }
                
                if let error = step.error {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text(error)
                            .font(JarvisTypography.bodySmall)
                    }
                    .foregroundColor(JarvisColors.error)
                    .lineLimit(2)
                }
            }
            .padding(.bottom, isLast ? 0 : 16)
            
            Spacer()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: step.status)
    }
}

// MARK: - Glass Button Style (macOS 26 Compatible)
/// Button style that uses official macOS 26 glass styles when available
struct GlassButtonStyle: ButtonStyle {
    var isProminent: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26.0, *) {
            // Use official macOS 26 glass button styling
            configuration.label
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: Capsule())
                .tint(isProminent ? JarvisColors.primary : nil)
                .foregroundStyle(isProminent ? Color.white : Color.primary)
                .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
                .animation(JarvisAnimations.buttonPress, value: configuration.isPressed)
        } else {
            // Fallback for older systems
            configuration.label
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isProminent ? JarvisColors.primary : JarvisColors.surfaceElevated)
                        .overlay(
                            Capsule()
                                .stroke(JarvisColors.glassStroke, lineWidth: 0.5)
                        )
                )
                .foregroundColor(isProminent ? .white : JarvisColors.textPrimary)
                .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
                .animation(JarvisAnimations.buttonPress, value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    /// Standard glass button style
    static var glass: GlassButtonStyle { GlassButtonStyle() }
    /// Prominent glass button style (for primary actions)
    static var glassProminent: GlassButtonStyle { GlassButtonStyle(isProminent: true) }
}

// MARK: - Additional macOS 26 Liquid Glass Components
@available(macOS 26.0, *)
struct LiquidGlassContainer<Content: View>: View {
    let content: Content
    @Namespace private var glassNamespace
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        GlassEffectContainer {
            content
        }
    }
}

// MARK: - Planning Indicator View (Shows while creating plan)
struct PlanningIndicatorView: View {
    @State private var dotAnimation: Bool = false
    @State private var shimmer: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Animated planning icon
            ZStack {
                Circle()
                    .fill(JarvisColors.primary.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Circle()
                    .stroke(JarvisColors.primary.opacity(0.3), lineWidth: 2)
                    .frame(width: 36, height: 36)
                    .scaleEffect(shimmer ? 1.3 : 1.0)
                    .opacity(shimmer ? 0 : 0.8)
                
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(JarvisColors.primary)
                    .rotationEffect(.degrees(shimmer ? 10 : -10))
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    shimmer = true
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Creating Plan")
                        .font(JarvisTypography.labelLarge)
                        .foregroundColor(JarvisColors.textPrimary)
                    
                    // Animated dots
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(JarvisColors.primary)
                                .frame(width: 4, height: 4)
                                .opacity(dotAnimation ? 1.0 : 0.3)
                                .animation(
                                    .easeInOut(duration: 0.5)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.15),
                                    value: dotAnimation
                                )
                        }
                    }
                    .onAppear { dotAnimation = true }
                }
                
                Text("Analyzing request and preparing steps...")
                    .font(JarvisTypography.bodySmall)
                    .foregroundColor(JarvisColors.textSecondary)
            }
            
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(JarvisColors.surfaceElevated.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(JarvisColors.primary.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
