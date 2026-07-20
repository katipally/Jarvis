import Foundation
import GRDB
import JStore

/// Read model for the consciousness feed: one chronological stream of what
/// Jarvis did and DECIDED — world syncs, decisions (with reasons, including
/// what was suppressed), delivered nudges, runs, meetings, approvals. Runs of
/// routine quiet verdicts collapse into a single "handled quietly" row so the
/// feed shows judgment, not noise.
struct ConsciousnessFeedStore: Sendable {
    let database: JarvisDatabase

    struct Entry: Sendable, Identifiable {
        enum Payload: Sendable {
            case run(RunStore.RunSummary, artifactCount: Int)
            case meeting(MeetingRow, taskCount: Int)
            case nudge(NudgeRow)
            case approval(ApprovalEventRow)
            case artifact(ArtifactRow)
            case ingest(IngestRunRow, worldName: String)
            case decision(DecisionRow)
            /// N routine verdicts (quiet ticks, dedupes, rate limits) collapsed.
            case quietSpan(count: Int, from: Date, to: Date)
        }

        let id: String
        let date: Date
        let payload: Payload
    }

    /// Actions that read as "the engine considered and stayed quiet" — these
    /// collapse; everything else stands alone with its reason visible.
    private static let quietActions: Set<String> = ["quiet", "deduped", "rate_limited", "dropped"]

    func observe(limit: Int = 60) -> AsyncValueObservation<[Entry]> {
        ValueObservation
            .tracking { db -> [Entry] in
                var entries: [Entry] = []

                // Batched, not N+1: this closure re-runs on every write to any
                // tracked table, so per-run/per-meeting subqueries would
                // multiply into hundreds of queries per decision-row insert.
                let runs = try RunRow.order(Column("started_at").desc).limit(limit).fetchAll(db)
                let runIDs = runs.map(\.id)
                let callsByRun = try Dictionary(
                    grouping: ToolCallRow
                        .filter(runIDs.contains(Column("run_id")))
                        .order(Column("created_at"))
                        .fetchAll(db),
                    by: \.runId)
                let artifactCounts: [String: Int] = try Dictionary(uniqueKeysWithValues:
                    Row.fetchAll(db, sql: """
                        SELECT run_id, COUNT(*) AS n FROM artifact
                        WHERE run_id IS NOT NULL GROUP BY run_id
                        """).map { ($0["run_id"] as String, $0["n"] as Int) })
                for run in runs {
                    let summary = RunStore.RunSummary(
                        id: run.id, kind: run.kind, status: run.status,
                        startedAt: run.startedAt, endedAt: run.endedAt, label: run.label,
                        totalInputTokens: run.totalInputTokens, totalOutputTokens: run.totalOutputTokens,
                        costUsd: run.costUsd, toolCalls: callsByRun[run.id] ?? [])
                    entries.append(Entry(id: "run-\(run.id)", date: run.startedAt,
                                         payload: .run(summary, artifactCount: artifactCounts[run.id] ?? 0)))
                }

                let meetings = try MeetingRow.order(Column("started_at").desc).limit(limit).fetchAll(db)
                let taskCounts: [String: Int] = try Dictionary(uniqueKeysWithValues:
                    Row.fetchAll(db, sql: """
                        SELECT source_id, COUNT(*) AS n FROM task
                        WHERE source = 'meeting' AND source_id IS NOT NULL GROUP BY source_id
                        """).map { ($0["source_id"] as String, $0["n"] as Int) })
                for meeting in meetings {
                    entries.append(Entry(id: "meeting-\(meeting.id)", date: meeting.startedAt,
                                         payload: .meeting(meeting, taskCount: taskCounts[meeting.id] ?? 0)))
                }

                let nudges = try NudgeRow.order(Column("created_at").desc).limit(limit).fetchAll(db)
                entries.append(contentsOf: nudges.map {
                    Entry(id: "nudge-\($0.id)", date: $0.createdAt, payload: .nudge($0))
                })

                let approvals = try ApprovalEventRow.order(Column("created_at").desc).limit(limit).fetchAll(db)
                entries.append(contentsOf: approvals.map {
                    Entry(id: "approval-\($0.id)", date: $0.createdAt, payload: .approval($0))
                })

                let looseArtifacts = try ArtifactRow
                    .filter(Column("run_id") == nil)
                    .order(Column("created_at").desc)
                    .limit(limit)
                    .fetchAll(db)
                entries.append(contentsOf: looseArtifacts.map {
                    Entry(id: "artifact-\($0.id)", date: $0.createdAt, payload: .artifact($0))
                })

                // World syncs that actually brought something in ("Mail synced —
                // 12 episodes"); empty polls stay out of the feed.
                let names = Dictionary(uniqueKeysWithValues: try WorldRow.fetchAll(db).map { ($0.id, $0.displayName) })
                let ingests = try IngestRunRow
                    .filter(Column("status") == "done")
                    .order(Column("started_at").desc)
                    .limit(limit)
                    .fetchAll(db)
                entries.append(contentsOf: ingests.map {
                    Entry(id: "ingest-\($0.id)", date: $0.startedAt,
                          payload: .ingest($0, worldName: names[$0.worldId] ?? $0.worldId))
                })

                // Decisions, newest first; consecutive routine-quiet verdicts
                // collapse into one span row.
                let decisions = try DecisionRow.order(Column("ts").desc).limit(limit * 3).fetchAll(db)
                var quietRun: [DecisionRow] = []
                func flushQuiet() {
                    guard !quietRun.isEmpty else { return }
                    if quietRun.count == 1 {
                        let decision = quietRun[0]
                        entries.append(Entry(id: "decision-\(decision.id)", date: decision.ts,
                                             payload: .decision(decision)))
                    } else {
                        let newest = quietRun.first!.ts
                        let oldest = quietRun.last!.ts
                        entries.append(Entry(id: "quiet-\(quietRun.first!.id)", date: newest,
                                             payload: .quietSpan(count: quietRun.count, from: oldest, to: newest)))
                    }
                    quietRun = []
                }
                for decision in decisions {
                    if Self.quietActions.contains(decision.action) {
                        quietRun.append(decision)
                    } else {
                        flushQuiet()
                        entries.append(Entry(id: "decision-\(decision.id)", date: decision.ts,
                                             payload: .decision(decision)))
                    }
                }
                flushQuiet()

                return Array(entries.sorted { $0.date > $1.date }.prefix(150))
            }
            .values(in: database.reader)
    }
}
