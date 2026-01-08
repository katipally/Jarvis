import SwiftUI

/// Panel mode options
enum PanelMode: String, CaseIterable {
    case focus = "Focus"
    case conversation = "Conversation"
    
    var icon: String {
        switch self {
        case .focus: return "keyboard"
        case .conversation: return "waveform"
        }
    }
}

/// Unified panel view that switches between Focus and Conversation modes
struct UnifiedPanelView: View {
    @State private var currentMode: PanelMode = .focus
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag handle area
            dragHandle
            
            // Mode switcher header
            modeSwitcher
            
            // Content based on mode
            Group {
                switch currentMode {
                case .focus:
                    FocusPanelContent()
                case .conversation:
                    ConversationModeContent()
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
        .frame(width: 380, height: 520)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.spring(response: 0.3), value: currentMode)
    }
    
    // MARK: - Drag Handle
    private var dragHandle: some View {
        HStack {
            // Drag indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 16)
        .contentShape(Rectangle())
    }
    
    // MARK: - Mode Switcher
    private var modeSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(Array(PanelMode.allCases.enumerated()), id: \.element) { index, mode in
                Button(action: { currentMode = mode }) {
                    HStack(spacing: 6) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 12))
                        Text(mode.rawValue)
                            .font(.system(size: 12, weight: .medium))
                        // Keyboard shortcut hint
                        Text("⌘\(index + 1)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .foregroundStyle(currentMode == mode ? .white : .white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(currentMode == mode ? Color.white.opacity(0.15) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))
        )
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

/// Focus Panel content (extracted from FocusPanelView)
struct FocusPanelContent: View {
    @ObservedObject private var viewModel = SharedChatViewModel.shared.viewModel
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with controls
            FocusPanelHeader(viewModel: viewModel)
            
            Divider()
                .opacity(0.3)
            
            // Chat area with messages
            FocusChatArea(viewModel: viewModel, isInputFocused: $isInputFocused)
            
            // Input pill
            FocusInputPill(viewModel: viewModel, isInputFocused: $isInputFocused)
        }
    }
}

/// Conversation Mode content (extracted from ConversationModeView)
struct ConversationModeContent: View {
    @StateObject private var viewModel = ConversationViewModel()
    @State private var isInitialized = false
    @State private var showCalibrationSheet = false
    @State private var isPushToTalkActive = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Conversation header
            conversationHeader
            
            // Calibration indicator (if calibrating)
            if viewModel.isCalibrating {
                calibrationView
            } else {
                Spacer()
                
                // Blob
                blobArea
                
                Spacer()
                
                // Transcript
                transcriptArea
            }
            
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
    
    // MARK: - Calibration View
    private var calibrationView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            // Calibration animation
            ZStack {
                // Outer ring (noise level)
                Circle()
                    .stroke(Color.orange.opacity(0.3), lineWidth: 3)
                    .frame(width: 120, height: 120)
                
                // Progress ring
                Circle()
                    .trim(from: 0, to: CGFloat(viewModel.calibrationProgress))
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                
                // Audio level indicator
                Circle()
                    .fill(Color.green.opacity(0.3))
                    .frame(width: 80 + CGFloat(viewModel.audioLevel) * 30, 
                           height: 80 + CGFloat(viewModel.audioLevel) * 30)
                    .animation(.easeOut(duration: 0.1), value: viewModel.audioLevel)
                
                // Mic icon
                Image(systemName: "mic.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
            }
            
            VStack(spacing: 8) {
                Text("Calibrating...")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                
                Text("Speak normally for a few seconds")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                
                // Progress percentage
                Text("\(Int(viewModel.calibrationProgress * 100))%")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)
            }
            
            // Audio level bars
            HStack(spacing: 4) {
                ForEach(0..<20, id: \.self) { index in
                    let threshold = Float(index) / 20.0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(viewModel.audioLevel > threshold ? 
                              (threshold > 0.5 ? Color.green : Color.orange) : 
                              Color.white.opacity(0.2))
                        .frame(width: 12, height: 20)
                }
            }
            .padding(.top, 8)
            
            // Cancel button
            Button(action: { viewModel.cancelCalibration() }) {
                Text("Cancel")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Conversation Header
    private var conversationHeader: some View {
        HStack(spacing: 8) {
            // Input mode toggle with shortcut hint
            Button(action: { viewModel.toggleInputMode() }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.inputMode.icon)
                        .font(.system(size: 10))
                    Text(viewModel.inputMode.rawValue)
                        .font(.system(size: 10, weight: .medium))
                    Text("⌃⌥M")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.15)))
                .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Toggle input mode (⌃⌥M)")
            
            // Calibrate button
            Button(action: { Task { await viewModel.startCalibration() } }) {
                HStack(spacing: 3) {
                    Image(systemName: viewModel.isCalibrated ? "checkmark.circle.fill" : "waveform.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(viewModel.isCalibrated ? .green : .orange)
                    Text("⌃⌥B")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.1)))
                .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Calibrate microphone (⌃⌥B)")
            
            Spacer()
            
            // Voice settings
            Menu {
                Section("Select Voice") {
                    ForEach(viewModel.availableVoices.prefix(15)) { voice in
                        // Select voice button
                        Button(action: { 
                            viewModel.selectVoice(voice.identifier)
                        }) {
                            HStack {
                                // Selected indicator
                                if voice.identifier == viewModel.selectedVoiceId {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.secondary)
                                }
                                
                                // Quality indicator
                                Image(systemName: voice.qualityIcon)
                                    .foregroundStyle(voice.quality == "Premium" ? .yellow : .secondary)
                                
                                Text(voice.displayName)
                                    .fontWeight(voice.identifier == viewModel.selectedVoiceId ? .semibold : .regular)
                            }
                        }
                    }
                }
                
                Divider()
                
                Section("Preview Voice") {
                    // Preview currently selected voice
                    Button(action: { viewModel.previewSelectedVoice() }) {
                        Label("Preview Selected Voice", systemImage: "play.circle.fill")
                    }
                }
                
                Divider()
                
                Section("Settings") {
                    Button(action: { viewModel.openVoiceSettings() }) {
                        Label("Download Premium Voices", systemImage: "arrow.down.circle")
                    }
                    .keyboardShortcut("v", modifiers: [.control, .option])
                    
                    Button(action: { viewModel.refreshVoices() }) {
                        Label("Refresh Voice List", systemImage: "arrow.clockwise")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11))
                    if viewModel.selectedVoiceId.isEmpty {
                        Circle()
                            .fill(.orange)
                            .frame(width: 5, height: 5)
                    } else {
                        Circle()
                            .fill(.green)
                            .frame(width: 5, height: 5)
                    }
                }
                .foregroundStyle(.white.opacity(0.7))
                .padding(5)
            }
            .menuStyle(.borderlessButton)
            .help("Voice settings (⌃⌥V)")
            
            // Expand button
            Button(action: { AppDelegate.shared?.openMainWindow() }) {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11))
                    Text("⌘O")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Open main window (⌘⇧O)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
    
    // MARK: - Blob Area
    private var blobArea: some View {
        VStack(spacing: 12) {
            SiriBlobView(
                state: viewModel.state,
                audioLevel: viewModel.audioLevel,
                speakingLevel: viewModel.speakingLevel
            )
            
            Text(viewModel.state.description)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
    
    // MARK: - Transcript Area (Scrollable)
    private var transcriptArea: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    // Show recent conversation history (last 4 messages)
                    ForEach(viewModel.messages.suffix(4)) { message in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: message.role == .user ? "person.fill" : "brain")
                                .font(.system(size: 10))
                                .foregroundStyle(message.role == .user ? .green : .purple)
                                .frame(width: 16)
                            
                            Text(message.content)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(message.role == .user ? Color.green.opacity(0.1) : Color.purple.opacity(0.1))
                        )
                        .id(message.id)
                    }
                    
                    // Current user input (partial or final)
                    if !viewModel.partialTranscript.isEmpty || (!viewModel.currentTranscript.isEmpty && viewModel.state == .listening) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.green)
                                .frame(width: 16)
                            
                            Text(viewModel.partialTranscript.isEmpty ? viewModel.currentTranscript : viewModel.partialTranscript)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.9))
                                .multilineTextAlignment(.leading)
                            
                            Spacer()
                            
                            // Recording indicator
                            Circle()
                                .fill(.red)
                                .frame(width: 6, height: 6)
                                .opacity(viewModel.state == .listening ? 1 : 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.green.opacity(0.15)))
                        .id("currentInput")
                    }
                    
                    // Current assistant response (streaming)
                    if !viewModel.assistantResponse.isEmpty {
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
        .animation(.spring(response: 0.3), value: viewModel.messages.count)
    }
    
    // MARK: - Controls Area
    private var controlsArea: some View {
        VStack(spacing: 8) {
            if viewModel.inputMode == .pushToTalk {
                // Push to talk button with shortcut hint
                Button(action: {}) {
                    HStack(spacing: 6) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 14))
                        Text("Hold to Talk")
                            .font(.system(size: 12, weight: .medium))
                        Text("⌃⌥R")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
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
                .help("Hold to record (⌃⌥R)")
            }
            
            // Action buttons with shortcuts
            HStack(spacing: 20) {
                if viewModel.state == .speaking {
                    Button(action: { viewModel.interrupt() }) {
                        VStack(spacing: 2) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 12))
                            Text("Stop")
                                .font(.system(size: 8))
                        }
                        .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Stop speaking")
                }
                
                Button(action: { viewModel.clearHistory() }) {
                    VStack(spacing: 2) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                        Text("Clear")
                            .font(.system(size: 8))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Clear history (⇧⌘⌫)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

// MARK: - Preview
#Preview {
    UnifiedPanelView()
        .frame(width: 400, height: 550)
        .background(Color.black)
}
