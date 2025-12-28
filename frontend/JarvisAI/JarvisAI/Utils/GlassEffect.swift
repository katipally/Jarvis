import SwiftUI

// MARK: - Glass Effect Modifiers

extension View {
    /// Applies a liquid glass effect with customizable properties
    func liquidGlass(
        blur: CGFloat = 20,
        opacity: Double = 0.7,
        tint: Color = .white.opacity(0.1),
        cornerRadius: CGFloat = 16
    ) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(0.3),
                                        tint.opacity(0.1),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.4),
                                        .white.opacity(0.1),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                    .shadow(color: tint.opacity(0.3), radius: 20, x: 0, y: 10)
            )
            .backdrop(blur: blur)
    }
    
    /// Applies a frosted glass effect with backdrop blur
    func frostedGlass(
        material: Material = .ultraThinMaterial,
        cornerRadius: CGFloat = 12,
        borderWidth: CGFloat = 1,
        borderColor: Color = .white.opacity(0.2)
    ) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(material)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(borderColor, lineWidth: borderWidth)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            )
    }
    
    /// Applies a backdrop blur effect
    func backdrop(blur: CGFloat = 20) -> some View {
        self
            .background(
                Rectangle()
                    .fill(.clear)
                    .background(.ultraThinMaterial)
            )
    }
    
    /// Applies a glass button style
    func glassButton(
        isPressed: Bool = false,
        accentColor: Color = Color(red: 0.2, green: 0.6, blue: 0.6)
    ) -> some View {
        self
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        accentColor.opacity(isPressed ? 0.4 : 0.2),
                                        accentColor.opacity(isPressed ? 0.2 : 0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.4),
                                        .white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: accentColor.opacity(0.3), radius: isPressed ? 4 : 8, x: 0, y: isPressed ? 2 : 4)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
    }
}

// MARK: - Glass Container

struct GlassContainer<Content: View>: View {
    let content: Content
    let style: GlassStyle
    
    enum GlassStyle {
        case thin
        case regular
        case thick
        case ultraThin
        case custom(Material, CGFloat, Color)
        
        var material: Material {
            switch self {
            case .thin: return .thinMaterial
            case .regular: return .regularMaterial
            case .thick: return .thickMaterial
            case .ultraThin: return .ultraThinMaterial
            case .custom(let mat, _, _): return mat
            }
        }
        
        var cornerRadius: CGFloat {
            switch self {
            case .thin, .regular, .thick, .ultraThin: return 16
            case .custom(_, let radius, _): return radius
            }
        }
        
        var tint: Color {
            switch self {
            case .thin, .regular, .thick, .ultraThin: return .white.opacity(0.1)
            case .custom(_, _, let color): return color
            }
        }
    }
    
    init(style: GlassStyle = .ultraThin, @ViewBuilder content: () -> Content) {
        self.style = style
        self.content = content()
    }
    
    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .fill(style.material)
                    .overlay(
                        RoundedRectangle(cornerRadius: style.cornerRadius)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        style.tint.opacity(0.3),
                                        style.tint.opacity(0.1),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: style.cornerRadius)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.4),
                                        .white.opacity(0.1),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
                    .shadow(color: style.tint.opacity(0.2), radius: 20, x: 0, y: 10)
            )
    }
}

// MARK: - Glass Card

struct GlassCard<Content: View>: View {
    let content: Content
    let cornerRadius: CGFloat
    let padding: CGFloat
    let accentColor: Color
    
    init(
        cornerRadius: CGFloat = 16,
        padding: CGFloat = 16,
        accentColor: Color = Color(red: 0.2, green: 0.6, blue: 0.6),
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.accentColor = accentColor
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        accentColor.opacity(0.15),
                                        accentColor.opacity(0.05),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.3),
                                        .white.opacity(0.1),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: .black.opacity(0.25), radius: 15, x: 0, y: 8)
                    .shadow(color: accentColor.opacity(0.2), radius: 25, x: 0, y: 12)
            )
    }
}

// MARK: - Glass Button Style

struct GlassButtonStyle: ButtonStyle {
    let accentColor: Color
    let size: CGFloat
    
    init(accentColor: Color = Color(red: 0.2, green: 0.6, blue: 0.6), size: CGFloat = 36) {
        self.accentColor = accentColor
        self.size = size
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        accentColor.opacity(configuration.isPressed ? 0.4 : 0.2),
                                        accentColor.opacity(configuration.isPressed ? 0.2 : 0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.4),
                                        .white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(
                        color: accentColor.opacity(0.3),
                        radius: configuration.isPressed ? 4 : 8,
                        x: 0,
                        y: configuration.isPressed ? 2 : 4
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Glass Input Field

struct GlassInputField: ViewModifier {
    let isFocused: Bool
    let accentColor: Color
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        accentColor.opacity(isFocused ? 0.2 : 0.1),
                                        accentColor.opacity(isFocused ? 0.1 : 0.05),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isFocused ?
                                    LinearGradient(
                                        colors: [
                                            accentColor.opacity(0.6),
                                            accentColor.opacity(0.3)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ) :
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.2),
                                            .white.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                lineWidth: isFocused ? 2 : 1
                            )
                    )
                    .shadow(
                        color: isFocused ? accentColor.opacity(0.3) : .black.opacity(0.1),
                        radius: isFocused ? 12 : 6,
                        x: 0,
                        y: isFocused ? 6 : 3
                    )
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
    }
}

extension View {
    func glassInputField(isFocused: Bool, accentColor: Color = Color(red: 0.2, green: 0.6, blue: 0.6)) -> some View {
        modifier(GlassInputField(isFocused: isFocused, accentColor: accentColor))
    }
}

