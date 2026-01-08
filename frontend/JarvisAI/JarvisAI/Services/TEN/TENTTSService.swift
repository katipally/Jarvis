import Foundation
import AVFoundation
import Combine

/// TEN TTS Service - Optimized AVSpeechSynthesizer for low-latency voice output
@MainActor
class TENTTSService: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isSpeaking = false
    @Published var speakingLevel: Float = 0.0
    @Published var selectedVoiceId: String = ""
    @Published var availableVoices: [VoiceInfo] = []
    
    // MARK: - Callbacks
    var onSpeakingStart: (() -> Void)?
    var onSpeakingEnd: (() -> Void)?
    var onInterrupted: (() -> Void)?
    
    // MARK: - Private Properties
    private let synthesizer = AVSpeechSynthesizer()
    private var utteranceQueue: [String] = []
    private var isProcessingQueue = false
    private var currentUtterance: AVSpeechUtterance?
    private var levelTimer: Timer?
    
    // Voice configuration
    private var preferredVoice: AVSpeechSynthesisVoice?
    
    override init() {
        super.init()
        synthesizer.delegate = self
        loadVoices()
        selectBestVoice()
    }
    
    // MARK: - Voice Management
    
    struct VoiceInfo: Identifiable {
        let id: String
        let identifier: String
        let name: String
        let language: String
        let quality: String
        
        var displayName: String {
            "\(name) (\(quality))"
        }
    }
    
    private func loadVoices() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        
        // Filter for English voices and sort by quality
        availableVoices = voices
            .filter { $0.language.starts(with: "en") }
            .map { voice in
                let quality: String
                switch voice.quality {
                case .enhanced:
                    quality = "Premium"
                case .premium:
                    quality = "Premium"
                default:
                    quality = "Standard"
                }
                
                return VoiceInfo(
                    id: voice.identifier,
                    identifier: voice.identifier,
                    name: voice.name,
                    language: voice.language,
                    quality: quality
                )
            }
            .sorted { ($0.quality == "Premium" ? 0 : 1) < ($1.quality == "Premium" ? 0 : 1) }
    }
    
    private func selectBestVoice() {
        // Prefer British English premium voice for Jarvis character
        let voices = AVSpeechSynthesisVoice.speechVoices()
        
        // Try to find a premium British male voice
        if let britishPremium = voices.first(where: {
            $0.language == "en-GB" && ($0.quality == .enhanced || $0.quality == .premium)
        }) {
            preferredVoice = britishPremium
            selectedVoiceId = britishPremium.identifier
            return
        }
        
        // Fall back to any premium English voice
        if let anyPremium = voices.first(where: {
            $0.language.starts(with: "en") && ($0.quality == .enhanced || $0.quality == .premium)
        }) {
            preferredVoice = anyPremium
            selectedVoiceId = anyPremium.identifier
            return
        }
        
        // Fall back to default English voice
        if let defaultEnglish = voices.first(where: { $0.language.starts(with: "en") }) {
            preferredVoice = defaultEnglish
            selectedVoiceId = defaultEnglish.identifier
        }
    }
    
    func selectVoice(_ identifier: String) {
        if let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            preferredVoice = voice
            selectedVoiceId = identifier
        }
    }
    
    // MARK: - Speaking
    
    /// Speak text immediately (interrupts any current speech)
    func speak(_ text: String) {
        stop()
        
        let utterance = createUtterance(for: text)
        currentUtterance = utterance
        
        isSpeaking = true
        onSpeakingStart?()
        startLevelSimulation()
        
        synthesizer.speak(utterance)
    }
    
    /// Queue text for speaking (for streaming responses)
    func speakStreaming(_ text: String) {
        utteranceQueue.append(text)
        processQueue()
    }
    
    /// Speak a complete sentence (optimized for sentence-by-sentence TTS)
    func speakSentence(_ sentence: String) {
        let utterance = createUtterance(for: sentence)
        
        if !isSpeaking {
            isSpeaking = true
            onSpeakingStart?()
            startLevelSimulation()
        }
        
        synthesizer.speak(utterance)
    }
    
    /// Stop speaking immediately
    func stop() {
        utteranceQueue.removeAll()
        isProcessingQueue = false
        
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            onInterrupted?()
        }
        
        isSpeaking = false
        stopLevelSimulation()
    }
    
    /// Flush any remaining queued text
    func flush() {
        // Process any remaining text in queue
        if !utteranceQueue.isEmpty {
            let remaining = utteranceQueue.joined(separator: " ")
            utteranceQueue.removeAll()
            
            if !remaining.trimmingCharacters(in: .whitespaces).isEmpty {
                let utterance = createUtterance(for: remaining)
                synthesizer.speak(utterance)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func createUtterance(for text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        
        if let voice = preferredVoice {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        }
        
        // Optimize for natural conversation
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05  // Slightly faster
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.0  // No delay for low latency
        utterance.postUtteranceDelay = 0.1
        
        return utterance
    }
    
    private func processQueue() {
        guard !isProcessingQueue, !utteranceQueue.isEmpty else { return }
        
        isProcessingQueue = true
        
        // Combine small chunks for more natural speech
        var combinedText = ""
        while !utteranceQueue.isEmpty {
            let next = utteranceQueue.removeFirst()
            combinedText += next
            
            // Speak when we have a complete sentence or enough text
            if combinedText.contains(where: { ".!?".contains($0) }) || combinedText.count > 100 {
                break
            }
        }
        
        if !combinedText.trimmingCharacters(in: .whitespaces).isEmpty {
            let utterance = createUtterance(for: combinedText)
            
            if !isSpeaking {
                isSpeaking = true
                onSpeakingStart?()
                startLevelSimulation()
            }
            
            synthesizer.speak(utterance)
        }
        
        isProcessingQueue = false
    }
    
    // MARK: - Level Simulation
    
    private func startLevelSimulation() {
        stopLevelSimulation()
        
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isSpeaking else { return }
                // Simulate speaking level with some variation
                self.speakingLevel = Float.random(in: 0.3...0.8)
            }
        }
    }
    
    private func stopLevelSimulation() {
        levelTimer?.invalidate()
        levelTimer = nil
        speakingLevel = 0.0
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TENTTSService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = true
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // Check if there's more in the queue
            if utteranceQueue.isEmpty && !synthesizer.isSpeaking {
                isSpeaking = false
                stopLevelSimulation()
                onSpeakingEnd?()
            } else {
                processQueue()
            }
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            stopLevelSimulation()
        }
    }
}
