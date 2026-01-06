import SwiftUI
import MarkdownUI

/// Focus Mode - Siri-inspired compact chat interface for macOS 26
/// Distraction-free, centered conversation with beautiful animations
struct FocusView: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    @State private var showingMessages = true
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Ambient Background
                FocusBackgroundView(isLoading: viewModel.isLoading)
                
                VStack(spacing: 0) {
                    // Minimal Header
                    FocusHeaderView(viewModel: viewModel)
                    
                    // Messages in compact scrollable area
                    FocusMessagesView(
                        viewModel: viewModel,
                        isInputFocused: $isInputFocused,
                        containerHeight: geometry.size.height
                    )
                    
                    // Siri-style Input Pill at bottom
                    FocusInputPill(
                        viewModel: viewModel,
                        isInputFocused: $isInputFocused
                    )
                    .padding(.horizontal, max(40, (geometry.size.width - 600) / 2))
                    .padding(.bottom, 32)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 500)
    }
}

// MARK: - Focus Background
struct FocusBackgroundView: View {
    let isLoading: Bool
    @State private var animateGradient = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Base dark gradient
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(white: 0.08), Color(white: 0.05), Color(white: 0.02)]
                    : [Color(white: 0.98), Color(white: 0.95), Color(white: 0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Animated ambient glow when loading
            if isLoading {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                SiriColors.glowPurple.opacity(0.3),
                                SiriColors.glowBlue.opacity(0.2),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 50,
                            endRadius: 400
                        )
                    )
                    .frame(width: 800, height: 800)
                    .blur(radius: 80)
                    .offset(y: animateGradient ? -50 : 50)
                    .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: animateGradient)
                    .onAppear { animateGradient = true }
            }
            
            // Subtle noise texture
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.3)
                .ignoresSafeArea()
        }
    }
}

// MARK: - Focus Header
struct FocusHeaderView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            // Siri orb indicator
            ZStack {
                SiriGlowRing(isActive: viewModel.isLoading, size: 36)
                
                Circle()
                    .fill(
                        RadialGradient(
                            colors: viewModel.isLoading
                                ? [SiriColors.glowPurple, SiriColors.glowBlue]
                                : [Color.blue, Color.purple.opacity(0.8)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 14
                        )
                    )
                    .frame(width: 28, height: 28)
            }
            .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Jarvis")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                
                Text(viewModel.isLoading ? "Thinking..." : "Focus Mode")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Token counter
            if viewModel.currentTokenCount > 0 || viewModel.totalTokensUsed > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10))
                    Text("\(viewModel.isLoading ? viewModel.currentTokenCount : viewModel.totalTokensUsed)")
                        .font(.system(size: 11, design: .monospaced))
                }
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
            }
            
            // New chat button
            Button(action: { viewModel.startNewChat() }) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("New Chat")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

// MARK: - Focus Messages View
struct FocusMessagesView: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState.Binding var isInputFocused: Bool
    let containerHeight: CGFloat
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if viewModel.messages.isEmpty {
                        FocusEmptyState()
                            .frame(minHeight: containerHeight - 200)
                    } else {
                        ForEach(viewModel.messages.filter { $0.role != .system }) { message in
                            FocusMessageBubble(
                                message: message,
                                viewModel: viewModel,
                                isInputFocused: $isInputFocused
                            )
                            .id(message.id)
                        }
                    }
                    
                    Color.clear.frame(height: 20)
                }
                .padding(.horizontal, 40)
            }
            .scrollIndicators(.hidden)
            .onChange(of: viewModel.messages.count) { _ in
                withAnimation(.spring(response: 0.4)) {
                    if let lastId = viewModel.messages.filter({ $0.role != .system }).last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Focus Empty State
struct FocusEmptyState: View {
    @State private var pulseAnimation = false
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                SiriGlowRing(isActive: true, size: 100)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SiriColors.glowPurple, SiriColors.glowBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(pulseAnimation ? 1.1 : 1.0)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    pulseAnimation = true
                }
            }
            
            VStack(spacing: 8) {
                Text("Focus Mode")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                
                Text("A distraction-free space for deep conversations")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Focus Message Bubble
struct FocusMessageBubble: View {
    let message: Message
    @ObservedObject var viewModel: ChatViewModel
    @FocusState.Binding var isInputFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .user {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Message content
                Group {
                    if message.isStreaming && message.content.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .fill(Color.white.opacity(0.5))
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    } else {
                        Markdown(message.content)
                            .markdownTheme(.basic)
                            .markdownBlockStyle(\.codeBlock) { configuration in
                                configuration.label
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.95))
                                    )
                                    .markdownTextStyle {
                                        FontFamilyVariant(.monospaced)
                                        FontSize(12)
                                    }
                            }
                            .textSelection(.enabled)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                }
                .foregroundStyle(message.role == .user ? .white : .primary)
                .background(
                    Group {
                        if message.role == .user {
                            LinearGradient(
                                colors: [SiriColors.glowPurple, SiriColors.glowBlue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        } else {
                            colorScheme == .dark
                                ? Color(white: 0.15)
                                : Color(white: 0.92)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
                
                // Compact actions on hover
                if isHovering && !message.isStreaming {
                    FocusMessageActions(message: message, viewModel: viewModel)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .frame(maxWidth: 500, alignment: message.role == .user ? .trailing : .leading)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
            
            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Focus Message Actions
struct FocusMessageActions: View {
    let message: Message
    @ObservedObject var viewModel: ChatViewModel
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: { copyToClipboard(message.content) }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .help("Copy")
            
            if message.role == .assistant {
                Button(action: { Task { await viewModel.regenerateMessage(message) } }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
                .help("Regenerate")
            }
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Focus Input Pill
struct FocusInputPill: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState.Binding var isInputFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    @State private var glowAnimation = false
    
    var body: some View {
        VStack(spacing: 0) {
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
                            .background(SiriColors.glowPurple.opacity(0.2), in: Capsule())
                            .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            
            // Main input pill
            ZStack {
                // Animated glow border when focused
                if isInputFocused || viewModel.isLoading {
                    Capsule()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    SiriColors.glowPurple,
                                    SiriColors.glowBlue,
                                    SiriColors.glowPink,
                                    SiriColors.glowPurple
                                ],
                                center: .center,
                                startAngle: .degrees(glowAnimation ? 0 : 360),
                                endAngle: .degrees(glowAnimation ? 360 : 720)
                            ),
                            lineWidth: 2
                        )
                        .blur(radius: 4)
                        .opacity(0.6)
                        .onAppear {
                            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                                glowAnimation = true
                            }
                        }
                }
                
                // Input container
                HStack(spacing: 10) {
                    // Attach button
                    Button(action: { viewModel.showFilePicker = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
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
                    
                    // Text input
                    TextField("Ask anything...", text: $viewModel.inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .lineLimit(1...5)
                        .focused($isInputFocused)
                        .disabled(viewModel.isSending)
                        .onSubmit { sendMessage() }
                    
                    // Send/Stop button
                    if !viewModel.inputText.isEmpty || !viewModel.attachedFiles.isEmpty || viewModel.isLoading {
                        Button(action: {
                            if viewModel.isLoading {
                                viewModel.stopGeneration()
                            } else {
                                sendMessage()
                            }
                        }) {
                            ZStack {
                                if viewModel.isLoading {
                                    Circle()
                                        .fill(Color.red.opacity(0.9))
                                        .frame(width: 28, height: 28)
                                } else {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [SiriColors.glowPurple, SiriColors.glowBlue],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 28, height: 28)
                                }
                                
                                Image(systemName: viewModel.isLoading ? "stop.fill" : "arrow.up")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.95))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                )
            }
        }
        .animation(.spring(response: 0.3), value: viewModel.attachedFiles.count)
        .animation(.spring(response: 0.3), value: viewModel.inputText.isEmpty)
    }
    
    private func sendMessage() {
        guard viewModel.canSend else { return }
        Task {
            await viewModel.sendMessage()
            isInputFocused = true
        }
    }
}

// MARK: - Preview
struct FocusPreviewContainer: View {
    @StateObject private var viewModel = ChatViewModel()
    
    var body: some View {
        FocusView(viewModel: viewModel)
            .frame(width: 700, height: 600)
    }
}

#Preview {
    FocusPreviewContainer()
        .preferredColorScheme(.dark)
}

