import Foundation
import AVFoundation
import Combine

/// Audio pipeline for microphone input, level metering, and adaptive voice activity detection
@MainActor
class AudioPipeline: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0  // 0.0 to 1.0 normalized
    @Published var isSpeechDetected = false
    @Published var hasPermission = false
    @Published var error: String?
    @Published var isCalibrated = false
    @Published var calibrationProgress: Float = 0.0
    @Published var currentNoiseFloor: Float = 0.0  // For debugging/UI
    
    // MARK: - Audio Engine
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    
    // MARK: - Adaptive VAD Configuration
    // Dynamic noise floor that adapts to environment
    private var noiseFloor: Float = 0.01            // Baseline ambient noise level
    private var userVoiceLevel: Float = 0.0         // Learned user voice level
    private var noiseFloorSamples: [Float] = []    // Samples for calculating noise floor
    private var voiceSamples: [Float] = []         // Samples of user's voice level
    private let noiseFloorWindowSize = 50          // ~1 second of samples
    private let noiseFloorUpdateRate: Float = 0.02 // Faster adaptation
    
    // Speech detection thresholds (relative to noise floor) - tuned for responsiveness
    private let speechThresholdMultiplier: Float = 1.8  // Speech must be 1.8x noise floor (more sensitive)
    private let speechContinueMultiplier: Float = 1.3   // Continue threshold (lower hysteresis)
    private let interruptionMultiplier: Float = 2.0     // Interruption threshold (more sensitive)
    
    // Absolute minimum/maximum thresholds (safety bounds)
    private let absoluteMinThreshold: Float = 0.008     // Slightly higher minimum
    private let absoluteMaxThreshold: Float = 0.15      // Higher max for loud environments
    
    // Timing parameters - optimized for conversational flow
    private let silenceTimeout: TimeInterval = 0.8      // Faster end-of-speech detection
    private let minSpeechDuration: TimeInterval = 0.15  // Shorter minimum speech
    private let maxSpeechDuration: TimeInterval = 30.0  // Shorter max for conversation
    private let autoCalibrationTime: TimeInterval = 0.5 // Faster auto calibration
    private let manualCalibrationTime: TimeInterval = 2.0 // Shorter manual calibration
    
    // State tracking
    private var lastSpeechTime: Date?
    private var speechStartTime: Date?
    private var recordingStartTime: Date?
    private var calibrationStartTime: Date?
    private var silenceCheckTimer: Timer?
    private var isInSpeakingMode = false
    private var isCalibrating = true
    private var isManualCalibration = false
    private var consecutiveSpeechFrames = 0
    private var consecutiveSilenceFrames = 0
    private var interruptionCooldown: Date?
    private let interruptionCooldownDuration: TimeInterval = 0.3  // Shorter cooldown
    
    // Frame counting for robust detection - balanced for speed and accuracy
    private let minSpeechFrames = 2    // Need 2 consecutive frames to start speech
    private let minSilenceFrames = 6   // Need 6 consecutive frames of silence
    
    // Audio level history for smoothing
    private var levelHistory: [Float] = []
    private let levelHistorySize = 8
    
    // MARK: - Audio Buffer
    private var audioBuffers: [AVAudioPCMBuffer] = []
    
    // MARK: - Callbacks
    var onSpeechStart: (() -> Void)?
    var onSpeechEnd: (([AVAudioPCMBuffer]) -> Void)?
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    var onInterruption: (() -> Void)?
    
    // MARK: - Set Speaking Mode (for interruption detection)
    func setSpeakingMode(_ speaking: Bool) {
        isInSpeakingMode = speaking
    }
    
    // MARK: - Initialization
    init() {
        // Permission will be checked when startRecording is called
    }
    
    // MARK: - Permission
    func checkPermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            hasPermission = true
        case .notDetermined:
            hasPermission = await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            hasPermission = false
            error = "Microphone access denied. Please enable in System Settings > Privacy & Security > Microphone"
        @unknown default:
            hasPermission = false
        }
    }
    
    // MARK: - Setup Audio Engine
    private func setupAudioEngine() throws {
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            throw AudioPipelineError.engineCreationFailed
        }
        
        inputNode = engine.inputNode
        guard let inputNode = inputNode else {
            throw AudioPipelineError.inputNodeUnavailable
        }
        
        let format = inputNode.outputFormat(forBus: 0)
        
        // Validate format
        guard format.sampleRate > 0 && format.channelCount > 0 else {
            throw AudioPipelineError.invalidAudioFormat
        }
        
        // Install tap for audio processing
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            Task { @MainActor [weak self] in
                self?.processAudioBuffer(buffer)
            }
        }
        
        engine.prepare()
    }
    
    // MARK: - Process Audio Buffer
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Calculate RMS level
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }
        
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        
        let rms = sqrt(sum / Float(frameLength))
        
        // Add to level history for smoothing
        levelHistory.append(rms)
        if levelHistory.count > levelHistorySize {
            levelHistory.removeFirst()
        }
        
        // Calculate smoothed level
        let smoothedRms = levelHistory.reduce(0, +) / Float(levelHistory.count)
        let normalizedLevel = min(1.0, max(0, smoothedRms * 10))
        
        // Update published audio level for UI
        self.audioLevel = normalizedLevel
        self.currentNoiseFloor = noiseFloor
        
        // CALIBRATION PHASE
        if isCalibrating {
            processCalibration(smoothedRms: smoothedRms)
            return
        }
        
        // ADAPTIVE NOISE FLOOR: Slowly update during confirmed silence
        if !isSpeechDetected && consecutiveSilenceFrames > minSilenceFrames * 2 {
            let currentSpeechThreshold = calculateSpeechThreshold()
            if smoothedRms < currentSpeechThreshold * 0.6 {
                noiseFloor = noiseFloor * (1 - noiseFloorUpdateRate) + smoothedRms * noiseFloorUpdateRate
                noiseFloor = max(absoluteMinThreshold / speechThresholdMultiplier, noiseFloor)
            }
        }
        
        // Calculate dynamic thresholds based on noise floor
        let speechThreshold = calculateSpeechThreshold()
        let continueThreshold = calculateContinueThreshold()
        let interruptThreshold = calculateInterruptionThreshold()
        
        // INTERRUPTION DETECTION with cooldown
        if isInSpeakingMode {
            if let cooldown = interruptionCooldown, Date().timeIntervalSince(cooldown) < interruptionCooldownDuration {
                // In cooldown period, ignore interruptions
            } else if smoothedRms > interruptThreshold && consecutiveSpeechFrames >= 2 {
                // Need 2 consecutive loud frames to confirm interruption
                interruptionCooldown = Date()
                onInterruption?()
                return
            }
        }
        
        // Determine if this frame contains speech (with hysteresis)
        let currentThreshold = isSpeechDetected ? continueThreshold : speechThreshold
        let isSpeechFrame = smoothedRms > currentThreshold
        
        if isSpeechFrame {
            consecutiveSpeechFrames += 1
            consecutiveSilenceFrames = 0
            
            // Track voice level for profile
            if isSpeechDetected {
                voiceSamples.append(smoothedRms)
                if voiceSamples.count > 50 {
                    voiceSamples.removeFirst()
                    // Update learned user voice level
                    let avgVoice = voiceSamples.reduce(0, +) / Float(voiceSamples.count)
                    userVoiceLevel = userVoiceLevel * 0.9 + avgVoice * 0.1
                }
            }
            
            // START of speech - need consecutive frames to confirm
            if !isSpeechDetected && consecutiveSpeechFrames >= minSpeechFrames {
                speechStartTime = Date()
                isSpeechDetected = true
                lastSpeechTime = Date()
                startSilenceTimer()
                onSpeechStart?()
            } else if isSpeechDetected {
                // CONTINUING speech
                lastSpeechTime = Date()
            }
            
            // Store and forward buffer
            if isSpeechDetected {
                audioBuffers.append(buffer)
                onAudioBuffer?(buffer)
            }
            
        } else {
            consecutiveSilenceFrames += 1
            consecutiveSpeechFrames = 0
            
            if isSpeechDetected {
                // Still forward buffer during brief pauses
                audioBuffers.append(buffer)
                onAudioBuffer?(buffer)
            }
        }
        
        // Safety: Check for max speech duration
        if isSpeechDetected, let startTime = speechStartTime {
            if Date().timeIntervalSince(startTime) > maxSpeechDuration {
                endSpeechDetection()
            }
        }
    }
    
    // MARK: - Calibration Processing
    private func processCalibration(smoothedRms: Float) {
        guard let startTime = calibrationStartTime else {
            calibrationStartTime = Date()
            return
        }
        
        let calibrationDuration = isManualCalibration ? manualCalibrationTime : autoCalibrationTime
        let elapsed = Date().timeIntervalSince(startTime)
        calibrationProgress = Float(min(1.0, elapsed / calibrationDuration))
        
        // Collect samples
        noiseFloorSamples.append(smoothedRms)
        
        // During manual calibration, if user speaks (high level), collect voice samples
        if isManualCalibration && smoothedRms > 0.03 {
            voiceSamples.append(smoothedRms)
        }
        
        // Complete calibration
        if elapsed >= calibrationDuration {
            finishCalibration()
        }
    }
    
    private func finishCalibration() {
        if !noiseFloorSamples.isEmpty {
            // Sort and use percentile for noise floor (25th percentile = ambient noise)
            let sorted = noiseFloorSamples.sorted()
            let percentileIndex = max(0, sorted.count / 4)  // 25th percentile
            let calculatedFloor = sorted[min(percentileIndex, sorted.count - 1)]
            noiseFloor = max(absoluteMinThreshold / speechThresholdMultiplier, calculatedFloor)
            
            // If we have voice samples, calculate user voice level
            if !voiceSamples.isEmpty {
                let sortedVoice = voiceSamples.sorted()
                let voicePercentileIndex = sortedVoice.count * 3 / 4  // 75th percentile
                userVoiceLevel = sortedVoice[min(voicePercentileIndex, sortedVoice.count - 1)]
            }
        }
        
        noiseFloorSamples.removeAll()
        isCalibrating = false
        isManualCalibration = false
        isCalibrated = true
        calibrationProgress = 1.0
        calibrationStartTime = nil
        
        // If this was manual calibration, stop recording after calibration completes
        // The next startRecording will use the calibrated values
        if isRecording && !isSpeechDetected {
            // Keep recording for hands-free mode but reset state
            consecutiveSpeechFrames = 0
            consecutiveSilenceFrames = 0
        }
    }
    
    // MARK: - Dynamic Threshold Calculations
    private func calculateSpeechThreshold() -> Float {
        let threshold = noiseFloor * speechThresholdMultiplier
        return min(absoluteMaxThreshold, max(absoluteMinThreshold, threshold))
    }
    
    private func calculateContinueThreshold() -> Float {
        let threshold = noiseFloor * speechContinueMultiplier
        return min(absoluteMaxThreshold, max(absoluteMinThreshold * 0.8, threshold))
    }
    
    private func calculateInterruptionThreshold() -> Float {
        let threshold = noiseFloor * interruptionMultiplier
        return min(absoluteMaxThreshold, max(absoluteMinThreshold, threshold))
    }
    
    // MARK: - Silence Timer (critical for end-of-speech detection)
    private func startSilenceTimer() {
        // Cancel any existing timer
        silenceCheckTimer?.invalidate()
        
        // Start a repeating timer that checks for silence
        silenceCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkForSilenceTimeout()
            }
        }
    }
    
    private func stopSilenceTimer() {
        silenceCheckTimer?.invalidate()
        silenceCheckTimer = nil
    }
    
    private func checkForSilenceTimeout() {
        guard isSpeechDetected,
              let lastSpeech = lastSpeechTime,
              let startTime = speechStartTime else {
            return
        }
        
        let silenceDuration = Date().timeIntervalSince(lastSpeech)
        let speechDuration = Date().timeIntervalSince(startTime)
        
        // End speech if we've had enough silence AND meaningful speech
        if silenceDuration >= silenceTimeout && speechDuration >= minSpeechDuration {
            endSpeechDetection()
        }
    }
    
    private func endSpeechDetection() {
        // Stop the silence timer
        stopSilenceTimer()
        
        isSpeechDetected = false
        speechStartTime = nil
        lastSpeechTime = nil
        consecutiveSpeechFrames = 0
        consecutiveSilenceFrames = 0
        
        let buffers = audioBuffers
        audioBuffers.removeAll()
        
        if !buffers.isEmpty {
            onSpeechEnd?(buffers)
        }
    }
    
    // MARK: - Start/Stop Recording
    func startRecording() async throws {
        if !hasPermission {
            await checkPermission()
            if !hasPermission {
                throw AudioPipelineError.noPermission
            }
        }
        
        guard !isRecording else { return }
        
        try setupAudioEngine()
        
        guard let engine = audioEngine else {
            throw AudioPipelineError.engineCreationFailed
        }
        
        try engine.start()
        isRecording = true
        error = nil
        
        // Reset state for new recording session
        audioBuffers.removeAll()
        levelHistory.removeAll()
        noiseFloorSamples.removeAll()
        voiceSamples.removeAll()
        consecutiveSpeechFrames = 0
        consecutiveSilenceFrames = 0
        isCalibrating = true
        isManualCalibration = false
        isCalibrated = false
        calibrationProgress = 0.0
        calibrationStartTime = Date()
        recordingStartTime = Date()
        interruptionCooldown = nil
        noiseFloor = 0.005  // Reset to default
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        // Stop the silence timer
        stopSilenceTimer()
        
        // End any ongoing speech detection
        if isSpeechDetected {
            endSpeechDetection()
        }
        
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        
        isRecording = false
        audioLevel = 0
        isSpeechDetected = false
        levelHistory.removeAll()
    }
    
    // MARK: - Manual Trigger (Push-to-Talk)
    func startManualRecording() async throws {
        try await startRecording()
        // Skip calibration for push-to-talk
        isCalibrating = false
        isCalibrated = true
        calibrationProgress = 1.0
        isSpeechDetected = true
        onSpeechStart?()
    }
    
    func stopManualRecording() {
        if isSpeechDetected {
            endSpeechDetection()
        }
        stopRecording()
    }
    
    // MARK: - Manual Calibration
    /// Start manual calibration - user should speak normally for 3 seconds
    /// This learns both the ambient noise floor and the user's voice level
    func startManualCalibration() async throws {
        if !hasPermission {
            await checkPermission()
            if !hasPermission {
                throw AudioPipelineError.noPermission
            }
        }
        
        // Stop any existing recording
        if isRecording {
            stopRecording()
        }
        
        try setupAudioEngine()
        
        guard let engine = audioEngine else {
            throw AudioPipelineError.engineCreationFailed
        }
        
        try engine.start()
        isRecording = true
        error = nil
        
        // Reset calibration state
        audioBuffers.removeAll()
        levelHistory.removeAll()
        noiseFloorSamples.removeAll()
        voiceSamples.removeAll()
        consecutiveSpeechFrames = 0
        consecutiveSilenceFrames = 0
        isCalibrating = true
        isManualCalibration = true  // Enable manual calibration mode
        isCalibrated = false
        calibrationProgress = 0.0
        calibrationStartTime = Date()
        recordingStartTime = Date()
        noiseFloor = 0.005
    }
    
    /// Cancel manual calibration
    func cancelCalibration() {
        isCalibrating = false
        isManualCalibration = false
        calibrationProgress = 0.0
        noiseFloorSamples.removeAll()
        voiceSamples.removeAll()
        stopRecording()
    }
    
    /// Force recalibration on next recording start
    func resetCalibration() {
        isCalibrated = false
        noiseFloor = 0.005
        userVoiceLevel = 0.0
        voiceSamples.removeAll()
    }
    
    deinit {
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
    }
}

// MARK: - Errors
enum AudioPipelineError: LocalizedError {
    case noPermission
    case engineCreationFailed
    case inputNodeUnavailable
    case invalidAudioFormat
    
    var errorDescription: String? {
        switch self {
        case .noPermission:
            return "Microphone permission not granted"
        case .engineCreationFailed:
            return "Failed to create audio engine"
        case .inputNodeUnavailable:
            return "Audio input not available"
        case .invalidAudioFormat:
            return "Invalid audio format"
        }
    }
}
