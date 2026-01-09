import SwiftUI
import MarkdownUI

/// Message Bubble View Unified for macOS 26
/// Following iMessage design language with Liquid Glass effects
struct MessageBubbleView: View {
    let message: Message
    @ObservedObject var viewModel: ChatViewModel
    @FocusState.Binding var isInputFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    @State private var showBranchConfirm = false
    @State private var isEditing = false
    @State private var editContent = ""
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if message.role == .user { 
                Spacer(minLength: 80) 
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // iMessage-style: Files stacked directly above message content
                if !message.attachedFileNames.isEmpty {
                    VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                        ForEach(Array(message.attachedFileNames.enumerated()), id: \.offset) { index, fileName in
                            FileAttachmentBubble(
                                fileName: fileName,
                                fileId: index < message.attachedFileIds.count ? message.attachedFileIds[index] : nil,
                                isUser: message.role == .user,
                                colorScheme: colorScheme
                            )
                        }
                    }
                }
                
                // Message Bubble with Markdown
                MessageBubbleContent(
                    message: message,
                    colorScheme: colorScheme,
                    isEditing: $isEditing,
                    editContent: $editContent
                )
                
                // Error Recovery
                if message.isError {
                    ErrorRecoveryView(message: message, viewModel: viewModel)
                }
                
                // Actions (Only show for assistant or when not editing)
                if !message.isStreaming && !isEditing {
                    MessageActionsView(
                        message: message,
                        viewModel: viewModel,
                        isInputFocused: $isInputFocused,
                        showBranchConfirm: $showBranchConfirm,
                        isEditing: $isEditing,
                        editContent: $editContent
                    )
                }
                
                // Metadata
                HStack(spacing: 8) {
                    if message.role == .assistant && message.tokenCount > 0 && !message.isStreaming {
                        Text("\(message.tokenCount) tokens")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    
                    if message.role == .assistant && !message.isStreaming {
                        Text(message.createdAt, style: .time)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 4)
                
                // Reasoning
                if message.hasReasoning && message.role == .assistant {
                    ReasoningSection(reasoning: message.reasoning)
                }
            }
            .frame(maxWidth: 700, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .assistant { 
                Spacer(minLength: 80) 
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog("Create Branch?", isPresented: $showBranchConfirm) {
            Button("Branch from here") {
                viewModel.branchFromMessage(message)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will create a new conversation branch from this message.")
        }
    }
}

struct MessageBubbleContent: View {
    let message: Message
    let colorScheme: ColorScheme
    @Binding var isEditing: Bool
    @Binding var editContent: String
    
    @ViewBuilder
    private var content: some View {
        if message.isStreaming && message.content.isEmpty {
            ProgressView()
                .controlSize(.small)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        } else if isEditing && message.role == .user {
            TextEditor(text: $editContent)
                .font(.body)
                .frame(minHeight: 60, maxHeight: 250)
                .padding(12)
                .scrollContentBackground(.hidden)
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
        } else {
            Markdown(message.content)
                .markdownTheme(.basic)
                .markdownBlockStyle(\.codeBlock) { configuration in
                    configuration.label
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.96))
                        )
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(13)
                        }
                }
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
    }
    
    var body: some View {
        content
            .foregroundStyle(message.role == .user ? .white : (colorScheme == .dark ? .white : .primary))
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(bubbleColor)
                    .liquidGlass(opacity: message.role == .assistant ? 0.6 : 1.0, cornerRadius: 22)
            )
            .overlay(
                message.isError ?
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.red.opacity(0.5), lineWidth: 1) : nil
            )
    }
    
    private var bubbleColor: Color {
        if message.isError {
            return colorScheme == .dark ? .red.opacity(0.2) : .red.opacity(0.1)
        } else if message.role == .user {
            return iMessageColors.sent
        } else {
            return iMessageColors.received(for: colorScheme)
        }
    }
}

// MARK: - File Attachment Bubble (iMessage style)
struct FileAttachmentBubble: View {
    let fileName: String
    let fileId: String?
    let isUser: Bool
    let colorScheme: ColorScheme
    @State private var showPreview = false
    
    private var isImage: Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "heic", "webp"].contains(ext)
    }
    
    private var fileIcon: String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "png", "jpg", "jpeg", "gif", "heic", "webp": return "photo.fill"
        case "txt", "md": return "doc.text.fill"
        case "swift", "py", "js", "ts": return "chevron.left.forwardslash.chevron.right"
        default: return "doc.fill"
        }
    }
    
    var body: some View {
        Button(action: { showPreview = true }) {
            HStack(spacing: 8) {
                // File icon with background
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isUser ? .white.opacity(0.2) : .blue.opacity(0.15))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: fileIcon)
                        .font(.system(size: 16))
                        .foregroundStyle(isUser ? .white : .blue)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    
                    Text(isImage ? "Image" : "Document")
                        .font(.system(size: 11))
                        .foregroundStyle(isUser ? .white.opacity(0.7) : .secondary)
                }
                
                Spacer(minLength: 0)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isUser ? .white.opacity(0.5) : .secondary)
            }
            .padding(10)
            .frame(maxWidth: 280)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isUser ? iMessageColors.sent : iMessageColors.received(for: colorScheme))
            )
            .foregroundStyle(isUser ? .white : .primary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPreview) {
            FilePreviewPopover(fileName: fileName, fileId: fileId)
        }
    }
}

struct MessageBubblePreviewContainer: View {
    @StateObject private var viewModel = ChatViewModel()
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            MessageBubbleView(
                message: Message(
                    role: .user,
                    content: "Hello! Can you help me?",
                    attachedFileNames: ["document.pdf", "screenshot.png"]
                ),
                viewModel: viewModel,
                isInputFocused: $isInputFocused
            )
            
            MessageBubbleView(
                message: Message(
                    role: .assistant,
                    content: "Of course! I'm here to help. What would you like to know?",
                    reasoning: ["Analyzing query", "Preparing response"]
                ),
                viewModel: viewModel,
                isInputFocused: $isInputFocused
            )
        }
        .padding()
        .frame(width: 700)
    }
}

#Preview {
    MessageBubblePreviewContainer()
}
