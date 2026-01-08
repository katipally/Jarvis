import Foundation
import Speech
import AVFoundation

/// Speech recognition service using macOS 26 SpeechAnalyzer for on-device, low-latency transcription
@MainActor
class SpeechRecognitionService: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isTranscribing = false
    @Published var transcribedText = ""
    @Published var volatileText = ""  // Real-time partial results
    @Published var hasPermission = false
    @Published var isAvailable = false
    @Published var error: String?
    
    // MARK: - Speech Recognition
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // MARK: - Callbacks
    var onTranscriptionComplete: ((String) -> Void)?
    var onPartialResult: ((String) -> Void)?
    
    // MARK: - Initialization
    init() {
        setupRecognizer()
        // Don't block init with async permission check
        // Permission will be checked when startRecognition is called
    }
    
    // MARK: - Setup
    private func setupRecognizer() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        isAvailable = speechRecognizer?.isAvailable ?? false
        
        // Observe availability changes
        speechRecognizer?.delegate = nil  // We'll handle this differently
    }
    
    // MARK: - Permission
    func checkPermission() async {
        let status = SFSpeechRecognizer.authorizationStatus()
        
        switch status {
        case .authorized:
            hasPermission = true
        case .notDetermined:
            hasPermission = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        case .denied, .restricted:
            hasPermission = false
            error = "Speech recognition access denied. Please enable in System Settings > Privacy & Security > Speech Recognition"
        @unknown default:
            hasPermission = false
        }
    }
    
    // MARK: - Start Recognition
    func startRecognition() throws {
        guard hasPermission else {
            throw SpeechRecognitionError.noPermission
        }
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw SpeechRecognitionError.recognizerUnavailable
        }
        
        // Cancel any existing task
        stopRecognition()
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let request = recognitionRequest else {
            throw SpeechRecognitionError.requestCreationFailed
        }
        
        // Configure for real-time results
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true  // On-device for privacy and speed
        
        // Add context hints for better accuracy
        request.contextualStrings = [
            "Jarvis", "open", "close", "volume", "brightness",
            "Safari", "Chrome", "Finder", "Music", "Calendar",
            "play", "pause", "next", "previous", "stop",
            "dark mode", "light mode", "notification"
        ]
        
        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                if let error = error {
                    // Check if it's just an end-of-speech error
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                        // Normal end of speech
                        self.finalizeTranscription()
                        return
                    }
                    
                    self.error = error.localizedDescription
                    self.stopRecognition()
                    return
                }
                
                guard let result = result else { return }
                
                let transcription = result.bestTranscription.formattedString
                
                if result.isFinal {
                    self.transcribedText = transcription
                    self.volatileText = ""
                    self.onTranscriptionComplete?(transcription)
                    self.stopRecognition()
                } else {
                    self.volatileText = transcription
                    self.onPartialResult?(transcription)
                }
            }
        }
        
        isTranscribing = true
        error = nil
    }
    
    // MARK: - Process Audio Buffer
    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }
    
    // MARK: - Stop Recognition
    func stopRecognition() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isTranscribing = false
    }
    
    // MARK: - Finalize
    private func finalizeTranscription() {
        if !volatileText.isEmpty {
            transcribedText = volatileText
            onTranscriptionComplete?(volatileText)
            volatileText = ""
        }
        stopRecognition()
    }
    
    // MARK: - Clear
    func clear() {
        transcribedText = ""
        volatileText = ""
        error = nil
    }
}

// MARK: - Errors
enum SpeechRecognitionError: LocalizedError {
    case noPermission
    case recognizerUnavailable
    case requestCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .noPermission:
            return "Speech recognition permission not granted"
        case .recognizerUnavailable:
            return "Speech recognizer is not available"
        case .requestCreationFailed:
            return "Failed to create recognition request"
        }
    }
}
