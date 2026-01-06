import Foundation

@MainActor
class ConversationStorage {
    static let shared = ConversationStorage()
    private let userDefaults = UserDefaults.standard
    private let conversationsKey = "saved_conversations"
    
    private init() {}
    
    func saveConversations(_ conversations: [Conversation]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(conversations)
            userDefaults.set(data, forKey: conversationsKey)
        } catch {
            print("Failed to save conversations: \(error)")
        }
    }
    
    func loadConversations() -> [Conversation] {
        guard let data = userDefaults.data(forKey: conversationsKey) else {
            return []
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let conversations = try decoder.decode([Conversation].self, from: data)
            return conversations.sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            print("Failed to load conversations: \(error)")
            return []
        }
    }
    
    func deleteConversation(id: String) {
        var conversations = loadConversations()
        conversations.removeAll { $0.id == id }
        saveConversations(conversations)
    }
    
    func clearAll() {
        userDefaults.removeObject(forKey: conversationsKey)
    }
}
