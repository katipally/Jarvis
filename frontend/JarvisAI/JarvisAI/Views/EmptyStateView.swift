import SwiftUI

struct EmptyStateView: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState.Binding var isInputFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    
    private let suggestedPrompts = [
        ("Explain a concept", "Help me understand quantum computing in simple terms", "lightbulb.fill"),
        ("Write code", "Write a Python function to sort a list efficiently", "chevron.left.forwardslash.chevron.right"),
        ("Analyze data", "What are the key trends in this dataset?", "chart.bar.fill"),
        ("Creative writing", "Write a short story about space exploration", "pencil.and.outline"),
        ("Problem solving", "Help me debug this error in my code", "ant.fill"),
        ("Research", "Summarize the latest developments in AI", "magnifyingglass")
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 40) {
                Spacer(minLength: 60)
                
                // Hero Section
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [.blue.opacity(0.3), .purple.opacity(0.2), .clear],
                                    center: .center,
                                    startRadius: 20,
                                    endRadius: 80
                                )
                            )
                            .frame(width: 160, height: 160)
                            .blur(radius: 20)
                        
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 64, weight: .thin))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(spacing: 8) {
                        Text("Hello, I'm Jarvis")
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                        
                        Text("Your AI assistant powered by advanced intelligence")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Quick Actions Grid
                VStack(alignment: .leading, spacing: 16) {
                    Text("Try asking about...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.tertiary)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        ForEach(suggestedPrompts, id: \.0) { title, prompt, icon in
                            SuggestionCard(
                                title: title,
                                prompt: prompt,
                                icon: icon,
                                colorScheme: colorScheme
                            ) {
                                viewModel.inputText = prompt
                                isInputFocused = true
                            }
                        }
                    }
                }
                .frame(maxWidth: 600)
                
                // Capabilities Section
                VStack(spacing: 16) {
                    Text("Capabilities")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.tertiary)
                    
                    HStack(spacing: 24) {
                        CapabilityBadge(icon: "doc.text.fill", label: "Documents")
                        CapabilityBadge(icon: "photo.fill", label: "Images")
                        CapabilityBadge(icon: "brain", label: "Reasoning")
                        CapabilityBadge(icon: "arrow.triangle.branch", label: "Branching")
                    }
                }
                
                Spacer(minLength: 150)
            }
            .padding(.horizontal, 40)
        }
    }
}

struct SuggestionCard: View {
    let title: String
    let prompt: String
    let icon: String
    let colorScheme: ColorScheme
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(.blue)
                    .frame(width: 32, height: 32)
                    .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    Text(prompt)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .opacity(isHovering ? 1 : 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

struct CapabilityBadge: View {
    let icon: String
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.blue)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(width: 80)
    }
}

