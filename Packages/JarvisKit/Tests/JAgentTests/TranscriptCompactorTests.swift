import Foundation
import Testing
@testable import JAgent

/// A conversation shaped like real agent traffic: opening question, then
/// alternating tool turns (assistant tool_use → user tool_result) and prose.
private func toolConversation(turns: Int, filler: String) -> [NeutralMessage] {
    var messages: [NeutralMessage] = [.user("opening question \(filler)")]
    for i in 0..<turns {
        messages.append(NeutralMessage(role: .assistant, content: [
            .text("thinking about step \(i)"),
            .toolUse(id: "t\(i)", name: "echo", input: .object(["x": .string(filler)])),
        ]))
        messages.append(NeutralMessage(role: .user, content: [
            .toolResult(toolUseId: "t\(i)", content: "result \(i) \(filler)", isError: false, images: []),
        ]))
        messages.append(.user("follow-up \(i) \(filler)"))
        messages.append(.assistant("answer \(i) \(filler)"))
    }
    return messages
}

@Test func noPlanUnderPressureThreshold() {
    let messages = toolConversation(turns: 3, filler: "short")
    #expect(TranscriptCompactor.plan(messages, contextLimit: 200_000) == nil)
}

@Test func planTailNeverStartsInsideToolPair() {
    let filler = String(repeating: "x", count: 2000)
    let messages = toolConversation(turns: 20, filler: filler)
    // Low limit forces compaction.
    let plan = TranscriptCompactor.plan(messages, contextLimit: 10_000)
    #expect(plan != nil)
    guard let plan else { return }

    // The tail must open on a plain user turn — never a tool result, never an
    // assistant message.
    #expect(TranscriptCompactor.isPlainUserTurn(plan.tail[0]))

    // Every tool_use in the tail has its result in the tail too.
    var tailToolUses: Set<String> = []
    var tailToolResults: Set<String> = []
    for message in plan.tail {
        for block in message.content {
            if case .toolUse(let id, _, _) = block { tailToolUses.insert(id) }
            if case .toolResult(let id, _, _, _) = block { tailToolResults.insert(id) }
        }
    }
    #expect(tailToolUses.isSubset(of: tailToolResults))

    // Reassembly preserves order and drops nothing.
    #expect(plan.head.count + plan.middle.count + plan.tail.count == messages.count)
    #expect(plan.head.count == 1)
    #expect(!plan.middle.isEmpty)
}

@Test func schemasCountTowardPressure() {
    let messages = toolConversation(turns: 3, filler: "short")
    let bigSchema = ToolSchema(
        name: "big", description: String(repeating: "d", count: 40_000),
        parameters: .object(["type": .string("object")])
    )
    let bare = TranscriptCompactor.estimatedTokens(messages)
    let loaded = TranscriptCompactor.estimatedTokens(messages, toolSchemas: [bigSchema])
    #expect(loaded > bare + 9000)
}

@Test func renderForSummarySkipsThinkingAndCaps() {
    let messages: [NeutralMessage] = [
        NeutralMessage(role: .assistant, content: [
            .thinking(String(repeating: "secret", count: 100), signature: nil),
            .text("visible answer"),
        ]),
        .user("a question"),
    ]
    let rendered = TranscriptCompactor.renderForSummary(messages)
    #expect(!rendered.contains("secret"))
    #expect(rendered.contains("visible answer"))
    #expect(rendered.contains("User: a question"))
}
