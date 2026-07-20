import Foundation
import GRDB
import JStore

/// Read-only projection of the knowledge graph for the UI.
public struct GraphReader: Sendable {
    private let database: JarvisDatabase

    public init(database: JarvisDatabase) { self.database = database }

    public struct Node: Sendable, Identifiable, Equatable {
        public let id: String
        public let name: String
        public let kind: String // entity type: person | org | place | event | topic | project | thing
        public let isCurrent: Bool
    }

    public struct Edge: Sendable, Identifiable, Equatable {
        public let id: String
        public let source: String
        public let target: String
        public let relation: String
        public let isCurrent: Bool // invalidated_at == nil
    }

    public struct Snapshot: Sendable, Equatable {
        public let nodes: [Node]
        public let edges: [Edge]

        public init(nodes: [Node], edges: [Edge]) {
            self.nodes = nodes
            self.edges = edges
        }
    }

    /// Load the graph. `includeHistory` also returns invalidated (past-era) edges.
    public func snapshot(includeHistory: Bool = false, limit: Int = 200) async -> Snapshot {
        (try? await database.reader.read { db -> Snapshot in
            let nodeRows = try EntityRow.order(Column("created_at").desc).limit(limit).fetchAll(db)
            let nodes = nodeRows.map {
                Node(id: $0.id, name: $0.name, kind: $0.type, isCurrent: true)
            }
            let nodeIDs = Set(nodes.map(\.id))

            let edgeRows = try EdgeRow.order(Column("created_at").desc).limit(limit * 3).fetchAll(db)
            let edges = edgeRows
                .filter { (includeHistory || $0.invalidatedAt == nil) && nodeIDs.contains($0.srcId) && nodeIDs.contains($0.dstId) }
                .map { Edge(id: $0.id, source: $0.srcId, target: $0.dstId, relation: $0.rel, isCurrent: $0.invalidatedAt == nil) }
            return Snapshot(nodes: nodes, edges: edges)
        }) ?? Snapshot(nodes: [], edges: [])
    }

    /// Facts sourced by / superseding around an entity — the provenance chain
    /// for the node inspector. Returns "src rel dst" lines plus source facts.
    public func neighborhood(entityID: String, limit: Int = 12) async -> [String] {
        (try? await database.reader.read { db -> [String] in
            let rows = try Row.fetchAll(db, sql: """
                SELECT s.name AS srcName, e.rel AS rel, d.name AS dstName
                FROM edge e
                JOIN entity s ON s.id = e.src_id
                JOIN entity d ON d.id = e.dst_id
                WHERE (e.src_id = ? OR e.dst_id = ?) AND e.invalidated_at IS NULL
                ORDER BY e.created_at DESC LIMIT ?
                """, arguments: [entityID, entityID, limit])
            return rows.map {
                let rel: String = $0["rel"]
                return "\($0["srcName"] as String) \(rel.replacingOccurrences(of: "_", with: " ")) \($0["dstName"] as String)"
            }
        }) ?? []
    }
}
