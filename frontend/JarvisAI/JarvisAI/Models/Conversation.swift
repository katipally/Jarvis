import Foundation

struct Conversation: Identifiable, Codable {
    let id: String
    var title: String
    var messages: [Message]
    let createdAt: Date
    var updatedAt: Date
    
    init(id: String = UUID().uuidString, 
         title: String = "New Chat",
         messages: [Message] = [],
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    var preview: String {
        messages.first(where: { $0.role == .user })?.content.prefix(50).description ?? "Empty conversation"
    }
    
    mutating func updateTitle() {
        if let firstUserMessage = messages.first(where: { $0.role == .user }) {
            title = String(firstUserMessage.content.prefix(40))
        }
    }
}
