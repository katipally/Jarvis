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
    
    var hasReasoning: Bool {
        !reasoning.isEmpty
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
         attachedFileNames: [String] = []) {
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
        
        if let createdAtString = try? container.decode(String.self, forKey: .createdAt) {
            let formatter = ISO8601DateFormatter()
            createdAt = formatter.date(from: createdAtString) ?? Date()
        } else {
            createdAt = Date()
        }
    }
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct ChatRequest: Codable {
    let messages: [ChatMessage]
    
    init(messages: [ChatMessage]) {
        self.messages = messages
    }
}

struct StreamEvent: Codable {
    let type: String
    let content: String?
    let toolName: String?
    let error: String?
    let reasoningCount: Int?
    let tokenCount: Int?
    let usage: TokenUsage?
    
    enum CodingKeys: String, CodingKey {
        case type, content, error, usage
        case toolName = "tool_name"
        case reasoningCount = "reasoning_count"
        case tokenCount = "token_count"
    }
}

struct TokenUsage: Codable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}
