import Foundation
import GRDB
import JStore

/// CRUD over the `commitment` and `task` tables (v10). Shared so the memory
/// pipeline (which writes them from extraction) and proactivity (which fires
/// commitments and surfaces tasks) don't each reinvent the queries.
struct TaskStore: Sendable {
    let database: JarvisDatabase

    // MARK: - Commitments

    /// Inserts a commitment unless an open one with the same dedupe key exists.
    func addCommitment(text: String, dueAt: Date?, dedupeKey: String?, segmentID: String?) async {
        _ = try? await database.writer.write { db in
            if let dedupeKey {
                let existing = try CommitmentRow
                    .filter(Column("dedupe_key") == dedupeKey)
                    .filter(Column("status") == CommitmentRow.Status.open.rawValue)
                    .fetchCount(db)
                if existing > 0 { return }
            }
            try CommitmentRow(text: text, dueAt: dueAt, dedupeKey: dedupeKey,
                              sourceSegmentId: segmentID).insert(db)
        }
    }

    /// Open commitments whose due time falls at or before `cutoff`.
    func dueCommitments(by cutoff: Date) async -> [CommitmentRow] {
        (try? await database.reader.read { db in
            try CommitmentRow
                .filter(Column("status") == CommitmentRow.Status.open.rawValue)
                .filter(Column("due_at") != nil && Column("due_at") <= cutoff)
                .order(Column("due_at"))
                .fetchAll(db)
        }) ?? []
    }

    func setCommitmentStatus(_ id: String, _ status: CommitmentRow.Status) async {
        _ = try? await database.writer.write { db in
            try db.execute(sql: "UPDATE commitment SET status = ? WHERE id = ?",
                           arguments: [status.rawValue, id])
        }
    }

    // MARK: - Tasks

    /// Inserts a task unless an identical-text one is already suggested/open.
    /// Extraction-sourced tasks land as `.suggested` for review; manual adds
    /// pass `.open` so they're immediately actionable.
    func addTask(text: String, source: TaskRow.Source, sourceID: String?, dueAt: Date? = nil,
                 status: TaskRow.Status = .suggested) async {
        _ = try? await database.writer.write { db in
            let existing = try TaskRow
                .filter(Column("text") == text)
                .filter([TaskRow.Status.suggested.rawValue, TaskRow.Status.open.rawValue].contains(Column("status")))
                .fetchOne(db)
            if let existing {
                // A manual add of an already-suggested task is an implicit
                // accept — promote it instead of silently dropping the add.
                if status == .open, existing.status == TaskRow.Status.suggested.rawValue {
                    try db.execute(sql: "UPDATE task SET status = ? WHERE id = ?",
                                   arguments: [TaskRow.Status.open.rawValue, existing.id])
                }
                return
            }
            try TaskRow(text: text, source: source, sourceId: sourceID, status: status, dueAt: dueAt).insert(db)
        }
    }

    /// Streams suggested + open tasks so the Tasks pane updates live as
    /// extraction lands new rows.
    func observeActiveTasks() -> AsyncValueObservation<[TaskRow]> {
        ValueObservation
            .tracking { db in
                try TaskRow
                    .filter([TaskRow.Status.suggested.rawValue, TaskRow.Status.open.rawValue].contains(Column("status")))
                    .order(Column("created_at").desc)
                    .fetchAll(db)
            }
            .values(in: database.reader)
    }

    func setTaskText(_ id: String, _ text: String) async {
        _ = try? await database.writer.write { db in
            try db.execute(sql: "UPDATE task SET text = ? WHERE id = ?", arguments: [text, id])
        }
    }

    func setTaskDue(_ id: String, _ dueAt: Date?) async {
        _ = try? await database.writer.write { db in
            try db.execute(sql: "UPDATE task SET due_at = ? WHERE id = ?", arguments: [dueAt, id])
        }
    }

    func tasks(statuses: [TaskRow.Status]) async -> [TaskRow] {
        let raw = statuses.map(\.rawValue)
        return (try? await database.reader.read { db in
            try TaskRow
                .filter(raw.contains(Column("status")))
                .order(Column("created_at").desc)
                .fetchAll(db)
        }) ?? []
    }

    func setTaskStatus(_ id: String, _ status: TaskRow.Status) async {
        _ = try? await database.writer.write { db in
            try db.execute(sql: "UPDATE task SET status = ? WHERE id = ?",
                           arguments: [status.rawValue, id])
        }
    }
}
