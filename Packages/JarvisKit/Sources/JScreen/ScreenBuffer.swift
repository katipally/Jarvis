import AppKit
import Foundation
import GRDB
import JStore

/// Passive screen buffer: captures the frontmost window on a real app switch or
/// a periodic tick, dedups near-identical frames, and sweeps on a 72h TTL / 1GB
/// ceiling. Frames reach a model only via agent tools — with one documented
/// exception: the proactivity context-switch evaluation sends the single switch
/// frame to the user-configured aux model (see ProactivityService).
public final class ScreenBuffer: @unchecked Sendable {
    private let database: JarvisDatabase
    private let framesDir: URL
    private let blocklist: Set<String>

    private let tickInterval: TimeInterval = 60
    private let dedupThreshold = 4

    private var task: Task<Void, Never>?
    private var lastBundle: String?
    private var lastPHash: Int64 = 0
    private var lastCapture = Date.distantPast
    private var lastSweep = Date.distantPast

    // Live-tunable policy. Written from any thread (Settings) and read from the
    // capture task, so it's guarded by a lock rather than left to a torn struct read.
    private let policyLock = NSLock()
    private var _policy = ScreenCapturePolicy.default
    private var policy: ScreenCapturePolicy {
        get { policyLock.lock(); defer { policyLock.unlock() }; return _policy }
        set { policyLock.lock(); _policy = newValue; policyLock.unlock() }
    }

    // Serial background OCR pipeline: store() yields a job, one consumer drains it
    // so frames are OCR'd one at a time and never pile up on the capture path.
    private struct OCRJob: Sendable { let id: String; let jpegPath: String }
    private let ocrJobs: AsyncStream<OCRJob>
    private let ocrEnqueue: AsyncStream<OCRJob>.Continuation
    private var ocrConsumer: Task<Void, Never>?

    /// Fired on a real context switch (for proactivity in M7).
    public var onContextSwitch: (@Sendable (CapturedFrame) -> Void)?

    public init(database: JarvisDatabase, framesDirectory: URL, blocklist: Set<String> = ScreenBuffer.defaultBlocklist) {
        self.database = database
        self.framesDir = framesDirectory
        self.blocklist = blocklist
        (self.ocrJobs, self.ocrEnqueue) = AsyncStream.makeStream(of: OCRJob.self)
        try? FileManager.default.createDirectory(at: framesDirectory, withIntermediateDirectories: true)
    }

    /// Swap in a new capture policy (from Settings). Read live on the next tick.
    public func setPolicy(_ policy: ScreenCapturePolicy) { self.policy = policy }

    public static let defaultBlocklist: Set<String> = [
        "com.apple.keychainaccess", "com.agilebits.onepassword7", "com.1password.1password",
        "com.lastpass.LastPass", "com.bitwarden.desktop",
    ]

    public func start() {
        if ocrConsumer == nil {
            ocrConsumer = Task { [weak self] in
                guard let self else { return }
                for await job in self.ocrJobs {
                    await self.performOCR(job)
                }
            }
        }
        guard task == nil else { return }
        task = Task { [weak self] in
            // TTL must hold even if Screen Recording was later revoked (tick
            // bails early in that case), so sweep unconditionally on start.
            await self?.sweep()
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    private func tick() async {
        let policy = self.policy
        guard policy.enabled else { return }
        guard ScreenCapture.hasPermission, !ScreenCapture.isScreenLocked else { return }
        let bundle = await MainActor.run { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
        if let bundle, blocklist.contains(bundle) || policy.excludedBundleIDs.contains(bundle) { return }

        let switched = bundle != lastBundle
        let due = Date.now.timeIntervalSince(lastCapture) > tickInterval
        guard switched || due else { return }

        guard let frame = try? await ScreenCapture.captureFrontWindow() else { return }

        // Dedup near-identical periodic frames (but always keep a switch frame).
        if !switched, PerceptualHash.hamming(frame.phash, lastPHash) <= dedupThreshold {
            lastCapture = .now
            return
        }

        let previousPHash = lastPHash
        await store(frame, trigger: switched ? "context_switch" : "tick", previousPHash: previousPHash)
        lastBundle = bundle
        lastPHash = frame.phash
        lastCapture = .now
        if switched { onContextSwitch?(frame) }

        if Date.now.timeIntervalSince(lastSweep) > 3600 {
            await sweep()
            lastSweep = .now
        }
    }

    /// On-demand capture for the take_screenshot tool. Stores + returns the frame.
    @discardableResult
    public func captureNow() async throws -> CapturedFrame {
        guard ScreenCapture.hasPermission else { throw ScreenError.permissionDenied }
        guard let frame = try await ScreenCapture.captureFrontWindow() else {
            throw ScreenError.noWindow
        }
        await store(frame, trigger: "on_demand")
        return frame
    }

    private func store(_ frame: CapturedFrame, trigger: String, previousPHash: Int64 = 0) async {
        let id = UUID().uuidString
        let path = framesDir.appendingPathComponent("\(id).jpg")
        try? frame.jpeg.write(to: path)
        let row = ScreenFrameRow(
            id: id, ts: .now, appBundleId: frame.appBundleID, appName: frame.appName,
            windowTitle: frame.windowTitle, displayId: frame.displayID, phash: frame.phash,
            jpegPath: path.path, bytes: frame.jpeg.count, trigger: trigger
        )
        _ = try? await database.writer.write { try row.insert($0) }

        // Skip OCR for a frame perceptually identical to the previous kept one
        // (e.g. switching back to an unchanged window). Otherwise enqueue it on the
        // serial pipeline. The FTS twin auto-syncs on the ocr_text UPDATE via triggers.
        if previousPHash != 0, PerceptualHash.hamming(frame.phash, previousPHash) <= dedupThreshold {
            await markOCR(id: id, text: nil, status: "skipped")
        } else {
            ocrEnqueue.yield(OCRJob(id: id, jpegPath: path.path))
        }
    }

    private func performOCR(_ job: OCRJob) async {
        let text = await FrameOCR.text(jpegPath: job.jpegPath)
        await markOCR(id: job.id, text: text, status: "done")
    }

    private func markOCR(id: String, text: String?, status: String) async {
        _ = try? await database.writer.write { db in
            try db.execute(
                sql: "UPDATE screen_frame SET ocr_text = ?, ocr_status = ? WHERE id = ?",
                arguments: [text, status, id]
            )
        }
    }

    private func sweep() async {
        let policy = self.policy
        let ttl = TimeInterval(policy.retentionHours) * 3600
        let ceilingBytes = policy.ceilingBytes
        let cutoff = Date.now.addingTimeInterval(-ttl)
        _ = try? await database.writer.write { db in
            let expired = try ScreenFrameRow.filter(Column("ts") < cutoff).fetchAll(db)
            for frame in expired {
                try? FileManager.default.removeItem(atPath: frame.jpegPath)
                try ScreenFrameRow.deleteOne(db, key: frame.id)
            }
            // Enforce the disk ceiling oldest-first.
            var total = try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(bytes),0) FROM screen_frame") ?? 0
            if total > ceilingBytes {
                let oldest = try ScreenFrameRow.order(Column("ts")).fetchAll(db)
                for frame in oldest where total > ceilingBytes {
                    try? FileManager.default.removeItem(atPath: frame.jpegPath)
                    try ScreenFrameRow.deleteOne(db, key: frame.id)
                    total -= frame.bytes
                }
            }
        }
    }
}

/// Read side for the recall tools.
public struct ScreenRecall: Sendable {
    private let database: JarvisDatabase

    public init(database: JarvisDatabase) { self.database = database }

    public struct FrameMeta: Sendable, Identifiable {
        public let id: String
        public let ts: Date
        public let appName: String?
        public let windowTitle: String?
        public let jpegPath: String
    }

    /// One full-text search hit over OCR'd screen text.
    public struct SearchHit: Sendable, Identifiable {
        public let id: String
        public let ts: Date
        public let appName: String?
        public let windowTitle: String?
        public let snippet: String
        public let jpegPath: String
    }

    public func recent(hours: Int, app: String?, limit: Int = 40) async -> [FrameMeta] {
        let cutoff = Date.now.addingTimeInterval(-Double(hours) * 3600)
        return (try? await database.reader.read { db -> [FrameMeta] in
            var request = ScreenFrameRow.filter(Column("ts") >= cutoff)
            if let app, !app.isEmpty {
                request = request.filter(sql: "LOWER(app_name) LIKE ?", arguments: ["%\(app.lowercased())%"])
            }
            let rows = try request.order(Column("ts").desc).limit(limit).fetchAll(db)
            return rows.map { FrameMeta(id: $0.id, ts: $0.ts, appName: $0.appName, windowTitle: $0.windowTitle, jpegPath: $0.jpegPath) }
        }) ?? []
    }

    /// FTS5 search over OCR text + window titles, newest-relevant first. Each hit
    /// carries a `snippet()` excerpt around the match for display / model context.
    public func search(_ query: String, limit: Int = 20) async -> [SearchHit] {
        let terms = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
        guard !terms.isEmpty else { return [] }
        let match = terms.map { "\"\($0)\"" }.joined(separator: " OR ")
        return (try? await database.reader.read { db -> [SearchHit] in
            let rows = try Row.fetchAll(db, sql: """
                SELECT screen_frame.id AS id, screen_frame.ts AS ts,
                       screen_frame.app_name AS app_name, screen_frame.window_title AS window_title,
                       screen_frame.jpeg_path AS jpeg_path,
                       snippet(screen_frame_fts, 0, '', '', '…', 12) AS snippet
                FROM screen_frame
                JOIN screen_frame_fts ON screen_frame.rowid = screen_frame_fts.rowid
                WHERE screen_frame_fts MATCH ?
                ORDER BY rank
                LIMIT ?
                """, arguments: [match, limit])
            return rows.map { row in
                SearchHit(
                    id: row["id"], ts: row["ts"],
                    appName: row["app_name"], windowTitle: row["window_title"],
                    snippet: (row["snippet"] as String?) ?? "",
                    jpegPath: row["jpeg_path"]
                )
            }
        }) ?? []
    }

    /// Load up to `max` frames' JPEGs as base64, with their metadata.
    public func frames(ids: [String], max: Int = 5) async -> [(meta: FrameMeta, base64: String)] {
        let ids = Array(ids.prefix(max))
        guard !ids.isEmpty else { return [] }
        let rows = (try? await database.reader.read { db in
            try ScreenFrameRow.filter(ids.contains(Column("id"))).fetchAll(db)
        }) ?? []
        return rows.compactMap { row in
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: row.jpegPath)) else { return nil }
            return (FrameMeta(id: row.id, ts: row.ts, appName: row.appName, windowTitle: row.windowTitle, jpegPath: row.jpegPath), data.base64EncodedString())
        }
    }
}
