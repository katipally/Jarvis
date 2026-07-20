import Foundation
import JKnowledge

/// Watched folders: text-ish files (md/txt) become episodes when they change.
/// Cursor = per-file mtime map. Folder list comes from settings (the app is
/// not sandboxed, so plain paths suffice).
public struct FolderWorld: WorldConnector {
    public let worldId = "folders"
    let paths: [String]

    public init(paths: [String]) {
        self.paths = paths
    }

    struct Cursor: Codable {
        var mtimes: [String: Double] = [:]
    }

    static let extensions: Set<String> = ["md", "txt", "markdown"]
    static let maxPerSync = 50
    static let maxBytes = 64 * 1024

    public func sync(cursorJson: String?) async throws -> WorldSyncResult {
        var cursor = WorldCursor.decode(cursorJson, as: Cursor.self) ?? Cursor()
        var result = WorldSyncResult()
        var emitted = 0

        for root in paths {
            let rootURL = URL(fileURLWithPath: (root as NSString).expandingTildeInPath)
            let enumerator = FileManager.default.enumerator(
                at: rootURL, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            while let url = enumerator?.nextObject() as? URL {
                guard emitted < Self.maxPerSync else { break }
                guard Self.extensions.contains(url.pathExtension.lowercased()) else { continue }
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                guard let mtime = values?.contentModificationDate?.timeIntervalSince1970,
                      (values?.fileSize ?? 0) <= Self.maxBytes else { continue }
                let key = url.path
                guard mtime > (cursor.mtimes[key] ?? 0) else { continue }
                cursor.mtimes[key] = mtime
                guard let content = try? String(contentsOf: url, encoding: .utf8),
                      content.count > 40 else { continue }
                result.episodes.append(EpisodeDraft(
                    externalId: "file:\(key):\(Int(mtime))",
                    occurredAt: Date(timeIntervalSince1970: mtime),
                    title: url.lastPathComponent,
                    content: "Document \(url.lastPathComponent):\n\n" + content.prefix(8000)
                ))
                emitted += 1
            }
        }
        result.cursorJson = WorldCursor.encode(cursor)
        return result
    }
}
