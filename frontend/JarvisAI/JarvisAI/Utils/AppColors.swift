import SwiftUI

struct AppColors {
    // Modern macOS color palette
    static let primary = Color(red: 0.15, green: 0.55, blue: 0.95) // Modern blue
    static let primaryDark = Color(red: 0.1, green: 0.45, blue: 0.85)
    static let accent = Color(red: 0.2, green: 0.6, blue: 0.6) // Teal accent
    static let accentLight = Color(red: 0.3, green: 0.7, blue: 0.7)
    
    // Background colors
    static let background = Color(red: 0.05, green: 0.05, blue: 0.08)
    static let backgroundSecondary = Color(red: 0.08, green: 0.08, blue: 0.12)
    static let surface = Color(red: 0.1, green: 0.1, blue: 0.15)
    
    // Text colors
    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.7)
    static let textTertiary = Color.white.opacity(0.5)
    
    // Glass effects
    static let glassLight = Color.white.opacity(0.1)
    static let glassMedium = Color.white.opacity(0.15)
    static let glassHeavy = Color.white.opacity(0.2)
    
    // Status colors
    static let success = Color(red: 0.2, green: 0.8, blue: 0.4)
    static let warning = Color(red: 1.0, green: 0.7, blue: 0.2)
    static let error = Color(red: 1.0, green: 0.3, blue: 0.3)
    
    // Message bubble colors
    static let userBubble = Color(red: 0.15, green: 0.55, blue: 0.95)
    static let assistantBubble = Color(red: 0.15, green: 0.15, blue: 0.2)
    static let systemBubble = Color(red: 0.2, green: 0.6, blue: 0.6).opacity(0.2)
}

