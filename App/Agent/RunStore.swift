import Foundation
import GRDB
import JAgent
import JStore

/// Persists agent runs and tool calls; also reads them back for the Activity tab.
struct RunStore: Sendable {
    let database: JarvisDatabase

    func createRun(id: String, kind: String, segmentID: String?, initiator: String?, label: String? = nil) async {
        await database.loggingWrite("run.create") { db in
            try RunRow(id: id, kind: kind, segmentId: segmentID, initiator: initiator,
                       status: "running", label: label).insert(db)
        }
    }

    func finishRun(id: String, status: String, usage: Usage, error: String?, costUSD: Double? = nil) async {
        await database.loggingWrite("run.finish") { db in
            guard var row = try RunRow.fetchOne(db, key: id) else { return }
            row.status = status
            row.endedAt = .now
            row.error = error
            row.totalInputTokens = usage.inputTokens
            row.totalOutputTokens = usage.outputTokens
            row.totalCacheReadTokens = usage.cacheReadTokens
            row.costUsd = costUSD
            try row.update(db)
        }
    }

    func toolStarted(id: String, runID: String, name: String, input: JSONValue) async {
        await database.loggingWrite("tool.start") { db in
            try ToolCallRow(id: id, runId: runID, name: name, inputJson: input.jsonString, state: "running").insert(db)
        }
    }

    func toolFinished(id: String, state: String, preview: String, artifactID: String? = nil) async {
        await database.loggingWrite("tool.finish") { db in
            guard var row = try ToolCallRow.fetchOne(db, key: id) else { return }
            row.state = state
            row.outputPreview = String(preview.prefix(400))
            row.outputArtifactId = artifactID
            row.durationMs = Int(Date.now.timeIntervalSince(row.createdAt) * 1000)
            try row.update(db)
        }
    }

    // MARK: - Reads for Activity

    struct RunSummary: Sendable, Identifiable {
        let id: String
        let kind: String
        let status: String
        let startedAt: Date
        let endedAt: Date?
        let label: String?
        let totalInputTokens: Int
        let totalOutputTokens: Int
        let costUsd: Double?
        let toolCalls: [ToolCallRow]

        var duration: TimeInterval? { endedAt.map { $0.timeIntervalSince(startedAt) } }
    }

    func recentRuns(limit: Int = 40) async -> [RunSummary] {
        (try? await database.reader.read { db -> [RunSummary] in
            let runs = try RunRow.order(Column("started_at").desc).limit(limit).fetchAll(db)
            return try runs.map { run in
                let calls = try ToolCallRow
                    .filter(Column("run_id") == run.id)
                    .order(Column("created_at"))
                    .fetchAll(db)
                return RunSummary(id: run.id, kind: run.kind, status: run.status,
                                  startedAt: run.startedAt, endedAt: run.endedAt, label: run.label,
                                  totalInputTokens: run.totalInputTokens, totalOutputTokens: run.totalOutputTokens,
                                  costUsd: run.costUsd, toolCalls: calls)
            }
        }) ?? []
    }
}

// MARK: - Live observation + full run detail (Activity rework, Phase 9)

extension RunStore {
    /// Streams the recent-runs list, re-emitting whenever any `run` or
    /// `tool_call` row changes — lets the Activity pane update live while runs
    /// stream instead of loading once. Region tracking (run + tool_call) is
    /// inferred automatically by `ValueObservation.tracking`.
    func observeRecentRuns(limit: Int = 40) -> AsyncValueObservation<[RunSummary]> {
        ValueObservation
            .tracking { db -> [RunSummary] in
                let runs = try RunRow.order(Column("started_at").desc).limit(limit).fetchAll(db)
                return try runs.map { run in
                    let calls = try ToolCallRow
                        .filter(Column("run_id") == run.id)
                        .order(Column("created_at"))
                        .fetchAll(db)
                    return RunSummary(id: run.id, kind: run.kind, status: run.status,
                                      startedAt: run.startedAt, endedAt: run.endedAt, label: run.label,
                                      totalInputTokens: run.totalInputTokens, totalOutputTokens: run.totalOutputTokens,
                                      costUsd: run.costUsd, toolCalls: calls)
                }
            }
            .values(in: database.reader)
    }

    /// One tool invocation in a run's reconstructed timeline.
    struct RunToolItem: Sendable, Identifiable {
        let id: String
        let name: String
        let state: String        // running | done | error | pending_approval | denied | repaired
        let durationMs: Int?
        let output: String
        let isError: Bool
        let artifactID: String?
    }

    /// A run's timeline: assistant prose interleaved with the tool rows it drove.
    enum TimelineItem: Sendable, Identifiable {
        case assistant(id: String, text: String)
        case tool(RunToolItem)

        var id: String {
            switch self {
            case .assistant(let id, _): "assistant-\(id)"
            case .tool(let item): "tool-\(item.id)"
            }
        }
    }

    /// Everything a detail view needs for one run, foreground or background.
    struct RunDetail: Sendable, Identifiable {
        let id: String
        let kind: String
        let status: String
        let startedAt: Date
        let endedAt: Date?
        let label: String?
        let error: String?
        let inputTokens: Int
        let outputTokens: Int
        let cacheReadTokens: Int
        let costUsd: Double?
        let items: [TimelineItem]
        let artifacts: [ArtifactRow]

        var duration: TimeInterval? { endedAt.map { $0.timeIntervalSince(startedAt) } }
    }

    /// Decoded message row fed to the pure timeline builder.
    struct TimelineMessage: Sendable {
        let id: String
        let role: MessageRole
        let content: [ContentBlock]
        let kind: String
    }

    /// Loads a run plus its full message timeline (message rows WHERE run_id,
    /// ordered by seq) and artifact links. Foreground runs persist assistant +
    /// tool-result rows; background runs persist only `tool_call` rows, so the
    /// builder falls back to those. Returns nil if the run id is unknown.
    func fetchRun(id: String) async -> RunDetail? {
        let detail: RunDetail? = try? await database.reader.read { db -> RunDetail? in
            guard let run = try RunRow.fetchOne(db, key: id) else { return nil }
            let records = try MessageRecord
                .filter(Column("run_id") == id)
                .filter(Column("active") == true)
                .order(Column("seq"))
                .fetchAll(db)
            let calls = try ToolCallRow
                .filter(Column("run_id") == id)
                .order(Column("created_at"))
                .fetchAll(db)
            let artifacts = try ArtifactRow
                .filter(Column("run_id") == id)
                .order(Column("created_at"))
                .fetchAll(db)
            let messages = records.map { r in
                TimelineMessage(id: r.id,
                                role: MessageRole(rawValue: r.role) ?? .assistant,
                                content: decodeContent(r.contentJson),
                                kind: r.kind)
            }
            let items = Self.buildTimeline(messages: messages, toolCalls: calls)
            return RunDetail(id: run.id, kind: run.kind, status: run.status,
                             startedAt: run.startedAt, endedAt: run.endedAt, label: run.label,
                             error: run.error, inputTokens: run.totalInputTokens,
                             outputTokens: run.totalOutputTokens, cacheReadTokens: run.totalCacheReadTokens,
                             costUsd: run.costUsd, items: items, artifacts: artifacts)
        }
        return detail
    }

    /// Pure reconstruction: pairs each `toolUse` with the `toolResult` that lands
    /// in a later user row (same approach as `DisplayMessage.rows`), enriching
    /// each tool with duration/state/artifact from `tool_call`. Any `tool_call`
    /// with no matching message row (background runs) is appended at the end.
    static func buildTimeline(messages: [TimelineMessage], toolCalls: [ToolCallRow]) -> [TimelineItem] {
        var results: [String: (output: String, isError: Bool)] = [:]
        for message in messages {
            for case .toolResult(let uid, let content, let isError, _) in message.content {
                results[uid] = (content, isError)
            }
        }
        let callByID = Dictionary(toolCalls.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var items: [TimelineItem] = []
        var seen = Set<String>()
        for message in messages {
            if message.kind == MessageRecord.Kind.summary.rawValue { continue }
            if message.role == .user { continue } // original prompt + tool-result carriers
            let text = message.content.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined()
            if !text.isEmpty {
                items.append(.assistant(id: message.id, text: text))
            }
            for case .toolUse(let uid, let name, _) in message.content {
                seen.insert(uid)
                let call = callByID[uid]
                let result = results[uid]
                items.append(.tool(RunToolItem(
                    id: uid,
                    name: call?.name ?? name,
                    state: call?.state ?? ((result?.isError ?? false) ? "error" : "done"),
                    durationMs: call?.durationMs,
                    output: result?.output ?? call?.outputPreview ?? "",
                    isError: result?.isError ?? (call?.state == "error"),
                    artifactID: call?.outputArtifactId
                )))
            }
        }
        for call in toolCalls where !seen.contains(call.id) {
            items.append(.tool(RunToolItem(
                id: call.id, name: call.name, state: call.state,
                durationMs: call.durationMs,
                output: results[call.id]?.output ?? call.outputPreview ?? "",
                isError: call.state == "error",
                artifactID: call.outputArtifactId
            )))
        }
        return items
    }
}
