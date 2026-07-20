import Foundation
import GRDB
import JStore

/// Query-seeded, hub-avoiding multi-hop BFS over the live graph (Hive
/// traverse.ts port) → up to `limit` facts phrased "src rel dst". Seeds from
/// entities whose name matches the query, expands up to `depth` hops, but never
/// expands THROUGH a super-connector hub (p90 degree, floored at 8) so one busy
/// node can't drag the whole graph into every answer.
public enum Traverse {
    struct GraphEdge {
        let src: String, dst: String, srcName: String, dstName: String
        let rel: String, confidence: Double
    }

    public static func graphFacts(_ db: Database, query: String, limit: Int = 12, depth: Int = 2) throws -> [String] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT e.src_id AS src, e.dst_id AS dst, s.name AS srcName, d.name AS dstName,
                   e.rel AS rel, e.confidence AS confidence
            FROM edge e
            JOIN entity s ON s.id = e.src_id
            JOIN entity d ON d.id = e.dst_id
            WHERE e.invalidated_at IS NULL
            """)
        let edges = rows.map {
            GraphEdge(src: $0["src"], dst: $0["dst"], srcName: $0["srcName"],
                      dstName: $0["dstName"], rel: $0["rel"], confidence: $0["confidence"])
        }
        guard !edges.isEmpty else { return [] }

        var adj: [String: [GraphEdge]] = [:]
        var deg: [String: Int] = [:]
        var nameOf: [String: String] = [:]
        for e in edges {
            adj[e.src, default: []].append(e)
            adj[e.dst, default: []].append(e)
            deg[e.src, default: 0] += 1
            deg[e.dst, default: 0] += 1
            nameOf[e.src] = e.srcName
            nameOf[e.dst] = e.dstName
        }

        let degrees = deg.values.sorted()
        let p90 = degrees[min(degrees.count - 1, Int(Double(degrees.count) * 0.9))]
        let hubCut = max(8, p90)

        let q = Set(queryTokens(query))
        let seeds = nameOf.filter { !q.isDisjoint(with: queryTokens($0.value)) }.map(\.key)
        // Query matched no entity → no graph lines. (Hive falls back to the
        // whole subgraph, but its graphs are member-scoped and tiny; here that
        // would BFS everything on every unrelated question.)
        guard !seeds.isEmpty else { return [] }

        var seen = Set<String>()
        var have = Set<String>()
        var collected: [GraphEdge] = []
        var frontier = seeds
        var d = 0
        while d < depth, !frontier.isEmpty {
            var next: [String] = []
            for node in frontier where !seen.contains(node) {
                seen.insert(node)
                for e in adj[node] ?? [] {
                    let key = "\(e.src)|\(e.rel)|\(e.dst)"
                    if !have.contains(key) {
                        have.insert(key)
                        collected.append(e)
                    }
                    let other = e.src == node ? e.dst : e.src
                    if !seen.contains(other), (deg[other] ?? 0) <= hubCut { next.append(other) }
                }
            }
            frontier = next
            d += 1
        }

        return collected
            .sorted { $0.confidence > $1.confidence }
            .prefix(limit)
            .map { "\($0.srcName) \($0.rel.replacingOccurrences(of: "_", with: " ")) \($0.dstName)" }
    }
}
