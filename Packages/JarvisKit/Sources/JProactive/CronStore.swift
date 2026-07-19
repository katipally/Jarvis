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
