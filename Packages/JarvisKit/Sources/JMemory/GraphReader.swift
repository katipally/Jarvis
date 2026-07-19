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
        public let kind: String
        public let isCurrent: Bool // valid_to == nil
    }

    public struct Edge: Sendable, Identifiable, Equatable {
        public let id: String
        public let source: String
        public let target: String
        public let relation: String
        public let isCurrent: Bool
    }

    public struct Snapshot: Sendable, Equatable {
        public let nodes: [Node]
        public let edges: [Edge]

        public init(nodes: [Node], edges: [Edge]) {
            self.nodes = nodes
            self.edges = edges
        }
    }

    /// Load the graph. `includeHistory` also returns superseded (past-era) items.
    public func snapshot(includeHistory: Bool = false, limit: Int = 200) async -> Snapshot {
        (try? await database.reader.read { db -> Snapshot in
            let nodeRows = try GraphNodeRow.order(Column("created_at").desc).limit(limit).fetchAll(db)
            let nodes = nodeRows
                .filter { includeHistory || $0.validTo == nil }
                .map { Node(id: $0.id, name: $0.name, kind: $0.kind, isCurrent: $0.validTo == nil) }
            let nodeIDs = Set(nodes.map(\.id))

            let edgeRows = try GraphEdgeRow.order(Column("created_at").desc).limit(limit * 3).fetchAll(db)
            let edges = edgeRows
                .filter { (includeHistory || $0.validTo == nil) && nodeIDs.contains($0.srcId) && nodeIDs.contains($0.dstId) }
                .map { Edge(id: $0.id, source: $0.srcId, target: $0.dstId, relation: $0.relation, isCurrent: $0.validTo == nil) }
            return Snapshot(nodes: nodes, edges: edges)
        }) ?? Snapshot(nodes: [], edges: [])
    }
}
