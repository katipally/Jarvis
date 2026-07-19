import Foundation
import GRDB
import JStore

/// CRUD + scheduling for cron jobs, and the heartbeat's persisted last-run.
public struct CronStore: Sendable {
    private let database: JarvisDatabase

    public init(database: JarvisDatabase) { self.database = database }

    @discardableResult
    public func create(name: String, cronExpr: String, prompt: String, now: Date = .now) async -> CronJobRow? {
        guard let schedule = CronSchedule(cronExpr), let next = schedule.nextFire(after: now) else { return nil }
        let job = CronJobRow(name: name, cronExpr: cronExpr, prompt: prompt, nextRunAt: next, createdAt: now)
        _ = try? await database.writer.write { try job.insert($0) }
        return job
    }

    public func dueJobs(now: Date = .now) async -> [CronJobRow] {
        (try? await database.reader.read { db in
            try CronJobRow.filter(Column("enabled") == true && Column("next_run_at") <= now).fetchAll(db)
        }) ?? []
    }

    public func markRan(id: String, status: String, now: Date = .now) async {
        // nextFire can walk minute-by-minute over 400 days for a never-matching
        // expression — compute it outside the write transaction.
        guard let job = try? await database.reader.read({ db in try CronJobRow.fetchOne(db, key: id) }),
              var updated = job as CronJobRow?
        else { return }
        updated.lastRunAt = now
        updated.lastStatus = status
        if let schedule = CronSchedule(updated.cronExpr), let next = schedule.nextFire(after: now) {
            updated.nextRunAt = next
        } else {
            updated.enabled = false
        }
        let final = updated
        _ = try? await database.writer.write { db in try final.update(db) }
    }

    /// Upserts a reserved builtin job (e.g. "builtin:morning_brief") with the
    /// given schedule. The prompt is empty — ProactivityService composes the
    /// body itself when a builtin id comes due. Re-runnable each launch: only
    /// recomputes the next fire when the expression actually changed, so an
    /// unchanged brief keeps its place in the schedule across relaunches.
    public func ensureBuiltin(id: String, name: String, cronExpr: String, enabled: Bool, now: Date = .now) async {
        guard let schedule = CronSchedule(cronExpr), let next = schedule.nextFire(after: now) else { return }
        if let existing = try? await database.reader.read({ db in try CronJobRow.fetchOne(db, key: id) }),
           var updated = existing as CronJobRow? {
            let exprChanged = updated.cronExpr != cronExpr
            let staleReenable = enabled && !updated.enabled && updated.nextRunAt <= now
            updated.name = name
            updated.cronExpr = cronExpr
            updated.enabled = enabled
            if exprChanged || staleReenable { updated.nextRunAt = next }
            let final = updated
            _ = try? await database.writer.write { db in try final.update(db) }
        } else {
            let job = CronJobRow(id: id, name: name, cronExpr: cronExpr, prompt: "",
                                 enabled: enabled, nextRunAt: next, createdAt: now)
            _ = try? await database.writer.write { db in try job.insert(db) }
        }
    }

    public func list() async -> [CronJobRow] {
        (try? await database.reader.read { db in
            try CronJobRow.order(Column("created_at").desc).fetchAll(db)
        }) ?? []
    }

    public func setEnabled(id: String, _ enabled: Bool) async {
        _ = try? await database.writer.write { db in
            try CronJobRow.filter(Column("id") == id).updateAll(db, Column("enabled").set(to: enabled))
        }
    }

    public func delete(id: String) async {
        _ = try? await database.writer.write { db in try CronJobRow.deleteOne(db, key: id) }
    }

    // MARK: - Heartbeat state

    public func heartbeatLastRun() async -> Date? {
        try? await database.reader.read { db in
            try Date.fetchOne(db, sql: "SELECT last_run_at FROM heartbeat_state WHERE id = 1")
        } ?? nil
    }

    public func setHeartbeatRun(_ date: Date, result: String) async {
        _ = try? await database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO heartbeat_state (id, last_run_at, last_result) VALUES (1, ?, ?)
                ON CONFLICT(id) DO UPDATE SET last_run_at = excluded.last_run_at, last_result = excluded.last_result
                """, arguments: [date, result])
        }
    }
}
