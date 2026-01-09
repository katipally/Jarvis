import SwiftUI

/// Reasoning Dropdown View for displaying AI thinking process
/// Enhanced design with better visual hierarchy and tool information
struct ReasoningDropdownView: View {
    let reasoning: [String]
    @State private var isExpanded = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header button
            Button(action: { withAnimation(.spring(response: 0.3)) { isExpanded.toggle() } }) {
                HStack(spacing: 8) {
                    // Animated thinking icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    Text("Thinking Steps")
                        .font(.system(size: 13, weight: .medium))
                    
                    // Step count badge
                    Text("·")
                        .foregroundStyle(.tertiary)
                    
                    Text("\(reasoning.count)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.purple)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 0 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.purple.opacity(0.15), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)
            
            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(reasoning.indices, id: \.self) { index in
                        ThinkingStepRow(
                            step: index + 1,
                            content: reasoning[index],
                            isLast: index == reasoning.count - 1,
                            colorScheme: colorScheme
                        )
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.purple.opacity(0.06) : Color.purple.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.purple.opacity(0.15), lineWidth: 0.5)
                        )
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
    }
}

// MARK: - Individual Thinking Step Row
struct ThinkingStepRow: View {
    let step: Int
    let content: String
    let isLast: Bool
    let colorScheme: ColorScheme
    
    private var stepIcon: String {
        let lowercased = content.lowercased()
        if lowercased.contains("tool:") || lowercased.contains("using tool") {
            return "wrench.and.screwdriver.fill"
        } else if lowercased.contains("search") || lowercased.contains("looking") {
            return "magnifyingglass"
        } else if lowercased.contains("process") || lowercased.contains("analyzing") {
            return "gearshape.fill"
        } else if lowercased.contains("file") || lowercased.contains("document") {
            return "doc.fill"
        } else if lowercased.contains("result") || lowercased.contains("complete") {
            return "checkmark.circle.fill"
        } else {
            return "sparkle"
        }
    }
    
    private var stepColor: Color {
        let lowercased = content.lowercased()
        if lowercased.contains("tool:") || lowercased.contains("using tool") {
            return .orange
        } else if lowercased.contains("result") || lowercased.contains("complete") {
            return .green
        } else {
            return .purple
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Step indicator with connecting line
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(stepColor.opacity(0.2))
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: stepIcon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(stepColor)
                }
                
                if !isLast {
                    Rectangle()
                        .fill(Color.purple.opacity(0.2))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 28)
            
            // Step content
            VStack(alignment: .leading, spacing: 4) {
                // Step number
                Text("Step \(step)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                
                // Step description
                Text(formatStepContent(content))
                    .font(.system(size: 13))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.85) : .primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 12)
            
            Spacer(minLength: 0)
        }
    }
    
    private func formatStepContent(_ content: String) -> String {
        // Clean up common prefixes for better readability
        var cleaned = content
        let prefixes = ["Using tool: ", "Tool: ", "Processing ", "Analyzing "]
        for prefix in prefixes {
            if cleaned.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
                break
            }
        }
        return cleaned.isEmpty ? content : cleaned
    }
}

#Preview {
    ReasoningDropdownView(reasoning: [
        "Analyzing the user's question about code",
        "Identifying the programming language context",
        "Formulating a comprehensive response",
        "Adding code examples for clarity"
    ])
    .padding()
    .frame(width: 400)
}

