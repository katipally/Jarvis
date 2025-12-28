import SwiftUI
import MarkdownUI

// MARK: - Message Bubble View (HIG Compliant for macOS 26+)
// Following Apple Human Interface Guidelines

struct MessageBubbleView: View {
    let message: Message
    @State private var showReasoning = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        let isUser = message.role == .user
        
        HStack(alignment: .top, spacing: 12) {
            if isUser { Spacer(minLength: 80) }
            
            if !isUser && message.role == .assistant {
                avatarView(isUser: false)
            }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                // Attachments
                if !message.attachedFileNames.isEmpty {
                    attachmentsView(isUser: isUser)
                }
                
                // Message Bubble
                messageBubble(isUser: isUser)
                
                // Actions
                if !message.isStreaming {
                    actionsRow(isUser: isUser)
                }
                
                // Reasoning
                if message.hasReasoning && !isUser {
                    reasoningSection
                }
            }
            .frame(maxWidth: 600, alignment: isUser ? .trailing : .leading)
            
            if isUser {
                avatarView(isUser: true)
            }
            
            if !isUser { Spacer(minLength: 80) }
        }
    }
    
    // MARK: - Avatar
    private func avatarView(isUser: Bool) -> some View {
        ZStack {
            if isUser {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 32, height: 32)
                
                Image(systemName: "person.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }
    
    // MARK: - Message Bubble
    @ViewBuilder
    private func messageBubble(isUser: Bool) -> some View {
        Group {
            if message.isStreaming && message.content.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                Markdown(message.content)
                    .textSelection(.enabled)
                    .markdownTextStyle(\.text) {
                        ForegroundColor(isUser ? .white : Color(nsColor: .labelColor))
                        FontSize(15)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isUser ? AnyShapeStyle(userBubbleGradient) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)))
        )
    }
    
    private var userBubbleGradient: LinearGradient {
        LinearGradient(
            colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - Attachments
    private func attachmentsView(isUser: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(message.attachedFileNames, id: \.self) { fileName in
                Label(fileName, systemImage: "paperclip")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isUser ? .white.opacity(0.2) : .blue.opacity(0.1), in: Capsule())
                    .foregroundStyle(isUser ? .white : .blue)
            }
        }
    }
    
    // MARK: - Actions Row
    private func actionsRow(isUser: Bool) -> some View {
        HStack(spacing: 8) {
            Button(action: copyToClipboard) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            
            if isUser {
                Button(action: {}) {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
            } else {
                Button(action: {}) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.small)
        .foregroundStyle(.secondary)
    }
    
    // MARK: - Reasoning Section
    private var reasoningSection: some View {
        DisclosureGroup(isExpanded: $showReasoning) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(message.reasoning.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(.secondary, in: Circle())
                        
                        Text(message.reasoning[index])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Label("Reasoning · \(message.reasoning.count) steps", systemImage: "brain")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .tint(.secondary)
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
    }
}

#Preview {
    VStack(spacing: 16) {
        MessageBubbleView(message: Message(
            role: .user,
            content: "Hello! Can you help me?",
            attachedFileNames: ["document.pdf"]
        ))
        
        MessageBubbleView(message: Message(
            role: .assistant,
            content: "Of course! I'm here to help. What would you like to know?",
            reasoning: ["Analyzing query", "Preparing response"]
        ))
    }
    .padding()
    .frame(width: 700)
}
