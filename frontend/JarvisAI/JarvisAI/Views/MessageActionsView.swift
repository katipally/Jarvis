import SwiftUI

struct MessageActionsView: View {
    let message: Message
    @ObservedObject var viewModel: ChatViewModel
    @FocusState.Binding var isInputFocused: Bool
    @Binding var showBranchConfirm: Bool
    @Binding var isEditing: Bool
    @Binding var editContent: String
    
    var body: some View {
        HStack(spacing: 12) {
            // Copy
            Button(action: { copyContent() }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Copy")
            
            if message.role == .user {
                // Edit
                if isEditing {
                    Button("Cancel") {
                        isEditing = false
                        editContent = ""
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("Save & Resend") {
                        isEditing = false
                        Task { await viewModel.editAndResend(message, newContent: editContent) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button(action: {
                        editContent = message.content
                        isEditing = true
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Edit")
                }
            } else {
                // Assistant actions
                
                // Regenerate
                Button(action: {
                    Task { await viewModel.regenerateMessage(message) }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
                .help("Regenerate")
                
                // Branch
                Button(action: { showBranchConfirm = true }) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Branch Conversation")
                
                // Copy Code
                if message.content.contains("```") {
                    Menu {
                        ForEach(extractCodeBlocks(from: message.content), id: \.self) { code in
                            Button("Copy: \(String(code.prefix(20)))...") {
                                copyToClipboard(code)
                            }
                        }
                    } label: {
                        Image(systemName: "curlybraces")
                            .font(.system(size: 11))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
        .padding(.top, 2)
        .foregroundStyle(.tertiary)
    }
    
    private func copyContent() {
        copyToClipboard(message.content)
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
    private func extractCodeBlocks(from content: String) -> [String] {
        let pattern = "```(?:\\w+)?\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        
        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: range)
        
        return matches.compactMap { match in
            guard let codeRange = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[codeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

struct ErrorRecoveryView: View {
    let message: Message
    @ObservedObject var viewModel: ChatViewModel
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.system(size: 12))
            
            Text("Issue with generation")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            
            Button("Retry") {
                Task { await viewModel.retryFailedMessage(message) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.05))
        .cornerRadius(10)
    }
}

// ReasoningSection has been moved to MessageBubbleView.swift
