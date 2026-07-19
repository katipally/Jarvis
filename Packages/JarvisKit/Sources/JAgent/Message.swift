import Foundation

/// A base64-encoded image attachment.
public struct ImageSource: Sendable, Codable, Equatable {
    public var mediaType: String // "image/png", "image/jpeg", "image/webp"
    public var base64Data: String

    public init(mediaType: String, base64Data: String) {
        self.mediaType = mediaType
        self.base64Data = base64Data
    }

    public var dataURL: String { "data:\(mediaType);base64,\(base64Data)" }
}

/// One piece of message content. The neutral model every provider maps to.
///
/// `thinking.signature` is the provider's opaque replay token (Anthropic thinking
/// signature, or a JSON-encoded OpenAI reasoning item). Adapters replay only
/// signatures they themselves produced and drop the rest.
public enum ContentBlock: Sendable, Codable, Equatable {
    case text(String)
    case thinking(String, signature: String?)
    case image(ImageSource)
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(toolUseId: String, content: String, isError: Bool, images: [ImageSource])
}

public enum MessageRole: String, Sendable, Codable {
    case user, assistant, system, tool
}

/// A single conversational turn in provider-neutral form.
public struct NeutralMessage: Sendable, Codable, Equatable {
    public var role: MessageRole
    public var content: [ContentBlock]

    public init(role: MessageRole, content: [ContentBlock]) {
        self.role = role
        self.content = content
    }

    public static func user(_ text: String, images: [ImageSource] = []) -> NeutralMessage {
        NeutralMessage(role: .user, content: [.text(text)] + images.map(ContentBlock.image))
    }

    public static func assistant(_ text: String) -> NeutralMessage {
        NeutralMessage(role: .assistant, content: [.text(text)])
    }

    /// Plain concatenated text (thinking excluded) — for previews and history rows.
    public var plainText: String {
        content.compactMap {
            if case .text(let t) = $0 { return t }
            return nil
        }.joined()
    }
}
