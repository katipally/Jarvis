import Foundation
import GRDB
import JStore

/// Read model for the Activity timeline: one chronological feed merging agent
/// runs, meetings, nudges (delivered and suppressed), approval decisions, and
/// artifacts not linked to a run. A single ValueObservation over all the source
/// tables keeps the feed live while the pane is open.
struct TimelineStore: Sendable {
    let database: JarvisDatabase

    struct Entry: Sendable, Identifiable {
        enum Payload: Sendable {
            case run(RunStore.RunSummary, artifactCount: Int)
            case meeting(MeetingRow, taskCount: Int)
            case nudge(NudgeRow)
            case approval(ApprovalEventRow)
            case artifact(ArtifactRow)
        }

        let id: String
        let date: Date
        let payload: Payload
    }

    /// Streams the merged feed, re-emitting when any source table changes.
    /// `limit` bounds each source; the merged feed is capped at 150 entries.
    func observe(limit: Int = 60) -> AsyncValueObservation<[Entry]> {
        ValueObservation
            .tracking { db -> [Entry] in
                var entries: [Entry] = []

                let runs = try RunRow.order(Column("started_at").desc).limit(limit).fetchAll(db)
                for run in runs {
                    let calls = try ToolCallRow
                        .filter(Column("run_id") == run.id)
                        .order(Column("created_at"))
                        .fetchAll(db)
                    let artifactCount = try ArtifactRow.filter(Column("run_id") == run.id).fetchCount(db)
                    let summary = RunStore.RunSummary(
                        id: run.id, kind: run.kind, status: run.status,
                        startedAt: run.startedAt, endedAt: run.endedAt, label: run.label,
                        totalInputTokens: run.totalInputTokens, totalOutputTokens: run.totalOutputTokens,
                        costUsd: run.costUsd, toolCalls: calls)
                    entries.append(Entry(id: "run-\(run.id)", date: run.startedAt,
                                         payload: .run(summary, artifactCount: artifactCount)))
                }

                let meetings = try MeetingRow.order(Column("started_at").desc).limit(limit).fetchAll(db)
                for meeting in meetings {
                    let taskCount = try TaskRow
                        .filter(Column("source") == TaskRow.Source.meeting.rawValue)
                        .filter(Column("source_id") == meeting.id)
                        .fetchCount(db)
                    entries.append(Entry(id: "meeting-\(meeting.id)", date: meeting.startedAt,
                                         payload: .meeting(meeting, taskCount: taskCount)))
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

                return Array(entries.sorted { $0.date > $1.date }.prefix(150))
            }
            .values(in: database.reader)
    }
}
