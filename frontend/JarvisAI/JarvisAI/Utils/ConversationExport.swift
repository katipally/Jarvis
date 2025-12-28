import Foundation

struct ConversationExport {
    static func exportConversation(_ conversation: Conversation) -> String {
        var markdown = "# \(conversation.title)\n\n"
        markdown += "**Date:** \(conversation.createdAt.formatted(date: .long, time: .shortened))\n\n"
        markdown += "---\n\n"
        
        for message in conversation.messages {
            let role = message.role == .user ? "You" : "Jarvis"
            markdown += "## \(role)\n\n"
            markdown += "\(message.content)\n\n"
            
            if !message.reasoning.isEmpty {
                markdown += "### Reasoning\n\n"
                for (index, reasoning) in message.reasoning.enumerated() {
                    markdown += "\(index + 1). \(reasoning)\n"
                }
                markdown += "\n"
            }
            
            markdown += "---\n\n"
        }
        
        return markdown
    }
    
    static func exportToFile(_ conversation: Conversation) -> URL? {
        let markdown = exportConversation(conversation)
        
        let fileName = "\(conversation.title.replacingOccurrences(of: " ", with: "_"))_\(Date().timeIntervalSince1970).md"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try markdown.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            print("Error exporting conversation: \(error)")
            return nil
        }
    }
}

