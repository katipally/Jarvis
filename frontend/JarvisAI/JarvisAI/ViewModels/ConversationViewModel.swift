import Foundation
import SwiftUI
import Combine
import AVFoundation

/// Conversation state machine states
enum ConversationState: Equatable {
    case idle
    case listening
    case processing
    case speaking
    case interrupted  // User interrupted while AI was speaking
    case error(String)
    
    var description: String {
        switch self {
        case .idle: return "Ready"
        case .listening: return "Listening..."
        case .processing: return "Thinking..."
        case .speaking: return "Speaking..."
        case .interrupted: return "Listening..."
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

/// Input mode for conversation
enum ConversationInputMode: String, CaseIterable {
    case handsFree = "Hands-free"
    case pushToTalk = "Push to Talk"
    
    var icon: String {
        switch self {
        case .handsFree: return "waveform"
        case .pushToTalk: return "hand.tap"
        }
    }
}

/// Main ViewModel for Conversation Mode
@MainActor
class ConversationViewModel: ObservableObject {
    
    // MARK: - Published State
    @Published var state: ConversationState = .idle
    @Published var inputMode: ConversationInputMode = .handsFree
    @Published var isActive = false
    
    // MARK: - Audio Levels (for blob animation)
    @Published var audioLevel: Float = 0.0
    @Published var speakingLevel: Float = 0.0
    
    // MARK: - Transcript
    @Published var currentTranscript = ""      // What user is saying
    @Published var partialTranscript = ""      // Real-time partial
    @Published var assistantResponse = ""      // What Jarvis is saying
    
    // MARK: - Conversation History
    @Published var messages: [ConversationMessage] = []
    
    // MARK: - Settings
    @Published var selectedVoiceId: String = ""
    @Published var availableVoices: [VoiceOption] = []
    @Published var hasPremiumVoices: Bool = false
    
    // MARK: - Calibration State
    @Published var isCalibrating = false
    @Published var calibrationProgress: Float = 0.0
    @Published var isCalibrated = false
    
    // MARK: - Services
    private let audioPipeline = AudioPipeline()
    private let speechRecognition = SpeechRecognitionService()
    private let speechSynthesis = SpeechSynthesisService()
    private let streamingService = StreamingService()
    private let storage = ConversationStorage.shared
    
    // MARK: - WebSocket for TEN Agent
    private var webSocketTask: URLSessionWebSocketTask?
    private var isWebSocketConnected = false
    private var sessionId = UUID().uuidString
    
    // MARK: - Shared Chat Integration
    // Use the same conversation ID as the main chat to share context
    private var sharedChatViewModel: ChatViewModel { SharedChatViewModel.shared.viewModel }
    
    // MARK: - Conversation Storage
    private var currentConversationId: String?
    
    // MARK: - Cancellables
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        setupCallbacks()
        setupSimpleBindings()
        setupNotificationObservers()
    }
    
    // Note: Cleanup is handled in stopConversation() which is called from onDisappear
    // deinit cannot safely call @MainActor methods
    
    // MARK: - Setup Notification Observers for Keyboard Shortcuts
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name("ToggleInputMode"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.toggleInputMode()
            }
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("StartCalibration"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.startCalibration()
            }
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("ClearConversation"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.clearHistory()
            }
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("PushToTalk"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.inputMode == .pushToTalk else { return }
                await self.startPushToTalk()
            }
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("StopSpeaking"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopSpeaking()
            }
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("OpenVoiceSettings"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.openVoiceSettings()
            }
        }
    }
    
    // MARK: - Setup Simple Bindings (avoid complex transforms that can crash)
    private func setupSimpleBindings() {
        // Bind available voices directly
        availableVoices = speechSynthesis.availableVoices
        selectedVoiceId = speechSynthesis.selectedVoiceIdentifier
        hasPremiumVoices = speechSynthesis.hasPremiumVoices
        
        // Bind calibration state from AudioPipeline
        audioPipeline.$isCalibrated
            .receive(on: DispatchQueue.main)
            .assign(to: &$isCalibrated)
        
        audioPipeline.$calibrationProgress
            .receive(on: DispatchQueue.main)
            .assign(to: &$calibrationProgress)
    }
    
    // MARK: - Setup Callbacks
    private func setupCallbacks() {
        // Audio Pipeline callbacks - Handle interruptions
        audioPipeline.onSpeechStart = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.inputMode == .handsFree else { return }
                
                // INTERRUPTION HANDLING: If AI is speaking, stop and listen to user
                if self.state == .speaking {
                    self.handleUserInterruption()
                } else if self.state == .idle {
                    self.startListening()
                }
            }
        }
        
        audioPipeline.onSpeechEnd = { [weak self] buffers in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.finishListening()
            }
        }
        
        audioPipeline.onAudioBuffer = { [weak self] buffer in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Update audio level for animation
                self.audioLevel = self.audioPipeline.audioLevel
                // Send to speech recognition only when listening
                if self.state == .listening || self.state == .interrupted {
                    self.speechRecognition.appendAudioBuffer(buffer)
                }
            }
        }
        
        // Direct interruption callback from AudioPipeline
        audioPipeline.onInterruption = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.state == .speaking else { return }
                self.handleUserInterruption()
            }
        }
        
        // Speech Recognition callbacks
        speechRecognition.onTranscriptionComplete = { [weak self] text in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                // Only process if we're in a listening state
                guard self.state == .listening || self.state == .interrupted else { return }
                
                self.currentTranscript = text
                self.partialTranscript = ""
                
                // Only process if we have meaningful text
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedText.isEmpty && trimmedText.count > 1 {
                    self.processUserInput(trimmedText)
                } else {
                    // No meaningful input, go back to idle and restart listening
                    self.state = .idle
                    if self.inputMode == .handsFree && self.isActive {
                        Task {
                            try? await Task.sleep(for: .milliseconds(200))
                            // CRITICAL: Check isActive again to prevent race condition on exit
                            if self.state == .idle && self.isActive {
                                try? await self.audioPipeline.startRecording()
                            }
                        }
                    }
                }
            }
        }
        
        speechRecognition.onPartialResult = { [weak self] text in
            Task { @MainActor [weak self] in
                self?.partialTranscript = text
            }
        }
        
        // Speech Synthesis callbacks
        speechSynthesis.onSpeakingStarted = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.state = .speaking
                self.speakingLevel = 0.5
                // CRITICAL: Stop recording while speaking to prevent TTS audio from triggering VAD
                // This prevents the "interrupted" issue in handsfree mode
                self.audioPipeline.stopRecording()
                self.audioPipeline.setSpeakingMode(true)
            }
        }
        
        speechSynthesis.onSpeakingFinished = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.speakingLevel = 0
                self.audioPipeline.setSpeakingMode(false)
                
                // Only go to idle if not interrupted
                if self.state == .speaking {
                    self.state = .idle
                    self.assistantResponse = ""
                }
                
                // Resume listening in hands-free mode after a brief delay
                // The delay allows TTS audio to fully stop before resuming microphone
                if self.inputMode == .handsFree && self.isActive && self.state == .idle {
                    try? await Task.sleep(for: .milliseconds(300))
                    if self.state == .idle && self.isActive {
                        try? await self.audioPipeline.startRecording()
                    }
                }
            }
        }
        
        speechSynthesis.onWordSpoken = { [weak self] word in
            Task { @MainActor [weak self] in
                // Create pulsing effect during speech
                let pulse = Float.random(in: 0.3...0.7)
                self?.speakingLevel = pulse
            }
        }
    }
    
    // MARK: - Conversation Control
    func startConversation() async {
        guard !isActive else { return }
        
        isActive = true
        state = .idle
        
        // Connect to TEN Agent WebSocket
        connectWebSocket()
        
        // Check permissions (these are quick checks)
        await audioPipeline.checkPermission()
        await speechRecognition.checkPermission()
        
        // Update voices list after init
        availableVoices = speechSynthesis.availableVoices
        selectedVoiceId = speechSynthesis.selectedVoiceIdentifier
        
        if !audioPipeline.hasPermission {
            state = .error("Microphone permission required. Enable in System Settings.")
            return
        }
        
        if !speechRecognition.hasPermission {
            state = .error("Speech recognition permission required. Enable in System Settings.")
            return
        }
        
        // Start listening in hands-free mode
        if inputMode == .handsFree {
            do {
                try await audioPipeline.startRecording()
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }
    
    func stopConversation() {
        guard isActive else { return }  // Prevent multiple calls
        
        print("[ConversationViewModel] Stopping conversation mode - cleaning up all resources")
        
        isActive = false
        state = .idle
        
        // Stop all audio/speech services immediately
        audioPipeline.stopRecording()
        speechRecognition.stopRecognition()
        speechSynthesis.stop()
        
        // Clear callbacks to prevent any further processing
        audioPipeline.onSpeechStart = nil
        audioPipeline.onSpeechEnd = nil
        audioPipeline.onAudioBuffer = nil
        audioPipeline.onInterruption = nil
        speechRecognition.onTranscriptionComplete = nil
        speechRecognition.onPartialResult = nil
        speechSynthesis.onSpeakingStarted = nil
        speechSynthesis.onSpeakingFinished = nil
        
        // Disconnect WebSocket
        disconnectWebSocket()
        
        // Reset state
        currentTranscript = ""
        partialTranscript = ""
        assistantResponse = ""
        audioLevel = 0
        speakingLevel = 0
        
        // Save conversation before cleanup
        if !messages.isEmpty {
            saveVoiceConversation()
        }
        
        print("[ConversationViewModel] Conversation mode stopped and cleaned up")
    }
    
    // MARK: - Manual Calibration
    /// Start manual calibration - user should speak normally for 3 seconds
    func startCalibration() async {
        isCalibrating = true
        do {
            try await audioPipeline.startManualCalibration()
        } catch {
            state = .error("Calibration failed: \(error.localizedDescription)")
            isCalibrating = false
        }
    }
    
    /// Cancel ongoing calibration
    func cancelCalibration() {
        audioPipeline.cancelCalibration()
        isCalibrating = false
    }
    
    /// Reset calibration and force recalibration on next start
    func resetCalibration() {
        audioPipeline.resetCalibration()
        isCalibrated = false
    }
    
    // MARK: - Listening Control
    private func startListening() {
        // Allow starting from idle or interrupted states
        guard state == .idle || state == .interrupted else { return }
        
        state = .listening
        currentTranscript = ""
        partialTranscript = ""
        
        do {
            try speechRecognition.startRecognition()
        } catch {
            state = .error(error.localizedDescription)
        }
    }
    
    private func finishListening() {
        // Don't change state here - let the transcription callback handle it
        // The callback will call processUserInput which sets state to .processing
        
        // Signal end of audio to speech recognition
        speechRecognition.stopRecognition()
        
        // If we have partial transcript but no final, use the partial
        if currentTranscript.isEmpty && !partialTranscript.isEmpty {
            let finalText = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !finalText.isEmpty {
                currentTranscript = finalText
                partialTranscript = ""
                processUserInput(finalText)
                return
            }
        }
        
        // If still listening with no transcript, go back to idle
        if state == .listening && currentTranscript.isEmpty && partialTranscript.isEmpty {
            state = .idle
            // Restart listening in hands-free mode
            if inputMode == .handsFree && isActive {
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    // CRITICAL: Check isActive again to prevent race condition on exit
                    if state == .idle && isActive {
                        try? await audioPipeline.startRecording()
                    }
                }
            }
        }
    }
    
    // MARK: - Push to Talk
    func startPushToTalk() async {
        guard inputMode == .pushToTalk, isActive else { return }
        
        do {
            try await audioPipeline.startManualRecording()
            startListening()
        } catch {
            state = .error(error.localizedDescription)
        }
    }
    
    func endPushToTalk() {
        guard inputMode == .pushToTalk else { return }
        
        audioPipeline.stopManualRecording()
        finishListening()
    }
    
    // MARK: - Stop Speaking
    func stopSpeaking() {
        speechSynthesis.stop()
        state = .idle
        
        // Send interrupt to backend
        Task {
            await sendInterrupt()
        }
        
        // Resume listening in hands-free mode
        if inputMode == .handsFree && isActive {
            Task {
                try? await Task.sleep(for: .milliseconds(200))
                // CRITICAL: Check isActive again to prevent race condition on exit
                if state == .idle && isActive {
                    try? await audioPipeline.startRecording()
                }
            }
        }
    }
    
    // MARK: - Process User Input
    private func processUserInput(_ text: String) {
        guard !text.isEmpty else {
            state = .idle
            return
        }
        
        // Add user message to history
        let userMessage = ConversationMessage(role: .user, content: text)
        messages.append(userMessage)
        
        state = .processing
        assistantResponse = ""
        
        // Send to backend and get streaming response
        Task {
            await sendToBackend(text)
        }
    }
    
    // MARK: - Conversational System Prompt (Casual Jarvis)
    private let conversationalSystemPrompt = """
You are Jarvis, a chill AI assistant. Be casual and friendly, like talking to a smart friend.

STYLE:
- Keep it short - 1-2 sentences max (this is spoken aloud)
- Use natural speech: "Yeah", "Got it", "Sure thing", "No problem"
- NO formal language - avoid "sir", "certainly", "indeed"
- Use contractions: "I'll", "you're", "that's", "can't"

EXAMPLES:
"What time is it?" → "It's 3:30."
"How are you?" → "I'm good! What's up?"
"Thanks" → "No problem!" or "You got it."
"Tell me a joke" → "Why don't scientists trust atoms? They make up everything."

Be natural, brief, and helpful. Sound like a real person, not a robot or butler.
"""
    
    // MARK: - WebSocket Connection (TEN Agent)
    private func connectWebSocket() {
        guard !isWebSocketConnected else { return }
        
        // Use ws:// for local development
        guard let url = URL(string: "ws://127.0.0.1:8000/api/ws/conversation") else { return }
        
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()
        isWebSocketConnected = true
        
        // Start receiving messages
        receiveWebSocketMessage()
    }
    
    private func disconnectWebSocket() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isWebSocketConnected = false
    }
    
    private func receiveWebSocketMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self?.handleWebSocketMessage(message)
                    self?.receiveWebSocketMessage() // Continue receiving
                case .failure(let error):
                    print("WebSocket receive error: \(error)")
                    self?.isWebSocketConnected = false
                    // Attempt reconnection after delay
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    self?.connectWebSocket()
                }
            }
        }
    }
    
    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseServerMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseServerMessage(text)
            }
        @unknown default:
            break
        }
    }
    
    private func parseServerMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }
        
        switch type {
        case "text_start":
            state = .processing
            assistantResponse = ""
            
        case "text_delta":
            if let content = json["content"] as? String {
                assistantResponse += content
            }
            
        case "sentence_end":
            if let sentence = json["sentence"] as? String {
                // Speak sentence immediately for low latency
                state = .speaking
                speechSynthesis.speakStreaming(sentence)
            }
            
        case "text_done":
            if let fullText = json["full_text"] as? String {
                // Add to history
                let assistantMessage = ConversationMessage(role: .assistant, content: fullText)
                messages.append(assistantMessage)
                
                // Flush TTS
                speechSynthesis.flushStreamingBuffer()
                saveVoiceConversation()
            }
            
        case "interrupted":
            speechSynthesis.stop()
            state = .idle
            if inputMode == .handsFree {
                Task { await startConversation() }
            }
            
        case "error":
            if let errorMsg = json["message"] as? String {
                state = .error(errorMsg)
            }
            
        default:
            break
        }
    }
    
    // MARK: - Backend Integration (WebSocket)
    private func sendToBackend(_ text: String) async {
        if !isWebSocketConnected {
            connectWebSocket()
            // Wait a bit for connection
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        // Build chat history context from shared chat (last 10 messages for context)
        var chatHistory: [[String: String]] = []
        let recentMessages = sharedChatViewModel.messages.suffix(10)
        for msg in recentMessages {
            chatHistory.append([
                "role": msg.role == .user ? "user" : "assistant",
                "content": msg.content
            ])
        }
        
        // Also include conversation mode messages
        for msg in messages.suffix(5) {
            chatHistory.append([
                "role": msg.role == .user ? "user" : "assistant",
                "content": msg.content
            ])
        }
        
        let message: [String: Any] = [
            "type": "text",
            "content": text,
            "session_id": sessionId,
            "chat_history": chatHistory  // Include chat context for better responses
        ]
        
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: data, encoding: .utf8) else { return }
        
        do {
            try await webSocketTask?.send(.string(jsonString))
        } catch {
            state = .error("Failed to send message: \(error.localizedDescription)")
        }
    }
    
    private func sendInterrupt() async {
        let message: [String: Any] = ["type": "interrupt"]
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: data, encoding: .utf8) else { return }
        try? await webSocketTask?.send(.string(jsonString))
    }
    
    // MARK: - Voice Selection
    func selectVoice(_ voiceId: String) {
        speechSynthesis.selectVoice(voiceId)
        selectedVoiceId = voiceId
    }
    
    // MARK: - Voice Preview
    func previewSelectedVoice() {
        speechSynthesis.previewVoice(selectedVoiceId)
    }
    
    func previewVoice(_ voiceId: String) {
        speechSynthesis.previewVoice(voiceId)
    }
    
    // MARK: - Voice Settings
    func openVoiceSettings() {
        speechSynthesis.openVoiceDownloadSettings()
    }
    
    func refreshVoices() {
        speechSynthesis.refreshVoices()
        availableVoices = speechSynthesis.availableVoices
        hasPremiumVoices = speechSynthesis.hasPremiumVoices
        
        // Re-select best voice if current one is not premium and we now have premium
        if hasPremiumVoices {
            let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.starts(with: "en") }
            if let currentVoice = AVSpeechSynthesisVoice(identifier: selectedVoiceId),
               currentVoice.quality == .default,
               let premiumVoice = voices.first(where: { $0.quality == .premium }) {
                selectVoice(premiumVoice.identifier)
            }
        }
    }
    
    // MARK: - Input Mode Toggle
    func toggleInputMode() {
        if inputMode == .handsFree {
            inputMode = .pushToTalk
            audioPipeline.stopRecording()
        } else {
            inputMode = .handsFree
            if isActive {
                Task {
                    try? await audioPipeline.startRecording()
                }
            }
        }
    }
    
    // MARK: - Interrupt (manual stop button)
    func interrupt() {
        speechSynthesis.stop()
        assistantResponse = ""
        state = .idle
        
        if inputMode == .handsFree && isActive {
            Task {
                try? await audioPipeline.startRecording()
            }
        }
    }
    
    // MARK: - Handle User Interruption (automatic when user speaks)
    private func handleUserInterruption() {
        // Stop TTS and clear its buffer immediately
        speechSynthesis.stop()
        audioPipeline.setSpeakingMode(false)
        
        // Keep the partial response in history if substantial
        if !assistantResponse.isEmpty && assistantResponse.count > 20 {
            let partialMessage = ConversationMessage(
                role: .assistant,
                content: assistantResponse + "... [interrupted]"
            )
            messages.append(partialMessage)
        }
        
        // Clear current response and switch to listening
        assistantResponse = ""
        speakingLevel = 0
        state = .interrupted
        
        // Reset speech recognition for new input
        speechRecognition.stopRecognition()
        
        // Small delay to let audio settle, then start listening
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            if state == .interrupted {
                startListening()
            }
        }
    }
    
    // MARK: - Clear History
    func clearHistory() {
        messages.removeAll()
        currentTranscript = ""
        partialTranscript = ""
        assistantResponse = ""
        currentConversationId = nil
    }
    
    // MARK: - Save Conversation to Storage
    private func saveVoiceConversation() {
        guard !messages.isEmpty else { return }
        
        // Convert ConversationMessages to Messages for storage
        let storageMessages = messages.map { msg in
            Message(
                role: msg.role == .user ? .user : .assistant,
                content: msg.content,
                createdAt: msg.timestamp
            )
        }
        
        // Load existing conversations
        var conversations = storage.loadConversations()
        
        if let existingId = currentConversationId,
           let index = conversations.firstIndex(where: { $0.id == existingId }) {
            // Update existing conversation
            conversations[index].messages = storageMessages
            conversations[index].updatedAt = Date()
            conversations[index].chatType = .voice
        } else {
            // Create new conversation
            let title = messages.first?.content.prefix(40).description ?? "Voice Chat"
            let newConversation = Conversation(
                title: String(title),
                messages: storageMessages,
                chatType: .voice
            )
            currentConversationId = newConversation.id
            conversations.insert(newConversation, at: 0)
        }
        
        storage.saveConversations(conversations)
        
        // Notify SharedChatViewModel to refresh
        NotificationCenter.default.post(name: .conversationsDidUpdate, object: nil)
    }
}

// MARK: - Notification for conversation updates
extension Notification.Name {
    static let conversationsDidUpdate = Notification.Name("conversationsDidUpdate")
}

// MARK: - Conversation Message Model
struct ConversationMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let content: String
    let timestamp = Date()
    
    enum MessageRole: String {
        case user
        case assistant
    }
}
