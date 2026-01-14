import Foundation

@MainActor
class StreamingService: ObservableObject {
    @Published var currentMessage: String = ""
    @Published var currentReasoning: [String] = []
    @Published var isStreaming: Bool = false
    @Published var error: String?
    @Published var tokenCount: Int = 0
    
    private var streamTask: Task<Void, Never>?
    
    func sendMessage(_ message: String, fileIds: [String] = [], conversationHistory: [[String: String]] = []) async {
        isStreaming = true
        currentMessage = ""
        currentReasoning = []
        error = nil
        tokenCount = 0
        
        streamTask = Task {
            await performStreaming(message: message, fileIds: fileIds, conversationHistory: conversationHistory)
        }
        
        await streamTask?.value
        isStreaming = false
    }
    
    func cancelStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }
    
    private func performStreaming(message: String, fileIds: [String], conversationHistory: [[String: String]] = []) async {
        guard let url = URL(string: "\(Config.apiBaseURL)/chat/stream") else {
            error = "Invalid URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        
        // Build full message history including conversation context
        var allMessages = conversationHistory
        allMessages.append(["role": "user", "content": message])
        
        let requestBody: [String: Any] = [
            "messages": allMessages,
            "file_ids": fileIds,
            "include_reasoning": true
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            
            // Check HTTP status
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 429 {
                    self.error = "Rate limit exceeded. Please wait a moment and try again."
                    return
                } else if httpResponse.statusCode >= 400 {
                    self.error = "Server error (\(httpResponse.statusCode)). Please try again."
                    return
                }
            }
            
            for try await line in bytes.lines {
                if Task.isCancelled { break }
                
                if line.hasPrefix("data: ") {
                    let data = String(line.dropFirst(6))
                    await handleStreamEvent(data)
                }
            }
        } catch is CancellationError {
            // Task was cancelled, not an error
        } catch {
            var errorMessage = error.localizedDescription
            
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet:
                    errorMessage = "No internet connection. Please check your network settings."
                case .timedOut:
                    errorMessage = "Request timed out. Please try again."
                case .cannotFindHost, .cannotConnectToHost:
                    errorMessage = "Cannot connect to server. Please ensure the backend is running."
                default:
                    errorMessage = "Connection error: \(urlError.localizedDescription)"
                }
            }
            
            self.error = errorMessage
        }
    }
    
    private func handleStreamEvent(_ data: String) async {
        guard let eventData = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
            return
        }
        
        guard let type = json["type"] as? String else { return }
        
        switch type {
        case "content":
            if let content = json["content"] as? String {
                currentMessage += content
            }
        case "reasoning":
            if let reasoning = json["content"] as? String {
                currentReasoning.append(reasoning)
            }
        case "tool":
            if let toolName = json["tool_name"] as? String {
                currentReasoning.append("Using tool: \(toolName)")
            }
        case "error":
            if let errorMsg = json["error"] as? String {
                error = errorMsg
            }
        case "done":
            // Extract token count if available
            if let count = json["token_count"] as? Int {
                tokenCount = count
            } else if let usage = json["usage"] as? [String: Any],
                      let total = usage["total_tokens"] as? Int {
                tokenCount = total
            } else {
                // Estimate tokens (roughly 4 chars per token)
                tokenCount = (currentMessage.count + 100) / 4
            }
        default:
            break
        }
    }
}
