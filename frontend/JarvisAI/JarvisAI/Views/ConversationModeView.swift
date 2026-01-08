import SwiftUI

/// Conversation Mode view with Siri-style blob and voice interaction
struct ConversationModeView: View {
    @StateObject private var viewModel = ConversationViewModel()
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Spacer()
            
            // Main blob area
            blobArea
            
            Spacer()
            
            // Transcript area
            transcriptArea
            
            // Controls
            controlsArea
        }
        .frame(width: 380, height: 520)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            Task {
                await viewModel.startConversation()
            }
        }
        .onDisappear {
            viewModel.stopConversation()
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            // Mode indicator
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 14))
                Text("Conversation")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.9))
            
            Spacer()
            
            // Input mode toggle
            Button(action: { viewModel.toggleInputMode() }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.inputMode.icon)
                        .font(.system(size: 11))
                    Text(viewModel.inputMode.rawValue)
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.15)))
                .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            
            // Voice settings
            Menu {
                voiceMenu
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(6)
            }
            .menuStyle(.borderlessButton)
            
            // Close button
            Button(action: { AppDelegate.shared?.closeFocusPanel() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
    
    // MARK: - Voice Menu
    @ViewBuilder
    private var voiceMenu: some View {
        Section("Voice") {
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
    }
    
    // MARK: - Blob Area
    private var blobArea: some View {
        VStack(spacing: 16) {
            SiriBlobView(
                state: viewModel.state,
                audioLevel: viewModel.audioLevel,
                speakingLevel: viewModel.speakingLevel
            )
            
            // State description
            Text(viewModel.state.description)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .animation(.easeInOut, value: viewModel.state)
        }
    }
    
    // MARK: - Transcript Area
    private var transcriptArea: some View {
        VStack(spacing: 12) {
            // Current transcript (what user is saying)
            if !viewModel.partialTranscript.isEmpty || !viewModel.currentTranscript.isEmpty {
                HStack {
                    Image(systemName: "person.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                    
                    Text(viewModel.partialTranscript.isEmpty ? viewModel.currentTranscript : viewModel.partialTranscript)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.15))
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Assistant response
            if !viewModel.assistantResponse.isEmpty {
                HStack {
                    Image(systemName: "brain")
                        .font(.system(size: 12))
                        .foregroundStyle(.purple)
                    
                    Text(viewModel.assistantResponse)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(3)
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.purple.opacity(0.15))
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.3), value: viewModel.partialTranscript)
        .animation(.spring(response: 0.3), value: viewModel.assistantResponse)
    }
    
    // MARK: - Controls Area
    private var controlsArea: some View {
        VStack(spacing: 12) {
            // Push to talk button (only in push-to-talk mode)
            if viewModel.inputMode == .pushToTalk {
                pushToTalkButton
            }
            
            // Action buttons
            HStack(spacing: 20) {
                // Interrupt button
                if viewModel.state == .speaking {
                    Button(action: { viewModel.interrupt() }) {
                        VStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 16))
                            Text("Stop")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                
                // Clear history
                Button(action: { viewModel.clearHistory() }) {
                    VStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                        Text("Clear")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                
                // Expand to chat
                Button(action: { AppDelegate.shared?.openMainWindow() }) {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 16))
                        Text("Expand")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }
    
    // MARK: - Push to Talk Button
    private var pushToTalkButton: some View {
        Button(action: {}) {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18))
                Text("Hold to Talk")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(
                        viewModel.state == .listening
                            ? Color.green.opacity(0.8)
                            : Color.blue.opacity(0.6)
                    )
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if viewModel.state != .listening {
                        Task {
                            await viewModel.startPushToTalk()
                        }
                    }
                }
                .onEnded { _ in
                    viewModel.endPushToTalk()
                }
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - Preview
#Preview {
    ConversationModeView()
        .frame(width: 400, height: 550)
        .background(Color.black)
}
