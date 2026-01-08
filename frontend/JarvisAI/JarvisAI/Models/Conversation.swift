import Foundation

/// Chat interaction type for sidebar icons
enum ChatType: String, Codable {
    case text       // Text-only chat (keyboard icon)
    case voice      // Voice-only chat (speaker icon)
    case mixed      // Both text and voice (both icons)
    
    var icon: String {
        switch self {
        case .text: return "keyboard"
        case .voice: return "waveform"
        case .mixed: return "keyboard"  // Primary icon for mixed
        }
    }
    
    var secondaryIcon: String? {
        switch self {
        case .mixed: return "waveform"
        default: return nil
        }
    }
}

struct Conversation: Identifiable, Codable {
    let id: String
    var title: String
    var messages: [Message]
    let createdAt: Date
    var updatedAt: Date
    var chatType: ChatType
    
    init(id: String = UUID().uuidString, 
         title: String = "New Chat",
         messages: [Message] = [],
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         chatType: ChatType = .text) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.chatType = chatType
    }
    
    var preview: String {
        messages.first(where: { $0.role == .user })?.content.prefix(50).description ?? "Empty conversation"
    }
    
    var totalTokens: Int {
        messages.reduce(0) { $0 + $1.tokenCount }
    }
    
    mutating func updateTitle() {
        if let firstUserMessage = messages.first(where: { $0.role == .user }) {
            title = String(firstUserMessage.content.prefix(40))
        }
    }
}
