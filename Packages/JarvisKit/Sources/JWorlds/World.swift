import CryptoKit
import Foundation
import JKnowledge

/// A pending unit of experience produced by a text world; becomes an `episode`
/// row (LLM extraction runs later, off the sync path).
public struct EpisodeDraft: Sendable {
    public var externalId: String?
    public var occurredAt: Date
    public var title: String?
    public var content: String

    public init(externalId: String? = nil, occurredAt: Date, title: String? = nil, content: String) {
        self.externalId = externalId
        self.occurredAt = occurredAt
        self.title = title
        self.content = content
    }
}

/// One incremental sync: the new checkpoint cursor plus what was found since
/// the old one. Text worlds fill `episodes`; structured worlds fill `ops`
/// (episodes allowed too, e.g. browsing-pattern notes).
public struct WorldSyncResult: Sendable {
    public var cursorJson: String?
    public var episodes: [EpisodeDraft] = []
    public var ops: StructuredOps = .init()

    public init(cursorJson: String? = nil) {
        self.cursorJson = cursorJson
    }
}

/// One data source with an incremental checkpoint cursor. `sync` must never
/// full-rescan once a cursor exists, and must be safe to re-run (the store's
/// external-id unique key + deterministic graph ids absorb replays).
public protocol WorldConnector: Sendable {
    var worldId: String { get }
    func sync(cursorJson: String?) async throws -> WorldSyncResult
}

public enum WorldError: Error, LocalizedError {
    case accessDenied(String)
    case needsFullDiskAccess

    public var errorDescription: String? {
        switch self {
        case .accessDenied(let what): "\(what) access not granted"
        case .needsFullDiskAccess: "Needs Full Disk Access"
        }
    }
}

/// Codable cursor <-> JSON envelope stored in world.cursor_json.
public enum WorldCursor {
    public static func decode<T: Codable>(_ json: String?, as type: T.Type) -> T? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    public static func encode<T: Codable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Fingerprint-map diffing for sources with no changelog (openhuman's
/// world-diff): the cursor stores `[itemID: contentHash]`; a sync diffs the
/// fresh map against it.
public enum SnapshotDiff {
    public static func hash(_ parts: [String]) -> String {
        let digest = SHA256.hash(data: Data(parts.joined(separator: "\u{1f}").utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    public static func diff(old: [String: String], new: [String: String])
        -> (added: [String], changed: [String], removed: [String]) {
        var added: [String] = [], changed: [String] = [], removed: [String] = []
        for (id, fp) in new {
            switch old[id] {
            case nil: added.append(id)
            case fp: break
            default: changed.append(id)
            }
        }
        for id in old.keys where new[id] == nil { removed.append(id) }
        return (added, changed, removed)
    }
}

import GRDB

/// Shared read-only access to another app's SQLite store. Tries a direct
/// read-only open first (when allowed); on lock/permission refusal copies the
/// db plus its -wal and -shm sidecars to scratch and reads the copy. One
/// implementation so a WAL/sidecar bug gets fixed once, not three times.
public enum ForeignSQLite {
    public static func openReadOnly(_ source: URL, copyName: String, scratch: URL,
                                    directFirst: Bool = true) throws -> DatabaseQueue {
        var config = Configuration()
        config.readonly = true
        if directFirst, let direct = try? DatabaseQueue(path: source.path, configuration: config) {
            return direct
        }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let copy = scratch.appendingPathComponent("\(copyName)-copy.db")
        try? FileManager.default.removeItem(at: copy)
        try FileManager.default.copyItem(at: source, to: copy)
        for suffix in ["-wal", "-shm"] {
            let side = URL(fileURLWithPath: source.path + suffix)
            let sideCopy = URL(fileURLWithPath: copy.path + suffix)
            try? FileManager.default.removeItem(at: sideCopy)
            if FileManager.default.fileExists(atPath: side.path) {
                try? FileManager.default.copyItem(at: side, to: sideCopy)
            }
        }
        return try DatabaseQueue(path: copy.path, configuration: config)
    }
}

/// Core Data / Apple epoch (2001-01-01) helpers used by chat.db, NoteStore,
/// and Safari History timestamps.
public enum AppleEpoch {
    public static func date(fromSeconds t: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: t)
    }

    /// chat.db stores nanoseconds since 2001 (post-High Sierra).
    public static func date(fromNanoseconds t: Int64) -> Date {
        Date(timeIntervalSinceReferenceDate: Double(t) / 1_000_000_000)
    }

    /// Chrome stores microseconds since 1601-01-01.
    public static func date(fromChromeMicroseconds t: Int64) -> Date {
        Date(timeIntervalSince1970: Double(t) / 1_000_000 - 11_644_473_600)
    }
}
