import Foundation
import AVFoundation
import Combine
import AppKit

/// Speech synthesis service using AVSpeechSynthesizer with premium voice selection
/// Prioritizes Premium > Enhanced > Personal voices for natural, human-like output
/// Supports SSML for expressive speech and voice preview
@MainActor
class SpeechSynthesisService: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isSpeaking = false
    @Published var isPreviewing = false
    @Published var availableVoices: [VoiceOption] = []
    @Published var selectedVoiceIdentifier: String = ""
    @Published var speakingProgress: Float = 0.0
    @Published var currentUtterance: String = ""
    @Published var hasPersonalVoiceAccess = false
    @Published var hasPremiumVoices = false
    
    // MARK: - Settings (optimized for natural, human-like speech)
    // AVSpeechUtteranceDefaultSpeechRate is 0.5, range is 0.0 to 1.0
    @Published var speechRate: Float = AVSpeechUtteranceDefaultSpeechRate
    @Published var speechPitch: Float = 1.0  // Normal pitch (0.5 - 2.0)
    @Published var speechVolume: Float = 1.0 // Full volume for clarity
    
    // MARK: - Synthesizer
    private let synthesizer = AVSpeechSynthesizer()
    private let previewSynthesizer = AVSpeechSynthesizer() // Separate synthesizer for previews
    private var utteranceQueue: [String] = []
    private var sentenceBuffer: String = ""
    private let sentenceDelimiters = CharacterSet(charactersIn: ".!?;\n")
    
    // Preview phrases for voice selection
    private let previewPhrases = [
        "Hello! I'm your AI assistant, ready to help you.",
        "How can I assist you today?",
        "I can help you with questions, tasks, and more."
    ]
    
    // MARK: - Callbacks
    var onSpeakingStarted: (() -> Void)?
    var onSpeakingFinished: (() -> Void)?
    var onWordSpoken: ((String) -> Void)?
    
    // MARK: - User Defaults Keys
    private let selectedVoiceKey = "JarvisSelectedVoice"
    private let speechRateKey = "JarvisSpeechRate"
    private let speechPitchKey = "JarvisSpeechPitch"
    
    // MARK: - Initialization
    override init() {
        super.init()
        synthesizer.delegate = self
        loadAvailableVoices()
        loadSettings()
        checkForPremiumVoices()
    }
    
    private func checkForPremiumVoices() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        hasPremiumVoices = voices.contains { $0.quality == .premium }
    }
    
    // MARK: - Load Available Voices
    private func loadAvailableVoices() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        
        // Filter for English voices and sort by quality (Premium > Enhanced > Default)
        let englishVoices = voices
            .filter { $0.language.starts(with: "en") }
            .sorted { v1, v2 in
                // Personal voices first, then Premium, Enhanced, Default
                let score1 = voiceQualityScore(v1)
                let score2 = voiceQualityScore(v2)
                if score1 != score2 {
                    return score1 > score2
                }
                return v1.name < v2.name
            }
        
        availableVoices = englishVoices.map { voice in
            var isPersonal = false
            if #available(macOS 14.0, *) {
                isPersonal = voice.voiceTraits.contains(.isPersonalVoice)
            }
            return VoiceOption(
                identifier: voice.identifier,
                name: voice.name,
                language: voice.language,
                quality: isPersonal ? "Personal" : voiceQualityString(voice.quality),
                isDefault: false,
                isPersonal: isPersonal
            )
        }
        
        // Set default voice if none selected - prioritize best quality
        if selectedVoiceIdentifier.isEmpty {
            selectBestAvailableVoice(from: englishVoices)
        }
    }
    
    private func voiceQualityScore(_ voice: AVSpeechSynthesisVoice) -> Int {
        if #available(macOS 14.0, *) {
            if voice.voiceTraits.contains(.isPersonalVoice) { return 100 }
        }
        switch voice.quality {
        case .premium: return 3
        case .enhanced: return 2
        case .default: return 1
        @unknown default: return 0
        }
    }
    
    private func selectBestAvailableVoice(from voices: [AVSpeechSynthesisVoice]) {
        // Priority: Personal Voice > Premium > Enhanced > Default
        // Look for specific high-quality voices known to sound natural
        let preferredVoices = ["Samantha", "Ava", "Zoe", "Nicky", "Tom", "Evan"]
        
        // Try Personal Voice first (macOS 14.0+)
        if #available(macOS 14.0, *) {
            if let personalVoice = voices.first(where: { $0.voiceTraits.contains(.isPersonalVoice) }) {
                selectedVoiceIdentifier = personalVoice.identifier
                return
            }
        }
        
        // Try Premium voices with preferred names
        for name in preferredVoices {
            if let voice = voices.first(where: { $0.quality == .premium && $0.name.contains(name) }) {
                selectedVoiceIdentifier = voice.identifier
                return
            }
        }
        
        // Fall back to any Premium voice
        if let premiumVoice = voices.first(where: { $0.quality == .premium }) {
            selectedVoiceIdentifier = premiumVoice.identifier
            return
        }
        
        // Try Enhanced voices
        for name in preferredVoices {
            if let voice = voices.first(where: { $0.quality == .enhanced && $0.name.contains(name) }) {
                selectedVoiceIdentifier = voice.identifier
                return
            }
        }
        
        if let enhancedVoice = voices.first(where: { $0.quality == .enhanced }) {
            selectedVoiceIdentifier = enhancedVoice.identifier
            return
        }
        
        // Last resort: default US English voice
        if let defaultVoice = AVSpeechSynthesisVoice(language: "en-US") {
            selectedVoiceIdentifier = defaultVoice.identifier
        }
    }
    
    // MARK: - Request Personal Voice Access
    func requestPersonalVoiceAccess() {
        if #available(macOS 14.0, *) {
            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { [weak self] status in
                Task { @MainActor in
                    self?.hasPersonalVoiceAccess = (status == .authorized)
                    if status == .authorized {
                        self?.loadAvailableVoices()
                    }
                }
            }
        }
    }
    
    private func voiceQualityString(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .default:
            return "Standard"
        case .enhanced:
            return "Enhanced"
        case .premium:
            return "Premium"
        @unknown default:
            return "Unknown"
        }
    }
    
    // MARK: - Settings Persistence
    private func loadSettings() {
        if let savedVoice = UserDefaults.standard.string(forKey: selectedVoiceKey) {
            // Verify voice still exists
            if AVSpeechSynthesisVoice(identifier: savedVoice) != nil {
                selectedVoiceIdentifier = savedVoice
            }
        }
        
        let savedRate = UserDefaults.standard.float(forKey: speechRateKey)
        if savedRate > 0 {
            speechRate = savedRate
        }
        
        let savedPitch = UserDefaults.standard.float(forKey: speechPitchKey)
        if savedPitch > 0 {
            speechPitch = savedPitch
        }
    }
    
    func saveSettings() {
        UserDefaults.standard.set(selectedVoiceIdentifier, forKey: selectedVoiceKey)
        UserDefaults.standard.set(speechRate, forKey: speechRateKey)
        UserDefaults.standard.set(speechPitch, forKey: speechPitchKey)
    }
    
    // MARK: - Voice Preview
    func previewVoice(_ identifier: String) {
        // Stop any current preview
        previewSynthesizer.stopSpeaking(at: .immediate)
        
        guard let voice = AVSpeechSynthesisVoice(identifier: identifier) else { return }
        
        // Select a random preview phrase
        let phrase = previewPhrases.randomElement() ?? previewPhrases[0]
        
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = voice
        utterance.rate = speechRate
        utterance.pitchMultiplier = speechPitch
        utterance.volume = speechVolume
        
        // Natural speech timing
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        
        isPreviewing = true
        previewSynthesizer.speak(utterance)
        
        // Auto-reset preview state after estimated duration
        let estimatedDuration = Double(phrase.count) / 15.0 // ~15 chars per second
        DispatchQueue.main.asyncAfter(deadline: .now() + estimatedDuration + 0.5) { [weak self] in
            self?.isPreviewing = false
        }
    }
    
    func stopPreview() {
        previewSynthesizer.stopSpeaking(at: .immediate)
        isPreviewing = false
    }
    
    // MARK: - Open Voice Download Settings
    func openVoiceDownloadSettings() {
        // Open System Settings to Spoken Content where users can download voices
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?Accessibility_SpeakableItems") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func refreshVoices() {
        loadAvailableVoices()
        checkForPremiumVoices()
    }
    
    // MARK: - Speak Text
    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        
        // If already speaking, queue the text
        if isSpeaking {
            utteranceQueue.append(text)
            return
        }
        
        performSpeak(text)
    }
    
    private func performSpeak(_ text: String) {
        // Clean text for better synthesis
        let cleanedText = preprocessTextForSpeech(text)
        guard !cleanedText.isEmpty else {
            // Process next in queue if this one was empty
            if !utteranceQueue.isEmpty {
                processQueue()
            }
            return
        }
        
        // Try SSML first for more natural speech with prosody control
        let utterance: AVSpeechUtterance
        if let ssmlUtterance = createSSMLUtterance(for: cleanedText) {
            utterance = ssmlUtterance
        } else {
            utterance = AVSpeechUtterance(string: cleanedText)
        }
        
        // Set voice
        if !selectedVoiceIdentifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier) {
            utterance.voice = voice
        } else {
            // Fallback to best available
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        
        // Apply settings optimized for natural, human-like speech
        utterance.rate = speechRate
        utterance.pitchMultiplier = speechPitch
        utterance.volume = speechVolume
        
        // Zero delays for immediate, low-latency streaming
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        
        // Use natural prosody, not assistive technology settings
        utterance.prefersAssistiveTechnologySettings = false
        
        currentUtterance = cleanedText
        isSpeaking = true
        speakingProgress = 0.0
        
        onSpeakingStarted?()
        synthesizer.speak(utterance)
    }
    
    // MARK: - SSML Support for Natural Speech
    private func createSSMLUtterance(for text: String) -> AVSpeechUtterance? {
        // Create SSML with natural prosody adjustments
        // SSML allows fine-grained control over speech synthesis
        let escapedText = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        
        // Add natural pauses after punctuation and adjust prosody
        var processedText = escapedText
        
        // Add slight pauses after commas for natural rhythm
        processedText = processedText.replacingOccurrences(of: ",", with: ",<break time=\"150ms\"/>")
        
        // Add medium pauses after colons and semicolons
        processedText = processedText.replacingOccurrences(of: ":", with: ":<break time=\"200ms\"/>")
        processedText = processedText.replacingOccurrences(of: ";", with: ";<break time=\"200ms\"/>")
        
        // Convert speech rate to SSML percentage (0.5 = 100%, 0.25 = 50%, 0.75 = 150%)
        let ratePercent = Int((speechRate / AVSpeechUtteranceDefaultSpeechRate) * 100)
        
        let ssml = """
        <speak>
            <prosody rate="\(ratePercent)%" pitch="\(Int((speechPitch - 1.0) * 100))%">
                \(processedText)
            </prosody>
        </speak>
        """
        
        return AVSpeechUtterance(ssmlRepresentation: ssml)
    }
    
    // MARK: - Text Preprocessing for Natural Speech
    private func preprocessTextForSpeech(_ text: String) -> String {
        var result = text
        
        // Remove markdown formatting
        result = result.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "__", with: "")
        result = result.replacingOccurrences(of: "```", with: "")
        result = result.replacingOccurrences(of: "`", with: "")
        result = result.replacingOccurrences(of: "#", with: "")
        result = result.replacingOccurrences(of: "*", with: "")
        result = result.replacingOccurrences(of: "_", with: "")
        
        // Remove bullet points and list markers
        result = result.replacingOccurrences(of: "- ", with: "")
        result = result.replacingOccurrences(of: "• ", with: "")
        
        // Replace URLs with "link"
        let urlPattern = "https?://[^\\s]+"
        if let regex = try? NSRegularExpression(pattern: urlPattern, options: .caseInsensitive) {
            result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..., in: result), withTemplate: "link")
        }
        
        // Replace email addresses
        let emailPattern = "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        if let regex = try? NSRegularExpression(pattern: emailPattern, options: .caseInsensitive) {
            result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..., in: result), withTemplate: "email address")
        }
        
        // Expand common abbreviations for natural speech
        result = result.replacingOccurrences(of: "e.g.", with: "for example")
        result = result.replacingOccurrences(of: "i.e.", with: "that is")
        result = result.replacingOccurrences(of: "etc.", with: "and so on")
        result = result.replacingOccurrences(of: "vs.", with: "versus")
        result = result.replacingOccurrences(of: "approx.", with: "approximately")
        
        // Clean up excessive whitespace
        result = result.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Speak with Streaming (for LLM responses - low latency)
    func speakStreaming(_ textChunk: String) {
        sentenceBuffer += textChunk
        
        // Extract complete sentences for immediate speaking
        while let (sentence, remaining) = extractCompleteSentence(from: sentenceBuffer) {
            sentenceBuffer = remaining
            if !sentence.trimmingCharacters(in: .whitespaces).isEmpty {
                utteranceQueue.append(sentence)
            }
        }
        
        // If not speaking and we have queued sentences, start
        if !isSpeaking && !utteranceQueue.isEmpty {
            processQueue()
        }
    }
    
    private func extractCompleteSentence(from text: String) -> (sentence: String, remaining: String)? {
        // Find the first sentence delimiter
        guard let range = text.rangeOfCharacter(from: sentenceDelimiters) else {
            return nil
        }
        
        let endIndex = text.index(after: range.lowerBound)
        let sentence = String(text[..<endIndex])
        let remaining = String(text[endIndex...])
        
        return (sentence, remaining)
    }
    
    func flushStreamingBuffer() {
        // Speak any remaining text in buffer
        if !sentenceBuffer.trimmingCharacters(in: .whitespaces).isEmpty {
            utteranceQueue.append(sentenceBuffer)
            sentenceBuffer = ""
        }
        if !isSpeaking && !utteranceQueue.isEmpty {
            processQueue()
        }
    }
    
    private func processQueue() {
        guard !utteranceQueue.isEmpty else { return }
        
        let text = utteranceQueue.removeFirst()
        if !text.isEmpty {
            performSpeak(text)
        }
    }
    
    // MARK: - Control
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        utteranceQueue.removeAll()
        sentenceBuffer = ""  // Clear streaming buffer
        isSpeaking = false
        speakingProgress = 0.0
        currentUtterance = ""
    }
    
    func pause() {
        synthesizer.pauseSpeaking(at: .word)
    }
    
    func resume() {
        synthesizer.continueSpeaking()
    }
    
    // MARK: - Voice Selection
    func selectVoice(_ identifier: String) {
        selectedVoiceIdentifier = identifier
        saveSettings()
    }
    
    // MARK: - Speech Rate Adjustment
    func setSpeechRate(_ rate: Float) {
        // Clamp to valid range
        speechRate = max(AVSpeechUtteranceMinimumSpeechRate, 
                        min(AVSpeechUtteranceMaximumSpeechRate, rate))
        saveSettings()
    }
    
    func setPitch(_ pitch: Float) {
        // Clamp to valid range (0.5 - 2.0)
        speechPitch = max(0.5, min(2.0, pitch))
        saveSettings()
    }
    
    // MARK: - Voice Quality Info
    func getVoiceQualityDescription() -> String {
        guard !selectedVoiceIdentifier.isEmpty,
              let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier) else {
            return "No voice selected"
        }
        
        switch voice.quality {
        case .premium:
            return "Premium quality - Most natural, human-like speech"
        case .enhanced:
            return "Enhanced quality - Clear and natural speech"
        case .default:
            return "Standard quality - Basic speech synthesis"
        @unknown default:
            return "Unknown quality"
        }
    }
    
    func needsPremiumVoiceDownload() -> Bool {
        guard !selectedVoiceIdentifier.isEmpty,
              let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier) else {
            return !hasPremiumVoices
        }
        return voice.quality == .default && !hasPremiumVoices
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension SpeechSynthesisService: AVSpeechSynthesizerDelegate {
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = true
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.speakingProgress = 1.0
            
            // Check if there's more in the queue
            if !self.utteranceQueue.isEmpty {
                self.processQueue()
            } else {
                self.isSpeaking = false
                self.currentUtterance = ""
                self.onSpeakingFinished?()
            }
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentUtterance = ""
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in
            let totalLength = Float(utterance.speechString.count)
            let currentPosition = Float(characterRange.location + characterRange.length)
            self.speakingProgress = currentPosition / totalLength
            
            // Extract current word
            if let range = Range(characterRange, in: utterance.speechString) {
                let word = String(utterance.speechString[range])
                self.onWordSpoken?(word)
            }
        }
    }
}

// MARK: - Voice Option Model
struct VoiceOption: Identifiable, Hashable {
    let id: String
    let identifier: String
    let name: String
    let language: String
    let quality: String
    let isDefault: Bool
    let isPersonal: Bool
    
    init(identifier: String, name: String, language: String, quality: String, isDefault: Bool, isPersonal: Bool = false) {
        self.id = identifier
        self.identifier = identifier
        self.name = name
        self.language = language
        self.quality = quality
        self.isDefault = isDefault
        self.isPersonal = isPersonal
    }
    
    var displayName: String {
        if isPersonal {
            return "\(name) ⭐️"
        }
        return "\(name) (\(quality))"
    }
    
    var qualityIcon: String {
        switch quality {
        case "Premium": return "star.fill"
        case "Enhanced": return "star.leadinghalf.filled"
        case "Personal": return "person.fill"
        default: return "star"
        }
    }
}
