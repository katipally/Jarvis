import Foundation
import JStore

/// Spills oversized tool output to disk and reads it back on demand.
struct ArtifactStore: Sendable {
    let database: JarvisDatabase
    let directory: URL

    init(database: JarvisDatabase, directory: URL) {
        self.database = database
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Returns a reference like `artifact:<id>` the model can pass to
    /// `read_artifact`, plus the row id for tool_call bookkeeping.
    func spill(runID: String, toolName: String, content: String) async -> (ref: String, artifactID: String) {
        let id = UUID().uuidString
        let path = directory.appendingPathComponent("\(id).txt")
        try? content.write(to: path, atomically: true, encoding: .utf8)
        let row = ArtifactRow(
            id: id, kind: "spill", runId: runID, path: path.path,
            filename: "\(toolName)-output.txt", mime: "text/plain",
            bytes: content.utf8.count, preview: String(content.prefix(200))
        )
        await database.loggingWrite("artifact.spill") { try row.insert($0) }
        return ("artifact:\(id)", id)
    }

    func read(ref: String) async -> String? {
        let id = ref.hasPrefix("artifact:") ? String(ref.dropFirst("artifact:".count)) : ref
        guard let row = try? await database.reader.read({ try ArtifactRow.fetchOne($0, key: id) }) else {
            return nil
        }
        return try? String(contentsOfFile: row.path, encoding: .utf8)
    }
}
