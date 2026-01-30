import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

struct Message: Identifiable, Codable {
    let id: String
    let role: MessageRole
    var content: String
    var reasoning: [String]
    let createdAt: Date
    var isStreaming: Bool
    var attachedFileIds: [String] = []
    var attachedFileNames: [String] = []
    var isError: Bool = false
    var tokenCount: Int = 0
    
    // New: Plan support
    var plan: [PlanStep]? = nil
    var planSummary: String? = nil
    var intent: String? = nil
    var intentConfidence: Double? = nil
    var mode: AgentMode? = nil
    
    var hasReasoning: Bool {
        !reasoning.isEmpty
    }
    
    var hasPlan: Bool {
        guard let plan = plan else { return false }
        return !plan.isEmpty
    }
    
    var timestamp: Date {
        createdAt
    }
    
    // Check if message has image attachments
    var hasImageAttachments: Bool {
        attachedFileNames.contains { name in
            let ext = (name as NSString).pathExtension.lowercased()
            return ["png", "jpg", "jpeg", "gif", "heic", "webp"].contains(ext)
        }
    }
    
    // Get image file names
    var imageFileNames: [String] {
        attachedFileNames.filter { name in
            let ext = (name as NSString).pathExtension.lowercased()
            return ["png", "jpg", "jpeg", "gif", "heic", "webp"].contains(ext)
        }
    }
    
    // Get non-image file names
    var documentFileNames: [String] {
        attachedFileNames.filter { name in
            let ext = (name as NSString).pathExtension.lowercased()
            return !["png", "jpg", "jpeg", "gif", "heic", "webp"].contains(ext)
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, role, content, reasoning, isStreaming, isError, tokenCount
        case createdAt = "created_at"
        case attachedFileIds = "attached_file_ids"
        case attachedFileNames = "attached_file_names"
        case plan, planSummary, intent, intentConfidence, mode
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role.rawValue, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(reasoning, forKey: .reasoning)
        try container.encode(isStreaming, forKey: .isStreaming)
        try container.encode(isError, forKey: .isError)
        try container.encode(tokenCount, forKey: .tokenCount)
        let formatter = ISO8601DateFormatter()
        try container.encode(formatter.string(from: createdAt), forKey: .createdAt)
        try container.encode(attachedFileIds, forKey: .attachedFileIds)
        try container.encode(attachedFileNames, forKey: .attachedFileNames)
        try container.encodeIfPresent(plan, forKey: .plan)
        try container.encodeIfPresent(planSummary, forKey: .planSummary)
        try container.encodeIfPresent(intent, forKey: .intent)
        try container.encodeIfPresent(intentConfidence, forKey: .intentConfidence)
        try container.encodeIfPresent(mode?.rawValue, forKey: .mode)
    }
    
    init(id: String = UUID().uuidString,
         role: MessageRole,
         content: String,
         reasoning: [String] = [],
         createdAt: Date = Date(),
         isStreaming: Bool = false,
         isError: Bool = false,
         tokenCount: Int = 0,
         attachedFileIds: [String] = [],
         attachedFileNames: [String] = [],
         plan: [PlanStep]? = nil,
         planSummary: String? = nil,
         intent: String? = nil,
         intentConfidence: Double? = nil,
         mode: AgentMode? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.createdAt = createdAt
        self.isStreaming = isStreaming
        self.isError = isError
        self.tokenCount = tokenCount
        self.attachedFileIds = attachedFileIds
        self.attachedFileNames = attachedFileNames
        self.plan = plan
        self.planSummary = planSummary
        self.intent = intent
        self.intentConfidence = intentConfidence
        self.mode = mode
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        
        let roleString = try container.decode(String.self, forKey: .role)
        role = MessageRole(rawValue: roleString) ?? .user
        
        content = try container.decode(String.self, forKey: .content)
        reasoning = try container.decodeIfPresent([String].self, forKey: .reasoning) ?? []
        isStreaming = try container.decodeIfPresent(Bool.self, forKey: .isStreaming) ?? false
        isError = try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false
        tokenCount = try container.decodeIfPresent(Int.self, forKey: .tokenCount) ?? 0
        attachedFileIds = try container.decodeIfPresent([String].self, forKey: .attachedFileIds) ?? []
        attachedFileNames = try container.decodeIfPresent([String].self, forKey: .attachedFileNames) ?? []
        plan = try container.decodeIfPresent([PlanStep].self, forKey: .plan)
        planSummary = try container.decodeIfPresent(String.self, forKey: .planSummary)
        intent = try container.decodeIfPresent(String.self, forKey: .intent)
        intentConfidence = try container.decodeIfPresent(Double.self, forKey: .intentConfidence)
        
        if let modeString = try container.decodeIfPresent(String.self, forKey: .mode) {
            mode = AgentMode(rawValue: modeString)
        } else {
            mode = nil
        }
        
        if let createdAtString = try? container.decode(String.self, forKey: .createdAt) {
            let formatter = ISO8601DateFormatter()
            createdAt = formatter.date(from: createdAtString) ?? Date()
        } else {
            createdAt = Date()
        }
    }
    
    // Helper to update plan step status
    mutating func updatePlanStep(id: String, status: PlanStepStatus, result: String? = nil, error: String? = nil) {
        guard var steps = plan else { return }
        
        if let index = steps.firstIndex(where: { $0.id == id }) {
            var step = steps[index]
            step.status = status
            if let result = result {
                step.result = result
            }
            if let error = error {
                step.error = error
            }
            steps[index] = step
            self.plan = steps
        }
    }
}

// MARK: - Chat Message (API Format)
struct ChatMessage: Codable {
    let role: String
    let content: String
}

// MARK: - Chat Request
struct ChatRequest: Codable {
    let messages: [ChatMessage]
    var fileIds: [String]?
    var conversationId: String?
    var mode: String?
    var includeReasoning: Bool?
    var includePlan: Bool?
    
    enum CodingKeys: String, CodingKey {
        case messages
        case fileIds = "file_ids"
        case conversationId = "conversation_id"
        case mode
        case includeReasoning = "include_reasoning"
        case includePlan = "include_plan"
    }
    
    init(messages: [ChatMessage], fileIds: [String]? = nil, conversationId: String? = nil, mode: String? = nil) {
        self.messages = messages
        self.fileIds = fileIds
        self.conversationId = conversationId
        self.mode = mode
        self.includeReasoning = true
        self.includePlan = true
    }
}

// MARK: - Stream Event (Unified Schema)
struct StreamEvent: Codable {
    let type: String
    
    // Content events
    var text: String?
    var content: String?
    var isComplete: Bool?
    
    // Intent events
    var intent: String?
    var confidence: Double?
    
    // Mode events
    var mode: String?
    var reason: String?
    
    // Plan events
    var steps: [StreamPlanStep]?
    var summary: String?
    var status: String?
    
    // Plan step update events
    var stepId: String?
    var result: String?
    
    // Tool events
    var toolName: String?
    var toolArgs: [String: AnyCodable]?
    var toolCallId: String?
    
    // Done events
    var conversationId: String?
    var messageId: String?
    var tokens: TokenUsage?
    var cost: Double?
    var reasoningCount: Int?
    var toolCount: Int?
    var tokenCount: Int?
    
    // Error events
    var error: String?
    var code: String?
    var recoverable: Bool?
    
    enum CodingKeys: String, CodingKey {
        case type, text, content, intent, confidence, mode, reason
        case steps, summary, status, result, error, code, recoverable
        case tokens, cost, toolName, toolArgs, toolCallId
        case stepId = "step_id"
        case isComplete = "is_complete"
        case conversationId = "conversation_id"
        case messageId = "message_id"
        case reasoningCount = "reasoning_count"
        case toolCount = "tool_count"
        case tokenCount = "token_count"
    }
}

// MARK: - Stream Plan Step
struct StreamPlanStep: Codable {
    let id: String
    let description: String
    var status: String?
    var toolName: String?
    
    enum CodingKeys: String, CodingKey {
        case id, description, status
        case toolName = "tool_name"
    }
    
    func toPlanStep() -> PlanStep {
        PlanStep(
            id: id,
            description: description,
            status: PlanStepStatus(rawValue: status ?? "pending") ?? .pending,
            toolName: toolName
        )
    }
}

// MARK: - Token Usage
struct TokenUsage: Codable {
    var prompt: Int?
    var completion: Int?
    var total: Int?
    
    // Legacy support
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case prompt, completion, total
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
    
    var effectiveTotal: Int {
        total ?? totalTokens ?? 0
    }
}

// MARK: - Any Codable Helper
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        default:
            try container.encodeNil()
        }
    }
}
