import Foundation

/// Streaming service for handling chat responses with unified event schema
@MainActor
class StreamingService: ObservableObject {
    // Content
    @Published var currentMessage: String = ""
    @Published var currentReasoning: [String] = []
    @Published var isStreaming: Bool = false
    @Published var error: String?
    @Published var tokenCount: Int = 0
    
    // Plan support
    @Published var currentPlan: [PlanStep] = []
    @Published var planSummary: String = ""
    @Published var hasPlan: Bool = false
    
    // Intent & Mode
    @Published var detectedIntent: String?
    @Published var intentConfidence: Double = 0
    @Published var currentMode: AgentMode = .reasoning
    
    // Tool tracking
    @Published var activeToolName: String?
    @Published var toolCallCount: Int = 0
    
    private var streamTask: Task<Void, Never>?
    
    /// Send a message with optional file attachments and conversation history
    func sendMessage(
        _ message: String,
        fileIds: [String] = [],
        conversationHistory: [[String: String]] = [],
        mode: AgentMode = .reasoning,
        conversationId: String? = nil
    ) async {
        // Reset state
        isStreaming = true
        currentMessage = ""
        currentReasoning = []
        currentPlan = []
        planSummary = ""
        hasPlan = false
        error = nil
        tokenCount = 0
        detectedIntent = nil
        intentConfidence = 0
        currentMode = mode
        activeToolName = nil
        toolCallCount = 0
        
        streamTask = Task {
            await performStreaming(
                message: message,
                fileIds: fileIds,
                conversationHistory: conversationHistory,
                mode: mode,
                conversationId: conversationId
            )
        }
        
        await streamTask?.value
        isStreaming = false
        activeToolName = nil
    }
    
    /// Cancel current streaming
    func cancelStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        activeToolName = nil
    }
    
    private func performStreaming(
        message: String,
        fileIds: [String],
        conversationHistory: [[String: String]],
        mode: AgentMode,
        conversationId: String?
    ) async {
        guard let url = URL(string: "\(Config.apiBaseURL)/chat/stream") else {
            error = "Invalid URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        
        // Build full message history
        var allMessages = conversationHistory
        allMessages.append(["role": "user", "content": message])
        
        // Build request body with new unified schema
        var requestBody: [String: Any] = [
            "messages": allMessages,
            "mode": mode.rawValue,
            "include_reasoning": true,
            "include_plan": true
        ]
        
        if !fileIds.isEmpty {
            requestBody["file_ids"] = fileIds
        }
        
        if let conversationId = conversationId {
            requestBody["conversation_id"] = conversationId
        }
        
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
            
            // Process stream
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
            self.error = formatError(error)
        }
    }
    
    private func handleStreamEvent(_ data: String) async {
        guard let eventData = data.data(using: .utf8) else { return }
        
        // Try to decode as StreamEvent
        do {
            let event = try JSONDecoder().decode(StreamEvent.self, from: eventData)
            await processEvent(event)
        } catch {
            // Fallback to manual JSON parsing
            guard let json = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
                  let type = json["type"] as? String else {
                return
            }
            await processLegacyEvent(type: type, json: json)
        }
    }
    
    private func processEvent(_ event: StreamEvent) async {
        switch event.type {
        case "content":
            // Text content chunk
            if let text = event.text ?? event.content {
                currentMessage += text
            }
            
        case "reasoning":
            // Reasoning/thinking step
            if let content = event.content {
                currentReasoning.append(content)
            }
            
        case "thinking":
            // Extended thinking (chain of thought)
            if let content = event.content {
                // Could display differently from reasoning
                currentReasoning.append("💭 \(content)")
            }
            
        case "intent":
            // Intent classification result
            if let intent = event.intent {
                detectedIntent = intent
            }
            if let confidence = event.confidence {
                intentConfidence = confidence
            }
            
        case "mode":
            // Mode selection
            if let modeStr = event.mode, let mode = AgentMode(rawValue: modeStr) {
                currentMode = mode
            }
            
        case "plan":
            // Full plan received
            if let steps = event.steps {
                currentPlan = steps.map { $0.toPlanStep() }
                hasPlan = true
            }
            if let summary = event.summary {
                planSummary = summary
            }
            
        case "plan_step_update":
            // Plan step status update
            if let stepId = event.stepId, let statusStr = event.status {
                updatePlanStep(
                    id: stepId,
                    status: PlanStepStatus(rawValue: statusStr) ?? .pending,
                    result: event.result,
                    error: event.error
                )
            }
            
        case "tool":
            // Tool call started
            if let toolName = event.toolName {
                activeToolName = toolName
                toolCallCount += 1
                currentReasoning.append("🔧 Using tool: \(toolName)")
            }
            
        case "tool_result":
            // Tool execution completed
            activeToolName = nil
            
        case "error":
            // Error event
            if let errorMsg = event.error {
                error = errorMsg
            }
            
        case "done":
            // Stream completion
            if let tokens = event.tokens {
                tokenCount = tokens.effectiveTotal
            } else if let count = event.tokenCount {
                tokenCount = count
            }
            
            // Mark all running plan steps as completed (replace array for UI update)
            var finalPlan = currentPlan
            for i in finalPlan.indices where finalPlan[i].status == .running {
                finalPlan[i].status = .completed
            }
            currentPlan = finalPlan
            
        default:
            break
        }
    }
    
    /// Fallback for legacy event format
    private func processLegacyEvent(type: String, json: [String: Any]) async {
        switch type {
        case "content":
            if let content = json["content"] as? String {
                currentMessage += content
            } else if let text = json["text"] as? String {
                currentMessage += text
            }
            
        case "reasoning":
            if let reasoning = json["content"] as? String {
                currentReasoning.append(reasoning)
            }
            
        case "tool":
            if let toolName = json["tool_name"] as? String {
                activeToolName = toolName
                toolCallCount += 1
                currentReasoning.append("🔧 Using tool: \(toolName)")
            }
            
        case "error":
            if let errorMsg = json["error"] as? String {
                error = errorMsg
            }
            
        case "done":
            if let count = json["token_count"] as? Int {
                tokenCount = count
            } else if let usage = json["usage"] as? [String: Any],
                      let total = usage["total_tokens"] as? Int {
                tokenCount = total
            } else {
                tokenCount = (currentMessage.count + 100) / 4
            }
            
        default:
            break
        }
    }
    
    /// Update a plan step's status (replace array so @Published triggers live UI update)
    private func updatePlanStep(id: String, status: PlanStepStatus, result: String?, error: String?) {
        guard let index = currentPlan.firstIndex(where: { $0.id == id }) else { return }
        var step = currentPlan[index]
        step.status = status
        if let result = result { step.result = result }
        if let error = error { step.error = error }
        var updated = currentPlan
        updated[index] = step
        currentPlan = updated
    }
    
    /// Format error for user display
    private func formatError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "No internet connection. Please check your network settings."
            case .timedOut:
                return "Request timed out. Please try again."
            case .cannotFindHost, .cannotConnectToHost:
                return "Cannot connect to server. Please ensure the backend is running."
            default:
                return "Connection error: \(urlError.localizedDescription)"
            }
        }
        return error.localizedDescription
    }
    
    /// Build a Message from current streaming state
    func buildMessage() -> Message {
        Message(
            role: .assistant,
            content: currentMessage,
            reasoning: currentReasoning,
            isStreaming: isStreaming,
            isError: error != nil,
            tokenCount: tokenCount,
            plan: hasPlan ? currentPlan : nil,
            planSummary: planSummary.isEmpty ? nil : planSummary,
            intent: detectedIntent,
            intentConfidence: intentConfidence,
            mode: currentMode
        )
    }
}
