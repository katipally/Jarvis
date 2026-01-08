import Foundation
import Combine
import SwiftUI

/// Conversation state for TEN-based conversation mode
enum TENConversationState: Equatable {
    case idle
    case listening
    case processing
    case speaking
    case error(String)
    
    var description: String {
        switch self {
        case .idle: return "Ready"
        case .listening: return "Listening..."
        case .processing: return "Thinking..."
        case .speaking: return "Speaking..."
        case .error(let msg): return "Error: \(msg)"
        }
    }
    
    var isActive: Bool {
        switch self {
        case .idle, .error: return false
        default: return true
        }
    }
}

/// Input mode for conversation
enum TENInputMode: String, CaseIterable {
    case handsFree = "Hands-free"
    case pushToTalk = "Push to Talk"
    
    var icon: String {
        switch self {
        case .handsFree: return "waveform"
        case .pushToTalk: return "hand.tap"
        }
    }
}

/// Message in conversation history
struct TENMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp: Date
    
    enum Role: String {
        case user
        case assistant
    }
}

/// TEN Conversation ViewModel - Main controller for TEN-based conversation mode
@MainActor
class TENConversationViewModel: ObservableObject {
    
    // MARK: - Published State
    @Published var state: TENConversationState = .idle
    @Published var inputMode: TENInputMode = .handsFree
    @Published var messages: [TENMessage] = []
    @Published var partialTranscript = ""
    @Published var assistantResponse = ""
    @Published var audioLevel: Float = 0.0
    @Published var speakingLevel: Float = 0.0
    @Published var isConnected = false
    
    // MARK: - Services
    private let networkManager = TENNetworkManager.shared
    private let speechService = TENSpeechService()
    private let ttsService = TENTTSService()
    
    // MARK: - Private State
    private var cancellables = Set<AnyCancellable>()
    private var isInitialized = false
    
    // MARK: - Initialization
    
    init() {
        setupBindings()
        setupCallbacks()
    }
    
    // MARK: - Setup
    
    private func setupBindings() {
        // Network connection state
        networkManager.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.isConnected = (state == .connected)
            }
            .store(in: &cancellables)
        
        // Audio levels
        speechService.$audioLevel
            .receive(on: DispatchQueue.main)
            .assign(to: &$audioLevel)
        
        ttsService.$speakingLevel
            .receive(on: DispatchQueue.main)
            .assign(to: &$speakingLevel)
        
        // TTS speaking state
        ttsService.$isSpeaking
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isSpeaking in
                guard let self = self else { return }
                if !isSpeaking && self.state == .speaking {
                    self.finishSpeaking()
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupCallbacks() {
        // Speech recognition callbacks
        speechService.onSpeechStart = { [weak self] in
            Task { @MainActor in
                self?.handleSpeechStart()
            }
        }
        
        speechService.onPartialTranscript = { [weak self] transcript in
            Task { @MainActor in
                self?.partialTranscript = transcript
            }
        }
        
        speechService.onSpeechEnd = { [weak self] transcript in
            Task { @MainActor in
                await self?.handleSpeechEnd(transcript: transcript)
            }
        }
        
        speechService.onAudioLevel = { [weak self] level in
            Task { @MainActor in
                self?.audioLevel = level
            }
        }
        
        // Network callbacks
        networkManager.onResponseStart = { [weak self] in
            Task { @MainActor in
                self?.state = .processing
                self?.assistantResponse = ""
            }
        }
        
        networkManager.onResponseChunk = { [weak self] chunk in
            Task { @MainActor in
                self?.assistantResponse += chunk
            }
        }
        
        networkManager.onSentenceComplete = { [weak self] sentence in
            Task { @MainActor in
                self?.handleSentenceComplete(sentence)
            }
        }
        
        networkManager.onResponseComplete = { [weak self] fullText in
            Task { @MainActor in
                self?.handleResponseComplete(fullText)
            }
        }
        
        networkManager.onInterrupted = { [weak self] in
            Task { @MainActor in
                self?.handleInterrupted()
            }
        }
        
        networkManager.onError = { [weak self] error in
            Task { @MainActor in
                self?.state = .error(error)
            }
        }
        
        // TTS callbacks
        ttsService.onSpeakingStart = { [weak self] in
            Task { @MainActor in
                self?.state = .speaking
            }
        }
        
        ttsService.onSpeakingEnd = { [weak self] in
            Task { @MainActor in
                self?.finishSpeaking()
            }
        }
    }
    
    // MARK: - Lifecycle
    
    func startConversation() async {
        guard !isInitialized else { return }
        isInitialized = true
        
        // Connect to backend
        networkManager.connect()
        
        // Start listening in hands-free mode
        if inputMode == .handsFree {
            await startListening()
        }
    }
    
    func stopConversation() {
        isInitialized = false
        
        speechService.stopListening()
        ttsService.stop()
        networkManager.disconnect()
        
        state = .idle
    }
    
    // MARK: - Input Mode
    
    func toggleInputMode() {
        inputMode = (inputMode == .handsFree) ? .pushToTalk : .handsFree
        
        if inputMode == .handsFree && state == .idle {
            Task {
                await startListening()
            }
        } else if inputMode == .pushToTalk {
            speechService.stopListening()
        }
    }
    
    // MARK: - Listening Control
    
    func startListening() async {
        guard state == .idle || state == .speaking else { return }
        
        // If speaking, interrupt
        if state == .speaking {
            await interrupt()
        }
        
        do {
            state = .listening
            partialTranscript = ""
            try await speechService.startListening()
        } catch {
            state = .error(error.localizedDescription)
        }
    }
    
    func stopListening() {
        speechService.stopListening()
    }
    
    // MARK: - Push to Talk
    
    func startPushToTalk() async {
        guard inputMode == .pushToTalk else { return }
        await startListening()
    }
    
    func endPushToTalk() {
        guard inputMode == .pushToTalk else { return }
        speechService.stopListening()
    }
    
    // MARK: - Interruption
    
    func interrupt() async {
        ttsService.stop()
        
        do {
            try await networkManager.sendInterrupt()
        } catch {
            print("Failed to send interrupt: \(error)")
        }
        
        state = .idle
        
        // Resume listening in hands-free mode
        if inputMode == .handsFree {
            await startListening()
        }
    }
    
    // MARK: - History Management
    
    func clearHistory() {
        messages.removeAll()
        partialTranscript = ""
        assistantResponse = ""
        
        Task {
            try? await networkManager.clearHistory()
            networkManager.newSession()
        }
    }
    
    // MARK: - Event Handlers
    
    private func handleSpeechStart() {
        // If AI is speaking, interrupt
        if state == .speaking {
            Task {
                await interrupt()
            }
        }
        state = .listening
    }
    
    private func handleSpeechEnd(transcript: String) async {
        guard !transcript.trimmingCharacters(in: .whitespaces).isEmpty else {
            // Empty transcript, resume listening
            if inputMode == .handsFree {
                await startListening()
            } else {
                state = .idle
            }
            return
        }
        
        // Add user message
        let userMessage = TENMessage(role: .user, content: transcript, timestamp: Date())
        messages.append(userMessage)
        partialTranscript = ""
        
        // Send to backend
        state = .processing
        
        do {
            try await networkManager.sendText(transcript)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
    
    private func handleSentenceComplete(_ sentence: String) {
        // Speak sentence immediately for low latency
        ttsService.speakSentence(sentence)
        state = .speaking
    }
    
    private func handleResponseComplete(_ fullText: String) {
        // Add assistant message
        let assistantMessage = TENMessage(role: .assistant, content: fullText, timestamp: Date())
        messages.append(assistantMessage)
        
        // Flush any remaining TTS
        ttsService.flush()
    }
    
    private func handleInterrupted() {
        ttsService.stop()
        state = .idle
        
        if inputMode == .handsFree {
            Task {
                await startListening()
            }
        }
    }
    
    private func finishSpeaking() {
        guard state == .speaking else { return }
        
        state = .idle
        
        // Resume listening in hands-free mode
        if inputMode == .handsFree {
            Task {
                await startListening()
            }
        }
    }
    
    // MARK: - Voice Settings
    
    var availableVoices: [TENTTSService.VoiceInfo] {
        ttsService.availableVoices
    }
    
    var selectedVoiceId: String {
        ttsService.selectedVoiceId
    }
    
    func selectVoice(_ identifier: String) {
        ttsService.selectVoice(identifier)
    }
    
    func previewVoice() {
        ttsService.speak("Hello, I'm Jarvis. How may I assist you today, sir?")
    }
}
