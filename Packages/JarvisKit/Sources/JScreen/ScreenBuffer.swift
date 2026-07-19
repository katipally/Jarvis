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
    private let ttl: TimeInterval = 72 * 3600
    private let ceilingBytes = 1_000_000_000

    private var task: Task<Void, Never>?
    private var lastBundle: String?
    private var lastPHash: Int64 = 0
    private var lastCapture = Date.distantPast
    private var lastSweep = Date.distantPast

    /// Fired on a real context switch (for proactivity in M7).
    public var onContextSwitch: (@Sendable (CapturedFrame) -> Void)?

    public init(database: JarvisDatabase, framesDirectory: URL, blocklist: Set<String> = ScreenBuffer.defaultBlocklist) {
        self.database = database
        self.framesDir = framesDirectory
        self.blocklist = blocklist
        try? FileManager.default.createDirectory(at: framesDirectory, withIntermediateDirectories: true)
    }

    public static let defaultBlocklist: Set<String> = [
        "com.apple.keychainaccess", "com.agilebits.onepassword7", "com.1password.1password",
        "com.lastpass.LastPass", "com.bitwarden.desktop",
    ]

    public func start() {
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
        guard ScreenCapture.hasPermission, !ScreenCapture.isScreenLocked else { return }
        let bundle = await MainActor.run { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
        if let bundle, blocklist.contains(bundle) { return }

        let switched = bundle != lastBundle
        let due = Date.now.timeIntervalSince(lastCapture) > tickInterval
        guard switched || due else { return }

        guard let frame = try? await ScreenCapture.captureFrontWindow() else { return }

        // Dedup near-identical periodic frames (but always keep a switch frame).
        if !switched, PerceptualHash.hamming(frame.phash, lastPHash) <= dedupThreshold {
            lastCapture = .now
            return
        }

        await store(frame, trigger: switched ? "context_switch" : "tick")
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

    private func store(_ frame: CapturedFrame, trigger: String) async {
        let id = UUID().uuidString
        let path = framesDir.appendingPathComponent("\(id).jpg")
        try? frame.jpeg.write(to: path)
        let row = ScreenFrameRow(
            id: id, ts: .now, appBundleId: frame.appBundleID, appName: frame.appName,
            windowTitle: frame.windowTitle, displayId: frame.displayID, phash: frame.phash,
            jpegPath: path.path, bytes: frame.jpeg.count, trigger: trigger
        )
        _ = try? await database.writer.write { try row.insert($0) }
    }

    private func sweep() async {
        let cutoff = Date.now.addingTimeInterval(-ttl)
        _ = try? await database.writer.write { db in
            let expired = try ScreenFrameRow.filter(Column("ts") < cutoff).fetchAll(db)
            for frame in expired {
                try? FileManager.default.removeItem(atPath: frame.jpegPath)
                try ScreenFrameRow.deleteOne(db, key: frame.id)
            }
            // Enforce the disk ceiling oldest-first.
            var total = try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(bytes),0) FROM screen_frame") ?? 0
            if total > self.ceilingBytes {
                let oldest = try ScreenFrameRow.order(Column("ts")).fetchAll(db)
                for frame in oldest where total > self.ceilingBytes {
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
    }

    public func recent(hours: Int, app: String?, limit: Int = 40) async -> [FrameMeta] {
        let cutoff = Date.now.addingTimeInterval(-Double(hours) * 3600)
        return (try? await database.reader.read { db -> [FrameMeta] in
            var request = ScreenFrameRow.filter(Column("ts") >= cutoff)
            if let app, !app.isEmpty {
                request = request.filter(sql: "LOWER(app_name) LIKE ?", arguments: ["%\(app.lowercased())%"])
            }
            let rows = try request.order(Column("ts").desc).limit(limit).fetchAll(db)
            return rows.map { FrameMeta(id: $0.id, ts: $0.ts, appName: $0.appName, windowTitle: $0.windowTitle) }
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
            return (FrameMeta(id: row.id, ts: row.ts, appName: row.appName, windowTitle: row.windowTitle), data.base64EncodedString())
        }
    }
}
