import Foundation
import Speech
import AVFoundation
import Combine

/// Voice Activity Detection state
enum VADState: Equatable {
    case idle
    case listening
    case speaking
    case processing
}

/// TEN Speech Service - Handles native Apple STT with VAD
@MainActor
class TENSpeechService: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isListening = false
    @Published var vadState: VADState = .idle
    @Published var currentTranscript = ""
    @Published var audioLevel: Float = 0.0
    @Published var isAuthorized = false
    
    // MARK: - Callbacks
    var onSpeechStart: (() -> Void)?
    var onSpeechEnd: ((String) -> Void)?
    var onPartialTranscript: ((String) -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    
    // MARK: - Private Properties
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    // VAD Configuration
    private var silenceTimer: Timer?
    private var speechStartTime: Date?
    private let silenceThreshold: TimeInterval = 0.8  // End speech after 0.8s silence
    private let minSpeechDuration: TimeInterval = 0.2
    private var lastSpeechTime: Date?
    private var hasDetectedSpeech = false
    
    // Audio level tracking
    private var levelHistory: [Float] = []
    private let levelHistorySize = 10
    private var noiseFloor: Float = 0.01
    private let speechThreshold: Float = 0.02
    
    override init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        super.init()
        
        requestAuthorization()
    }
    
    // MARK: - Authorization
    
    private func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.isAuthorized = (status == .authorized)
            }
        }
    }
    
    // MARK: - Recording Control
    
    func startListening() async throws {
        guard isAuthorized else {
            throw SpeechError.notAuthorized
        }
        
        guard !isListening else { return }
        
        // Reset state
        currentTranscript = ""
        hasDetectedSpeech = false
        speechStartTime = nil
        lastSpeechTime = nil
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechError.requestCreationFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.addsPunctuation = true
        
        // Configure audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            self?.processAudioLevel(buffer: buffer)
        }
        
        // Start recognition
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognitionResult(result, error: error)
            }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        isListening = true
        vadState = .listening
        
        // Start silence detection timer
        startSilenceDetection()
    }
    
    func stopListening() {
        guard isListening else { return }
        
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
        
        isListening = false
        vadState = .idle
        audioLevel = 0.0
        
        // Deliver final transcript if we had speech
        if hasDetectedSpeech && !currentTranscript.isEmpty {
            onSpeechEnd?(currentTranscript)
        }
    }
    
    // MARK: - Recognition Handling
    
    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            // Ignore cancellation errors
            if (error as NSError).code != 1 {
                print("Recognition error: \(error)")
            }
            return
        }
        
        guard let result = result else { return }
        
        let transcript = result.bestTranscription.formattedString
        
        if !transcript.isEmpty {
            // Speech detected
            if !hasDetectedSpeech {
                hasDetectedSpeech = true
                speechStartTime = Date()
                vadState = .speaking
                onSpeechStart?()
            }
            
            lastSpeechTime = Date()
            currentTranscript = transcript
            onPartialTranscript?(transcript)
        }
        
        if result.isFinal {
            stopListening()
        }
    }
    
    // MARK: - Audio Level Processing
    
    private func processAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        
        // Calculate RMS
        var sum: Float = 0
        for i in 0..<frameLength {
            sum += channelData[i] * channelData[i]
        }
        let rms = sqrt(sum / Float(frameLength))
        
        // Smooth the level
        levelHistory.append(rms)
        if levelHistory.count > levelHistorySize {
            levelHistory.removeFirst()
        }
        let smoothedLevel = levelHistory.reduce(0, +) / Float(levelHistory.count)
        
        Task { @MainActor in
            self.audioLevel = min(1.0, smoothedLevel * 10)
            self.onAudioLevel?(self.audioLevel)
            
            // Update VAD based on level
            if smoothedLevel > self.speechThreshold && self.vadState == .listening {
                self.lastSpeechTime = Date()
            }
        }
    }
    
    // MARK: - Silence Detection
    
    private func startSilenceDetection() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForSilence()
            }
        }
    }
    
    private func checkForSilence() {
        guard isListening, hasDetectedSpeech else { return }
        
        guard let lastSpeech = lastSpeechTime else { return }
        
        let silenceDuration = Date().timeIntervalSince(lastSpeech)
        
        if silenceDuration >= silenceThreshold {
            // Silence detected - end speech
            if let startTime = speechStartTime {
                let speechDuration = Date().timeIntervalSince(startTime)
                if speechDuration >= minSpeechDuration {
                    stopListening()
                }
            }
        }
    }
}

// MARK: - Errors

enum SpeechError: Error, LocalizedError {
    case notAuthorized
    case requestCreationFailed
    case recognitionFailed
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition not authorized"
        case .requestCreationFailed:
            return "Failed to create recognition request"
        case .recognitionFailed:
            return "Speech recognition failed"
        }
    }
}
