import SwiftUI
import MarkdownUI

/// Focus Panel - Control Center-style menu bar dropdown
/// Clean, focused interface for quick Jarvis interactions
struct FocusPanelView: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    
    init(viewModel: ChatViewModel? = nil) {
        self.viewModel = viewModel ?? SharedChatViewModel.shared.viewModel
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Control Center-style Header
            FocusPanelHeader(viewModel: viewModel)
            
            Divider()
                .opacity(0.3)
            
            // Chat Content
            FocusChatArea(viewModel: viewModel, isInputFocused: $isInputFocused)
            
            // Liquid Glass input pill - edge to edge, no margins
            FocusInputPill(viewModel: viewModel, isInputFocused: $isInputFocused)
        }
        .frame(width: 380, height: 520)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Control Center-style Header
struct FocusPanelHeader: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 8) {
            // Top row - Branding and actions
            HStack(spacing: 10) {
                // Jarvis branding with gradient circle
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.purple, Color.blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 28, height: 28)
                        
                        Text("J")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Jarvis")
                            .font(.system(size: 14, weight: .semibold))
                        
                        if viewModel.isLoading {
                            Text("Thinking...")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Token count
                if viewModel.currentTokenCount > 0 || viewModel.totalTokensUsed > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 9))
                        Text("\(viewModel.currentTokenCount > 0 ? viewModel.currentTokenCount : viewModel.totalTokensUsed)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.1), in: Capsule())
                }
                
                // New Chat button
                Button(action: { viewModel.startNewChat() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("New Chat (⌘N)")
                
                // Expand to main window
                Button(action: openMainWindow) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Expand Window (⇧⌘O)")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)
            
            // Loading progress bar
            if viewModel.isLoading {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 2)
                        
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.purple, .blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * 0.3, height: 2)
                            .offset(x: loadingOffset(width: geometry.size.width))
                            .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: viewModel.isLoading)
                    }
                }
                .frame(height: 2)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }
        }
    }
    
    private func loadingOffset(width: CGFloat) -> CGFloat {
        // This creates an animated loading bar effect
        return viewModel.isLoading ? width * 0.7 : 0
    }
    
    private func openMainWindow() {
        AppDelegate.shared?.openMainWindow()
    }
}

// MARK: - Focus Chat Area
struct FocusChatArea: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState.Binding var isInputFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    
    private var displayMessages: [Message] {
        viewModel.messages.filter { $0.role != .system }
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    if displayMessages.isEmpty && !viewModel.isLoading {
                        FocusEmptyState()
                            .frame(minHeight: 260)
                    } else {
                        ForEach(displayMessages) { message in
                            FocusMessageRow(message: message, viewModel: viewModel)
                                .id(message.id)
                        }
                        
                        // Show loading indicator when waiting for response
                        if viewModel.isLoading && (displayMessages.last?.role == .user || displayMessages.isEmpty) {
                            FocusLoadingIndicator()
                                .id("loading")
                        }
                    }
                    
                    Color.clear.frame(height: 8)
                        .id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
            }
            .scrollIndicators(.hidden)
            .onChange(of: viewModel.messages.count) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.messages.last?.content) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.isLoading) { _ in
                scrollToBottom(proxy)
            }
        }
    }
    
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.2)) {
                if viewModel.isLoading {
                    proxy.scrollTo("loading", anchor: .bottom)
                } else if let lastId = displayMessages.last?.id {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Focus Loading Indicator
struct FocusLoadingIndicator: View {
    @State private var animate = false
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 6, height: 6)
                        .scaleEffect(animate ? 1.0 : 0.5)
                        .animation(
                            .easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(index) * 0.15),
                            value: animate
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.12))
            )
            
            Spacer()
        }
        .onAppear { animate = true }
    }
}

// MARK: - Focus Empty State
struct FocusEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.3), Color.blue.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 6) {
                Text("Focus Mode")
                    .font(.system(size: 16, weight: .semibold))
                
                Text("Quick access to Jarvis")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Focus Message Row
struct FocusMessageRow: View {
    let message: Message
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    @State private var selectedFileForPreview: String?
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 50)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // File Attachments - larger, clickable previews
                if !message.attachedFileNames.isEmpty {
                    VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                        ForEach(Array(message.attachedFileNames.enumerated()), id: \.offset) { index, fileName in
                            FocusFileAttachmentView(
                                fileName: fileName,
                                fileId: index < message.attachedFileIds.count ? message.attachedFileIds[index] : nil,
                                isUser: message.role == .user
                            )
                        }
                    }
                }
                
                // Content
                Group {
                    if message.isStreaming && message.content.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .fill(Color.white.opacity(0.5))
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    } else {
                        Markdown(message.content)
                            .markdownTheme(.focusCompact)
                            .textSelection(.enabled)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                }
                .foregroundStyle(message.role == .user ? .white : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(message.role == .user ? Color.blue : Color.white.opacity(0.12))
                )
                
                // Actions on hover
                if isHovering && !message.isStreaming {
                    HStack(spacing: 6) {
                        Button(action: { copyToClipboard(message.content) }) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        
                        if message.role == .assistant {
                            Button(action: { Task { await viewModel.regenerateMessage(message) } }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isLoading)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .transition(.opacity)
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
            
            if message.role == .assistant {
                Spacer(minLength: 50)
            }
        }
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Focus Input Pill (Liquid Glass style matching Chat window)
struct FocusInputPill: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState.Binding var isInputFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    // Use local state for file picker to avoid conflicts with main chat window
    @State private var showFocusFilePicker = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Attached files preview - above the input
            if !viewModel.attachedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.attachedFiles, id: \.self) { file in
                            HStack(spacing: 4) {
                                Image(systemName: "paperclip")
                                    .font(.system(size: 9))
                                Text(file.lastPathComponent)
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                                    .frame(maxWidth: 80)
                                Button(action: { viewModel.removeFile(file) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.blue.opacity(0.2)))
                            .foregroundStyle(.blue)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Main input - Liquid Glass style, edge-to-edge
            HStack(alignment: .bottom, spacing: 0) {
                // Attach Button - uses local state to avoid conflict with main window
                Button(action: { showFocusFilePicker = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
                .padding(.leading, 12)
                .padding(.bottom, 10)
                .fileImporter(
                    isPresented: $showFocusFilePicker,
                    allowedContentTypes: [.pdf, .plainText, .image, .png, .jpeg],
                    allowsMultipleSelection: true
                ) { result in
                    if case .success(let urls) = result {
                        viewModel.attachFiles(urls)
                    }
                }
                
                // Text Input - explicitly allow typing in panel
                TextField("Ask anything...", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .disabled(viewModel.isSending)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .onSubmit { sendMessage() }
                    .onAppear {
                        // Auto-focus input when view appears
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isInputFocused = true
                        }
                    }
                
                // Send/Stop Button
                if !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.attachedFiles.isEmpty || viewModel.isLoading {
                    Button(action: {
                        if viewModel.isLoading {
                            viewModel.stopGeneration()
                        } else {
                            sendMessage()
                        }
                    }) {
                        Image(systemName: viewModel.isLoading ? "stop.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(viewModel.isLoading ? .red : .blue)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 10)
                    .padding(.bottom, 8)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .background(
                // Liquid Glass effect - shows content behind
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                    .overlay(
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                    )
                    .overlay(
                        Rectangle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
            )
        }
        .animation(.spring(response: 0.3), value: viewModel.inputText.isEmpty)
        .animation(.spring(response: 0.3), value: viewModel.attachedFiles.count)
    }
    
    private func sendMessage() {
        guard viewModel.canSend else { return }
        Task {
            await viewModel.sendMessage()
            isInputFocused = true
        }
    }
}

// MARK: - Focus File Attachment View (Larger, Clickable Preview)
struct FocusFileAttachmentView: View {
    let fileName: String
    let fileId: String?
    let isUser: Bool
    @State private var showPreview = false
    @Environment(\.colorScheme) var colorScheme
    
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
                // File icon
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isUser ? .white.opacity(0.2) : .blue.opacity(0.15))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: fileIcon)
                        .font(.system(size: 14))
                        .foregroundStyle(isUser ? .white : .blue)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    
                    Text(isImage ? "Tap to preview" : "Document")
                        .font(.system(size: 9))
                        .foregroundStyle(isUser ? .white.opacity(0.7) : .secondary)
                }
                
                Spacer(minLength: 0)
                
                Image(systemName: "eye")
                    .font(.system(size: 10))
                    .foregroundStyle(isUser ? .white.opacity(0.5) : .secondary)
            }
            .padding(8)
            .frame(maxWidth: 200)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isUser ? Color.blue.opacity(0.8) : Color.white.opacity(0.12))
            )
            .foregroundStyle(isUser ? .white : .primary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPreview) {
            FocusFilePreviewPopover(fileName: fileName, fileId: fileId)
        }
    }
}

// MARK: - Focus File Preview Popover (Larger Preview)
struct FocusFilePreviewPopover: View {
    let fileName: String
    let fileId: String?
    @Environment(\.colorScheme) var colorScheme
    
    private var isImage: Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "heic", "webp"].contains(ext)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: isImage ? "photo.fill" : "doc.fill")
                    .foregroundStyle(.blue)
                Text(fileName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer()
            }
            .padding(12)
            .background(Color.gray.opacity(0.1))
            
            Divider()
            
            // Preview content
            if isImage, let fileId = fileId {
                // Show image preview from server
                AsyncImage(url: URL(string: "http://127.0.0.1:8000/api/files/\(fileId)/preview")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 350, maxHeight: 400)
                    case .failure:
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 32))
                                .foregroundStyle(.orange)
                            Text("Failed to load preview")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 250, height: 200)
                    case .empty:
                        ProgressView()
                            .frame(width: 250, height: 200)
                    @unknown default:
                        EmptyView()
                    }
                }
                .padding(12)
            } else {
                // Document preview placeholder
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue.opacity(0.6))
                    
                    Text(fileName)
                        .font(.system(size: 14, weight: .medium))
                    
                    Text("Document attached to message")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 250, height: 180)
                .padding(12)
            }
        }
        .frame(minWidth: 280)
        .background(colorScheme == .dark ? Color.black.opacity(0.9) : Color.white)
    }
}

// MARK: - Focus Compact Markdown Theme
extension MarkdownUI.Theme {
    static let focusCompact = Theme()
        .text {
            FontSize(13)
            ForegroundColor(.primary)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(11)
        }
        .codeBlock { configuration in
            configuration.label
                .padding(8)
                .background(Color.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .paragraph { configuration in
            configuration.label
                .lineSpacing(3)
        }
}
