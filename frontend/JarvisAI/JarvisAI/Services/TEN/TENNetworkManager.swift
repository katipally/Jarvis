import Foundation
import Combine

/// WebSocket message types for TEN conversation protocol
enum TENMessageType: String, Codable {
    case text
    case interrupt
    case ping
    case pong
    case clear
    case end
    case textStart = "text_start"
    case textDelta = "text_delta"
    case textDone = "text_done"
    case sentenceEnd = "sentence_end"
    case interrupted
    case cleared
    case error
}

/// Incoming message from server
struct TENServerMessage: Codable {
    let type: String
    let content: String?
    let fullText: String?
    let sentence: String?
    let message: String?
    
    enum CodingKeys: String, CodingKey {
        case type
        case content
        case fullText = "full_text"
        case sentence
        case message
    }
}

/// Outgoing message to server
struct TENClientMessage: Codable {
    let type: String
    let content: String?
    let sessionId: String?
    
    enum CodingKeys: String, CodingKey {
        case type
        case content
        case sessionId = "session_id"
    }
}

/// Connection state for the WebSocket
enum TENConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

/// TEN Network Manager - Handles WebSocket communication with the TEN Agent backend
@MainActor
class TENNetworkManager: NSObject, ObservableObject {
    static let shared = TENNetworkManager()
    
    // MARK: - Published Properties
    @Published var connectionState: TENConnectionState = .disconnected
    @Published var isReceivingResponse = false
    
    // MARK: - Callbacks
    var onResponseStart: (() -> Void)?
    var onResponseChunk: ((String) -> Void)?
    var onSentenceComplete: ((String) -> Void)?
    var onResponseComplete: ((String) -> Void)?
    var onInterrupted: (() -> Void)?
    var onError: ((String) -> Void)?
    
    // MARK: - Private Properties
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var pingTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private var sessionId: String = UUID().uuidString
    
    // MARK: - Configuration
    private let serverURL: URL
    
    override init() {
        // Use localhost for development
        self.serverURL = URL(string: "ws://127.0.0.1:8000/api/ws/conversation")!
        super.init()
        
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }
    
    // MARK: - Connection Management
    
    func connect() {
        guard connectionState != .connected && connectionState != .connecting else { return }
        
        connectionState = .connecting
        webSocketTask = urlSession.webSocketTask(with: serverURL)
        webSocketTask?.resume()
        
        startReceiving()
        startPingTimer()
    }
    
    func disconnect() {
        stopPingTimer()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
        isReceivingResponse = false
    }
    
    func reconnect() {
        disconnect()
        
        guard reconnectAttempts < maxReconnectAttempts else {
            connectionState = .error("Max reconnection attempts reached")
            return
        }
        
        reconnectAttempts += 1
        let delay = Double(reconnectAttempts) * 0.5
        
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            connect()
        }
    }
    
    // MARK: - Message Sending
    
    func sendText(_ text: String) async throws {
        guard connectionState == .connected else {
            throw TENError.notConnected
        }
        
        let message = TENClientMessage(type: "text", content: text, sessionId: sessionId)
        let data = try JSONEncoder().encode(message)
        let string = String(data: data, encoding: .utf8)!
        
        try await webSocketTask?.send(.string(string))
        isReceivingResponse = true
    }
    
    func sendInterrupt() async throws {
        guard connectionState == .connected else { return }
        
        let message = TENClientMessage(type: "interrupt", content: nil, sessionId: nil)
        let data = try JSONEncoder().encode(message)
        let string = String(data: data, encoding: .utf8)!
        
        try await webSocketTask?.send(.string(string))
    }
    
    func clearHistory() async throws {
        guard connectionState == .connected else { return }
        
        let message = TENClientMessage(type: "clear", content: nil, sessionId: sessionId)
        let data = try JSONEncoder().encode(message)
        let string = String(data: data, encoding: .utf8)!
        
        try await webSocketTask?.send(.string(string))
    }
    
    func newSession() {
        sessionId = UUID().uuidString
    }
    
    // MARK: - Message Receiving
    
    private func startReceiving() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self?.handleMessage(message)
                    self?.startReceiving() // Continue receiving
                    
                case .failure(let error):
                    self?.handleError(error)
                }
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
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
              let message = try? JSONDecoder().decode(TENServerMessage.self, from: data) else {
            return
        }
        
        switch message.type {
        case "text_start":
            onResponseStart?()
            
        case "text_delta":
            if let content = message.content {
                onResponseChunk?(content)
            }
            
        case "sentence_end":
            if let sentence = message.sentence {
                onSentenceComplete?(sentence)
            }
            
        case "text_done":
            isReceivingResponse = false
            if let fullText = message.fullText {
                onResponseComplete?(fullText)
            }
            
        case "interrupted":
            isReceivingResponse = false
            onInterrupted?()
            
        case "error":
            isReceivingResponse = false
            if let errorMessage = message.message {
                onError?(errorMessage)
            }
            
        case "pong":
            // Ping response received
            break
            
        case "cleared":
            // History cleared
            break
            
        default:
            break
        }
    }
    
    private func handleError(_ error: Error) {
        connectionState = .error(error.localizedDescription)
        isReceivingResponse = false
        onError?(error.localizedDescription)
        
        // Attempt reconnection
        reconnect()
    }
    
    // MARK: - Ping/Pong
    
    private func startPingTimer() {
        stopPingTimer()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                try? await self?.sendPing()
            }
        }
    }
    
    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }
    
    private func sendPing() async throws {
        guard connectionState == .connected else { return }
        
        let message = TENClientMessage(type: "ping", content: nil, sessionId: nil)
        let data = try JSONEncoder().encode(message)
        let string = String(data: data, encoding: .utf8)!
        
        try await webSocketTask?.send(.string(string))
    }
}

// MARK: - URLSessionWebSocketDelegate

extension TENNetworkManager: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            connectionState = .connected
            reconnectAttempts = 0
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            connectionState = .disconnected
            isReceivingResponse = false
        }
    }
}

// MARK: - Errors

enum TENError: Error, LocalizedError {
    case notConnected
    case encodingError
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to server"
        case .encodingError:
            return "Failed to encode message"
        case .serverError(let message):
            return message
        }
    }
}
