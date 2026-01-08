import SwiftUI

/// TEN-based Conversation Mode View
struct TENConversationView: View {
    @StateObject private var viewModel = TENConversationViewModel()
    @State private var isInitialized = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Spacer()
            
            // Visual feedback (blob)
            blobArea
            
            Spacer()
            
            // Transcript area
            transcriptArea
            
            // Controls
            controlsArea
        }
        .task {
            guard !isInitialized else { return }
            isInitialized = true
            await viewModel.startConversation()
        }
        .onDisappear {
            viewModel.stopConversation()
            isInitialized = false
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 8) {
            // Connection indicator
            Circle()
                .fill(viewModel.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            // Input mode toggle
            Button(action: { viewModel.toggleInputMode() }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.inputMode.icon)
                        .font(.system(size: 10))
                    Text(viewModel.inputMode.rawValue)
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.15)))
                .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Voice settings menu
            Menu {
                Section("Select Voice") {
                    ForEach(viewModel.availableVoices.prefix(10)) { voice in
                        Button(action: { viewModel.selectVoice(voice.identifier) }) {
                            HStack {
                                Text(voice.displayName)
                                if voice.identifier == viewModel.selectedVoiceId {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                
                Divider()
                
                Button(action: { viewModel.previewVoice() }) {
                    Label("Preview Voice", systemImage: "play.circle")
                }
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(6)
            }
            .menuStyle(.borderlessButton)
            
            // Expand to main window
            Button(action: { AppDelegate.shared?.openMainWindow() }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    // MARK: - Blob Area
    
    private var blobArea: some View {
        VStack(spacing: 16) {
            // Animated blob
            SiriBlobView(
                state: mapState(viewModel.state),
                audioLevel: viewModel.audioLevel,
                speakingLevel: viewModel.speakingLevel
            )
            
            // State description
            Text(viewModel.state.description)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
    
    private func mapState(_ state: TENConversationState) -> ConversationState {
        switch state {
        case .idle: return .idle
        case .listening: return .listening
        case .processing: return .processing
        case .speaking: return .speaking
        case .error: return .idle
        }
    }
    
    // MARK: - Transcript Area
    
    private var transcriptArea: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    // Message history
                    ForEach(viewModel.messages.suffix(4)) { message in
                        messageRow(message)
                    }
                    
                    // Current user input
                    if !viewModel.partialTranscript.isEmpty {
                        currentInputRow
                            .id("currentInput")
                    }
                    
                    // Current assistant response
                    if !viewModel.assistantResponse.isEmpty && viewModel.state != .idle {
                        currentResponseRow
                            .id("currentResponse")
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(maxHeight: 140)
            .onChange(of: viewModel.assistantResponse) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("currentResponse", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.partialTranscript) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("currentInput", anchor: .bottom)
                }
            }
        }
    }
    
    private func messageRow(_ message: TENMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: message.role == .user ? "person.fill" : "brain")
                .font(.system(size: 10))
                .foregroundStyle(message.role == .user ? .blue : .purple)
                .frame(width: 16)
            
            Text(message.content)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.leading)
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
    
    private var currentInputRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "person.fill")
                .font(.system(size: 10))
                .foregroundStyle(.green)
                .frame(width: 16)
            
            Text(viewModel.partialTranscript)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            // Recording indicator
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .opacity(viewModel.state == .listening ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.green.opacity(0.15)))
    }
    
    private var currentResponseRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "brain")
                .font(.system(size: 10))
                .foregroundStyle(.purple)
                .frame(width: 16)
            
            Text(viewModel.assistantResponse)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.leading)
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.purple.opacity(0.15)))
    }
    
    // MARK: - Controls Area
    
    private var controlsArea: some View {
        VStack(spacing: 10) {
            // Push to talk button (only in push-to-talk mode)
            if viewModel.inputMode == .pushToTalk {
                pushToTalkButton
            }
            
            // Action buttons
            HStack(spacing: 24) {
                // Stop button (when speaking)
                if viewModel.state == .speaking {
                    Button(action: { Task { await viewModel.interrupt() } }) {
                        VStack(spacing: 2) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 14))
                            Text("Stop")
                                .font(.system(size: 9))
                        }
                        .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                
                // Clear button
                Button(action: { viewModel.clearHistory() }) {
                    VStack(spacing: 2) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                        Text("Clear")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
    }
    
    private var pushToTalkButton: some View {
        Button(action: {}) {
            HStack(spacing: 6) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16))
                Text("Hold to Talk")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(viewModel.state == .listening ? Color.green.opacity(0.8) : Color.blue.opacity(0.6))
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if viewModel.state != .listening {
                        Task { await viewModel.startPushToTalk() }
                    }
                }
                .onEnded { _ in
                    viewModel.endPushToTalk()
                }
        )
    }
}

// MARK: - Preview

#Preview {
    TENConversationView()
        .frame(width: 380, height: 500)
        .background(Color.black)
}
