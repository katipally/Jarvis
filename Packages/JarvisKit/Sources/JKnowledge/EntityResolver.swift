import CryptoKit
import Foundation
import GRDB
import JStore

// Embedding-free entity resolution (Hive's port of graphify's dedup, minus the
// LSH stage we don't need at this scale): a normalized key merges case/spacing/
// punctuation variants ("New York" = "new-york" = "NewYork"), then a
// conservative fuzzy pass catches typos ("Google" = "Googel") — guarded so it
// never merges genuinely different entities.
public enum EntityResolver {
    /// NFKC → lowercase → keep letters/digits only.
    public static func normName(_ s: String) -> String {
        String(s.precomposedStringWithCompatibilityMapping.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Deterministic id from identity fields (cognee pattern): re-ingesting the
    /// same (type, norm) merges for free, across runs and sources.
    public static func deterministicID(type: EntityType, norm: String) -> String {
        let digest = SHA256.hash(data: Data("\(type.rawValue)\u{1f}\(norm)".utf8))
        return "ent_" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Fuzzy matching

    static func jaro(_ s1: [Character], _ s2: [Character]) -> Double {
        let len1 = s1.count, len2 = s2.count
        guard len1 > 0, len2 > 0 else { return 0 }
        let md = max(0, max(len1, len2) / 2 - 1)
        var m1 = [Bool](repeating: false, count: len1)
        var m2 = [Bool](repeating: false, count: len2)
        var matches = 0
        for i in 0..<len1 {
            let lo = max(0, i - md), hi = min(i + md + 1, len2)
            for j in lo..<hi where !m2[j] && s1[i] == s2[j] {
                m1[i] = true
                m2[j] = true
                matches += 1
                break
            }
        }
        guard matches > 0 else { return 0 }
        var t = 0.0, k = 0
        for i in 0..<len1 where m1[i] {
            while !m2[k] { k += 1 }
            if s1[i] != s2[k] { t += 1 }
            k += 1
        }
        t /= 2
        let m = Double(matches)
        return (m / Double(len1) + m / Double(len2) + (m - t) / m) / 3
    }

    public static func jaroWinkler(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let ca = Array(a), cb = Array(b)
        let j = jaro(ca, cb)
        var p = 0
        while p < 4, p < ca.count, p < cb.count, ca[p] == cb[p] { p += 1 }
        return j + Double(p) * 0.1 * (1 - j)
    }

    /// Guardrails that HARD-block a fuzzy merge regardless of score:
    /// differing numeric tokens ("M1"/"M2", "v1"/"v2") and big length gaps
    /// ("Sam"/"Samuel Jackson" could be different people).
    static func canMerge(_ a: String, _ b: String) -> Bool {
        func nums(_ s: String) -> String {
            s.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .filter { !$0.isEmpty }.sorted().joined(separator: ",")
        }
        if nums(a) != nums(b) { return false }
        let la = Double(a.count), lb = Double(b.count)
        if min(la, lb) / max(la, lb) < 0.6 { return false }
        return true
    }

    static let fuzzyThreshold = 0.94

    /// Resolve a name+type to an existing entity id: exact normalized match →
    /// alias → guarded high-similarity fuzzy among same-type candidates sharing
    /// a normalized prefix (indexed block, cheap as the graph grows). nil → new.
    public static func resolveExisting(_ db: Database, name: String, type: EntityType) throws -> String? {
        let n = normName(name)
        guard !n.isEmpty else { return nil }

        if let exact = try EntityRow
            .filter(Column("type") == type.rawValue && Column("norm") == n)
            .fetchOne(db) {
            return exact.id
        }

        // Alias hit (same type only — "Paris" the person ≠ "Paris" the place).
        if let aliased = try Row.fetchOne(db, sql: """
            SELECT e.id AS id FROM entity_alias a JOIN entity e ON e.id = a.entity_id
            WHERE a.alias_norm = ? AND e.type = ? LIMIT 1
            """, arguments: [n, type.rawValue]) {
            return aliased["id"]
        }

        let candidates = try EntityRow
            .filter(Column("type") == type.rawValue)
            .filter(sql: "norm LIKE ?", arguments: [String(n.prefix(4)) + "%"])
            .limit(50)
            .fetchAll(db)
        let la = name.lowercased()
        var best: (id: String, score: Double)?
        for c in candidates {
            let cl = c.name.lowercased()
            let s = jaroWinkler(la, cl)
            if s >= fuzzyThreshold, s > (best?.score ?? 0), canMerge(la, cl) {
                best = (c.id, s)
            }
        }
        return best?.id
    }
}
