import SwiftUI
import MarkdownUI

/// Focus Panel - Menu bar popover like Control Center
/// Provides quick access to Jarvis in a compact, focused interface
struct FocusPanelView: View {
    @StateObject private var viewModel = ChatViewModel()
    @EnvironmentObject var appState: AppState
    @FocusState private var isInputFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            FocusPanelHeader(viewModel: viewModel, appState: appState)
            
            Divider()
                .padding(.horizontal, 16)
            
            // Messages
            FocusPanelMessages(viewModel: viewModel, isInputFocused: $isInputFocused)
            
            // Input
            FocusPanelInput(viewModel: viewModel, isInputFocused: $isInputFocused)
        }
        .frame(width: 420, height: 580)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        )
    }
}

// MARK: - Focus Panel Header
struct FocusPanelHeader: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            // Jarvis Icon with status
            ZStack {
                if viewModel.isLoading {
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [.purple, .blue, .pink, .purple],
                                center: .center
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
                        .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: viewModel.isLoading)
                }
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 24, height: 24)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Jarvis")
                    .font(.system(size: 14, weight: .semibold))
                
                Text(viewModel.isLoading ? "Thinking..." : "Focus Mode")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Token count
            if viewModel.totalTokensUsed > 0 {
                Text("\(viewModel.totalTokensUsed)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            
            // New chat
            Button(action: { viewModel.startNewChat() }) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("New Chat")
            
            // Open main window
            Button(action: {
                appState.currentMode = .chat
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.title.contains("Jarvis") || $0.isMainWindow }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open Full Window")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Focus Panel Messages
struct FocusPanelMessages: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState.Binding var isInputFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.messages.isEmpty {
                        FocusPanelEmptyState()
                            .frame(minHeight: 300)
                    } else {
                        ForEach(viewModel.messages.filter { $0.role != .system }) { message in
                            FocusPanelMessageBubble(
                                message: message,
                                viewModel: viewModel
                            )
                            .id(message.id)
                        }
                    }
                    
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
            .onChange(of: viewModel.messages.count) { _ in
                withAnimation(.spring(response: 0.3)) {
                    if let lastId = viewModel.messages.filter({ $0.role != .system }).last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Focus Panel Empty State
struct FocusPanelEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: 6) {
                Text("Focus Mode")
                    .font(.system(size: 16, weight: .semibold))
                
                Text("Quick access to Jarvis\nfrom your menu bar")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Focus Panel Message Bubble
struct FocusPanelMessageBubble: View {
    let message: Message
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 40)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Files
                if !message.attachedFileNames.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(message.attachedFileNames, id: \.self) { name in
                            HStack(spacing: 4) {
                                Image(systemName: "paperclip")
                                    .font(.system(size: 9))
                                Text(name)
                                    .font(.system(size: 9))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.blue.opacity(0.15)))
                            .foregroundStyle(.blue)
                        }
                    }
                }
                
                // Message content
                Group {
                    if message.isStreaming && message.content.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { _ in
                                Circle()
                                    .fill(Color.secondary.opacity(0.5))
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    } else {
                        Markdown(message.content)
                            .markdownTheme(.compact)
                            .textSelection(.enabled)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(message.role == .user ? .white : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(bubbleColor)
                )
                
                // Actions on hover
                if isHovering && !message.isStreaming {
                    HStack(spacing: 8) {
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
                    .foregroundStyle(.tertiary)
                    .transition(.opacity)
                }
                
                // Timestamp
                if !message.isStreaming {
                    Text(message.createdAt, style: .time)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
            
            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
    }
    
    private var bubbleColor: Color {
        if message.role == .user {
            return .blue
        } else {
            return colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.92)
        }
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Focus Panel Input
struct FocusPanelInput: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState.Binding var isInputFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 8) {
            // Attached files
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
                                Button(action: { viewModel.removeFile(file) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.blue.opacity(0.15)))
                            .foregroundStyle(.blue)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            
            // Input bar
            HStack(spacing: 8) {
                // Attach
                Button(action: { viewModel.showFilePicker = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
                .fileImporter(
                    isPresented: $viewModel.showFilePicker,
                    allowedContentTypes: [.pdf, .plainText, .image, .png, .jpeg],
                    allowsMultipleSelection: true
                ) { result in
                    if case .success(let urls) = result {
                        viewModel.attachFiles(urls)
                    }
                }
                
                // Text field
                TextField("Ask anything...", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .disabled(viewModel.isSending)
                    .onSubmit { sendMessage() }
                
                // Send/Stop
                if !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.attachedFiles.isEmpty || viewModel.isLoading {
                    Button(action: {
                        if viewModel.isLoading {
                            viewModel.stopGeneration()
                        } else {
                            sendMessage()
                        }
                    }) {
                        Image(systemName: viewModel.isLoading ? "stop.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(viewModel.isLoading ? .red : .blue)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
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

// MARK: - Compact Markdown Theme
extension MarkdownUI.Theme {
    static let compact = Theme()
        .text {
            FontSize(13)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(11)
        }
        .codeBlock { configuration in
            configuration.label
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
}

