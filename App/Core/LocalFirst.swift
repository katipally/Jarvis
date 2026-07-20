import Foundation
import FoundationModels
import JAgent
import JLocal

/// Local-first model resolution (decision D3): on-device Foundation Models runs
/// extraction, nudge gating, titles, summaries, and briefs for free/offline;
/// the API aux/brain role is an optional quality upgrade or a fallback. One
/// shared instance is injected into KnowledgeService, ProactivityService, and
/// MeetingService so they never each stand up their own model plumbing.
@MainActor
final class LocalFirst {
    let local: LocalModel
    let core: JarvisCore

    init(local: LocalModel, core: JarvisCore) {
        self.local = local
        self.core = core
    }

    var localAvailable: Bool {
        get async { await local.isAvailable }
    }

    /// Typed guided generation on-device. Returns nil when the on-device model
    /// isn't available — the caller decides whether to fall back (e.g. memory
    /// extraction falls back to the aux JSON path; nudge gating just skips).
    func generate<Content: Generable & Sendable>(
        _ type: Content.Type = Content.self,
        instructions: String,
        prompt: String,
        maxTokens: Int = 1200
    ) async -> Content? {
        guard await local.isAvailable else { return nil }
        return try? await local.generate(type, instructions: instructions, prompt: prompt, maxTokens: maxTokens)
    }

    /// Plain text via on-device → aux → brain. Nil only if nothing is configured.
    func text(instructions: String, prompt: String, maxTokens: Int = 800) async -> String? {
        if await local.isAvailable,
           let t = try? await local.text(instructions: instructions, prompt: prompt, maxTokens: maxTokens),
           !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return t
        }
        guard let resolved = core.resolve(.aux) ?? core.resolve(.brain) else { return nil }
        let request = ModelRequest(model: resolved.model, system: instructions,
                                   messages: [.user(prompt)], maxTokens: maxTokens)
        let engine = ChatEngine(adapter: resolved.adapter)
        var text = ""
        for await event in engine.run(request) {
            if case .assistantMessage(let m) = event { text = m.plainText }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
