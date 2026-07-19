import Foundation
import GRDB
import JAgent
import JStore

/// Persists agent runs and tool calls; also reads them back for the Activity tab.
struct RunStore: Sendable {
    let database: JarvisDatabase

    func createRun(id: String, kind: String, segmentID: String?, initiator: String?) async {
        _ = try? await database.writer.write { db in
            try RunRow(id: id, kind: kind, segmentId: segmentID, initiator: initiator, status: "running").insert(db)
        }
    }

    func finishRun(id: String, status: String, usage: Usage, error: String?) async {
        _ = try? await database.writer.write { db in
            guard var row = try RunRow.fetchOne(db, key: id) else { return }
            row.status = status
            row.endedAt = .now
            row.error = error
            row.totalInputTokens = usage.inputTokens
            row.totalOutputTokens = usage.outputTokens
            try row.update(db)
        }
    }

    func toolStarted(id: String, runID: String, name: String, input: JSONValue) async {
        _ = try? await database.writer.write { db in
            try ToolCallRow(id: id, runId: runID, name: name, inputJson: input.jsonString, state: "running").insert(db)
        }
    }

    func toolFinished(id: String, state: String, preview: String) async {
        _ = try? await database.writer.write { db in
            guard var row = try ToolCallRow.fetchOne(db, key: id) else { return }
            row.state = state
            row.outputPreview = String(preview.prefix(400))
            try row.update(db)
        }
    }

    // MARK: - Reads for Activity

    struct RunSummary: Sendable, Identifiable {
        let id: String
        let kind: String
        let status: String
        let startedAt: Date
        let toolCalls: [ToolCallRow]
    }

    func recentRuns(limit: Int = 40) async -> [RunSummary] {
        (try? await database.reader.read { db -> [RunSummary] in
            let runs = try RunRow.order(Column("started_at").desc).limit(limit).fetchAll(db)
            return try runs.map { run in
                let calls = try ToolCallRow
                    .filter(Column("run_id") == run.id)
                    .order(Column("created_at"))
                    .fetchAll(db)
                return RunSummary(id: run.id, kind: run.kind, status: run.status, startedAt: run.startedAt, toolCalls: calls)
            }
        }) ?? []
    }
}
