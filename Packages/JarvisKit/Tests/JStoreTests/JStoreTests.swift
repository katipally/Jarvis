import Foundation
import GRDB
import Testing
@testable import JStore

@Test func migrationCreatesCoreTables() async throws {
    let db = try JarvisDatabase.inMemory()
    let tables = try await db.reader.read { db in
        try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
    }
    for expected in ["session", "segment", "message", "run", "tool_call",
                     "setting", "provider_account"] {
        #expect(tables.contains(expected), "missing table \(expected)")
    }
    // Dead since v1, dropped in v7.
    #expect(!tables.contains("compaction_checkpoint"))
}

@Test func v7HarnessColumnsRoundTrip() async throws {
    let db = try JarvisDatabase.inMemory()
    let session = Session()
    let segment = Segment(sessionId: session.id)
    let summary = MessageRecord(
        segmentId: segment.id, seq: 0, role: .user, status: .complete,
        contentJson: #"[{"type":"text","text":"[Conversation summary] …"}]"#,
        kind: .summary
    )
    let run = RunRow(kind: "cron", initiator: "jarvis", status: "done",
                     totalInputTokens: 100, totalOutputTokens: 40, totalCacheReadTokens: 900,
                     costUsd: 0.0123, label: "cron: standup")
    let call = ToolCallRow(runId: run.id, name: "echo", inputJson: "{}", state: "done",
                           outputArtifactId: "art1", durationMs: 250)
    try await db.writer.write { db in
        try session.insert(db)
        try segment.insert(db)
        try summary.insert(db)
        try run.insert(db)
        try call.insert(db)
    }
    let (fetchedMessage, fetchedRun, fetchedCall) = try await db.reader.read { db in
        (try MessageRecord.fetchOne(db, key: summary.id),
         try RunRow.fetchOne(db, key: run.id),
         try ToolCallRow.fetchOne(db, key: call.id))
    }
    #expect(fetchedMessage?.kind == "summary")
    #expect(fetchedMessage?.active == true) // default
    #expect(fetchedRun?.costUsd == 0.0123)
    #expect(fetchedRun?.totalCacheReadTokens == 900)
    #expect(fetchedRun?.label == "cron: standup")
    #expect(fetchedCall?.outputArtifactId == "art1")
    #expect(fetchedCall?.durationMs == 250)
}

@Test func conversationRoundTrip() async throws {
    let db = try JarvisDatabase.inMemory()
    let session = Session()
    let segment = Segment(sessionId: session.id)
    let message = MessageRecord(
        segmentId: segment.id, seq: 0, role: .user, status: .complete,
        contentJson: #"[{"type":"text","text":"hello"}]"#
    )
    try await db.writer.write { db in
        try session.insert(db)
        try segment.insert(db)
        try message.insert(db)
    }
    let fetched = try await db.reader.read { db in
        try MessageRecord.fetchOne(db, key: message.id)
    }
    #expect(fetched?.segmentId == segment.id)
    #expect(fetched?.role == "user")
    #expect(fetched?.contentJson.contains("hello") == true)
}

@Test func messageSeqIsUniquePerSegment() async throws {
    let db = try JarvisDatabase.inMemory()
    let session = Session()
    let segment = Segment(sessionId: session.id)
    try await db.writer.write { db in
        try session.insert(db)
        try segment.insert(db)
        try MessageRecord(segmentId: segment.id, seq: 0, role: .user, status: .complete, contentJson: "[]").insert(db)
    }
    await #expect(throws: DatabaseError.self) {
        try await db.writer.write { db in
            try MessageRecord(segmentId: segment.id, seq: 0, role: .assistant, status: .complete, contentJson: "[]").insert(db)
        }
    }
}

@Test func settingsStoreRoundTrip() async throws {
    let db = try JarvisDatabase.inMemory()
    let store = SettingsStore(db: db)
    try await store.set("onboarding_complete", to: true)
    let value = try await store.get("onboarding_complete", as: Bool.self)
    #expect(value == true)
    try await store.set("onboarding_complete", to: false)
    let updated = try await store.get("onboarding_complete", as: Bool.self)
    #expect(updated == false)
}
