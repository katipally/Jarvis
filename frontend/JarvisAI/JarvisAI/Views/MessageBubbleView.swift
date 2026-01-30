import SwiftUI
import MarkdownUI

/// Message Bubble View Unified for macOS 26
/// Following iMessage design language with Liquid Glass effects
/// Now with Plan Stepper and Mode indicator support
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
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // Intent & Mode indicator (for assistant messages)
                if message.role == .assistant && (message.intent != nil || message.mode != nil) {
                    HStack(spacing: 8) {
                        if let mode = message.mode {
                            ModeIndicatorBadge(mode: mode)
                        }
                        
                        if let intent = message.intent {
                            IntentBadge(intent: intent, confidence: message.intentConfidence)
                        }
                    }
                }
                
                // Plan Stepper - show immediately when plan exists, or show "Planning" indicator during streaming
                if message.role == .assistant {
                    if message.hasPlan, let plan = message.plan, !plan.isEmpty {
                        // Show plan stepper with live updates
                        PlanStepperView(
                            steps: plan,
                            summary: message.planSummary ?? ""
                        )
                        .frame(maxWidth: 600)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                            removal: .opacity
                        ))
                        .id("plan-\(message.id)-\(plan.count)-\(plan.map { $0.status.rawValue }.joined())") // Include statuses for live updates
                    } else if message.isStreaming && message.content.isEmpty && (viewModel.detectedIntent == "action" || viewModel.detectedIntent == "mixed") {
                        // Show "Creating Plan" indicator while waiting for plan
                        PlanningIndicatorView()
                            .frame(maxWidth: 600)
                            .transition(.opacity)
                    }
                }
                
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
                            .font(JarvisTypography.codeSmall)
                            .foregroundStyle(JarvisColors.textTertiary)
                    }
                    
                    if message.role == .assistant && !message.isStreaming {
                        Text(message.createdAt, style: .time)
                            .font(JarvisTypography.labelSmall)
                            .foregroundStyle(JarvisColors.textTertiary)
                    }
                }
                .padding(.horizontal, 4)
                
                // Reasoning Dropdown (using new component)
                if message.hasReasoning && message.role == .assistant {
                    ReasoningDropdownView(reasoning: message.reasoning)
                        .padding(.top, 4)
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

// MARK: - Mode Indicator Badge
struct ModeIndicatorBadge: View {
    let mode: AgentMode
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: mode.icon)
                .font(.system(size: 10, weight: .semibold))
            
            Text(mode.displayName)
                .font(JarvisTypography.labelSmall)
        }
        .foregroundColor(mode == .reasoning ? JarvisColors.reasoningMode : JarvisColors.fastMode)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill((mode == .reasoning ? JarvisColors.reasoningMode : JarvisColors.fastMode).opacity(0.15))
        )
    }
}

// MARK: - Intent Badge
struct IntentBadge: View {
    let intent: String
    let confidence: Double?
    
    private var icon: String {
        switch intent.lowercased() {
        case "question": return "questionmark.circle"
        case "action": return "gearshape"
        case "mixed": return "arrow.triangle.branch"
        default: return "circle"
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            
            Text(intent.capitalized)
                .font(JarvisTypography.labelSmall)
            
            if let conf = confidence, conf > 0 {
                Text(String(format: "%.0f%%", conf * 100))
                    .font(JarvisTypography.labelSmall)
                    .foregroundColor(JarvisColors.textTertiary)
            }
        }
        .foregroundColor(JarvisColors.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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

// MARK: - Message Bubble Content
struct MessageBubbleContent: View {
    let message: Message
    let colorScheme: ColorScheme
    @Binding var isEditing: Bool
    @Binding var editContent: String
    
    @ViewBuilder
    private var content: some View {
        if message.isStreaming && message.content.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                
                Text("Thinking...")
                    .font(JarvisTypography.bodySmall)
                    .foregroundColor(JarvisColors.textSecondary)
            }
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
                                .fill(colorScheme == .dark ? JarvisColors.surfaceElevated : Color(white: 0.96))
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
            .foregroundStyle(message.role == .user ? .white : (colorScheme == .dark ? JarvisColors.textPrimary : .primary))
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(bubbleColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        message.role == .assistant ? JarvisColors.glassStroke : Color.clear,
                        lineWidth: 0.5
                    )
            )
            .overlay(
                message.isError ?
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(JarvisColors.error.opacity(0.5), lineWidth: 1) : nil
            )
    }
    
    private var bubbleColor: Color {
        if message.isError {
            return colorScheme == .dark ? JarvisColors.error.opacity(0.2) : JarvisColors.error.opacity(0.1)
        } else if message.role == .user {
            return JarvisColors.userBubble
        } else {
            return colorScheme == .dark ? JarvisColors.assistantBubble : iMessageColors.receivedLight
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
                        .fill(isUser ? .white.opacity(0.2) : JarvisColors.primary.opacity(0.15))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: fileIcon)
                        .font(.system(size: 16))
                        .foregroundStyle(isUser ? .white : JarvisColors.primary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileName)
                        .font(JarvisTypography.labelMedium)
                        .lineLimit(1)
                    
                    Text(isImage ? "Image" : "Document")
                        .font(JarvisTypography.labelSmall)
                        .foregroundStyle(isUser ? .white.opacity(0.7) : JarvisColors.textSecondary)
                }
                
                Spacer(minLength: 0)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isUser ? .white.opacity(0.5) : JarvisColors.textSecondary)
            }
            .padding(10)
            .frame(maxWidth: 280)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isUser ? JarvisColors.userBubble : (colorScheme == .dark ? JarvisColors.assistantBubble : iMessageColors.receivedLight))
            )
            .foregroundStyle(isUser ? .white : JarvisColors.textPrimary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPreview) {
            FilePreviewPopover(fileName: fileName, fileId: fileId)
        }
    }
}

// MARK: - Reasoning Section (Legacy - for backward compatibility)
struct ReasoningSection: View {
    let reasoning: [String]
    @State private var isExpanded = false
    
    var body: some View {
        ReasoningDropdownView(reasoning: reasoning)
    }
}

// MARK: - Preview
struct MessageBubblePreviewContainer: View {
    @StateObject private var viewModel = ChatViewModel()
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // User message
                MessageBubbleView(
                    message: Message(
                        role: .user,
                        content: "Open Safari and search for AI news",
                        attachedFileNames: ["document.pdf"]
                    ),
                    viewModel: viewModel,
                    isInputFocused: $isInputFocused
                )
                
                // Assistant message with plan
                MessageBubbleView(
                    message: Message(
                        role: .assistant,
                        content: "I'll open Safari and search for AI news for you.",
                        reasoning: ["Detected action intent", "Creating plan for browser automation"],
                        plan: [
                            PlanStep(id: "step_1", description: "Launch Safari browser", status: .completed, toolName: "launch_app"),
                            PlanStep(id: "step_2", description: "Navigate to search engine", status: .completed, toolName: "browser_navigate_to_url"),
                            PlanStep(id: "step_3", description: "Enter search query", status: .running, toolName: "web_page_fill_input"),
                            PlanStep(id: "step_4", description: "Report results", status: .pending)
                        ],
                        planSummary: "Opening Safari and searching for AI news",
                        intent: "action",
                        intentConfidence: 0.95,
                        mode: .reasoning
                    ),
                    viewModel: viewModel,
                    isInputFocused: $isInputFocused
                )
                
                // Simple question response
                MessageBubbleView(
                    message: Message(
                        role: .assistant,
                        content: "The weather in San Francisco is currently 65°F with partly cloudy skies.",
                        intent: "question",
                        intentConfidence: 0.98,
                        mode: .fast
                    ),
                    viewModel: viewModel,
                    isInputFocused: $isInputFocused
                )
            }
            .padding()
        }
        .frame(width: 800, height: 600)
        .background(JarvisColors.backgroundPrimary)
    }
}

#Preview {
    MessageBubblePreviewContainer()
}
