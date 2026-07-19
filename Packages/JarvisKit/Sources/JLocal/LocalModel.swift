import Foundation
import FoundationModels

public enum LocalModelError: Error, Sendable {
    /// Apple Intelligence off, device ineligible, or model still downloading.
    case unavailable(String)
    case generationFailed(String)
}

/// On-device Apple Foundation Models (~3B) behind a small actor. Every call is
/// a fresh stateless `LanguageModelSession` — extraction, nudge gating, titles,
/// and summaries run here for free, offline, and private. When the model isn't
/// available, callers fall back to an API model (see the app's LocalFirst
/// resolver); nothing here ever blocks on the network.
public actor LocalModel {
    public init() {}

    /// True when guided generation can run right now.
    public var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Human-readable reason the model can't run, or nil when it can.
    public var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "This Mac isn't eligible for Apple Intelligence."
            case .appleIntelligenceNotEnabled: return "Apple Intelligence is turned off in System Settings."
            case .modelNotReady: return "The on-device model is still downloading."
            @unknown default: return "The on-device model is unavailable."
            }
        }
    }

    /// Guided generation into a typed `@Generable` result. Throws
    /// `.unavailable` when the model can't run so callers can fall back.
    public func generate<Content: Generable & Sendable>(
        _ type: Content.Type = Content.self,
        instructions: String,
        prompt: String,
        maxTokens: Int = 1200
    ) async throws -> Content {
        guard isAvailable else { throw LocalModelError.unavailable(unavailableReason ?? "unavailable") }
        let session = LanguageModelSession(instructions: instructions)
        do {
            let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: maxTokens)
            let response = try await session.respond(to: prompt, generating: type, options: options)
            return response.content
        } catch {
            throw LocalModelError.generationFailed(String(describing: error))
        }
    }

    /// Plain-text generation (summaries, briefs).
    public func text(instructions: String, prompt: String, maxTokens: Int = 800) async throws -> String {
        guard isAvailable else { throw LocalModelError.unavailable(unavailableReason ?? "unavailable") }
        let session = LanguageModelSession(instructions: instructions)
        do {
            let options = GenerationOptions(temperature: 0.4, maximumResponseTokens: maxTokens)
            let response = try await session.respond(to: prompt, options: options)
            return response.content
        } catch {
            throw LocalModelError.generationFailed(String(describing: error))
        }
    }
}

/// Splits long input for the small on-device context window. Callers extract
/// per chunk and merge, so a long conversation still fits.
public func localChunks(_ text: String, maxChars: Int = 6000) -> [String] {
    guard text.count > maxChars else { return [text] }
    var chunks: [String] = []
    var current = ""
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        if current.count + line.count > maxChars, !current.isEmpty {
            chunks.append(current)
            current = ""
        }
        current += line + "\n"
    }
    if !current.isEmpty { chunks.append(current) }
    return chunks
}
