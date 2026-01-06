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
            
            // Same input pill as Chat window
            FocusInputPill(viewModel: viewModel, isInputFocused: $isInputFocused)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .frame(width: 380, height: 520)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.2)
            }
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
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if viewModel.messages.isEmpty {
                        FocusEmptyState()
                            .frame(minHeight: 260)
                    } else {
                        ForEach(viewModel.messages.filter { $0.role != .system }) { message in
                            FocusMessageRow(message: message, viewModel: viewModel)
                                .id(message.id)
                        }
                    }
                    
                    Color.clear.frame(height: 8)
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
        }
    }
    
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if let lastId = viewModel.messages.filter({ $0.role != .system }).last?.id {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
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
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 50)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Attachments
                if !message.attachedFileNames.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(message.attachedFileNames.prefix(2), id: \.self) { name in
                            Label(name, systemImage: "paperclip")
                                .font(.system(size: 9))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.blue.opacity(0.2)))
                                .foregroundStyle(.blue)
                        }
                        if message.attachedFileNames.count > 2 {
                            Text("+\(message.attachedFileNames.count - 2)")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
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

// MARK: - Focus Input Pill (Same style as Chat window)
struct FocusInputPill: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState.Binding var isInputFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 6) {
            // Attached files preview
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
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Main input pill - matching chat window style
            HStack(alignment: .bottom, spacing: 0) {
                // Attach Button
                Button(action: { viewModel.showFilePicker = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
                .padding(.leading, 8)
                .padding(.bottom, 7)
                .fileImporter(
                    isPresented: $viewModel.showFilePicker,
                    allowedContentTypes: [.pdf, .plainText, .image, .png, .jpeg],
                    allowsMultipleSelection: true
                ) { result in
                    if case .success(let urls) = result {
                        viewModel.attachFiles(urls)
                    }
                }
                
                // Text Input
                TextField("Ask anything...", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .disabled(viewModel.isSending)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .onSubmit { sendMessage() }
                
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
                            .font(.system(size: 26))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(viewModel.isLoading ? .red : .blue)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                    .padding(.bottom, 5)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
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
