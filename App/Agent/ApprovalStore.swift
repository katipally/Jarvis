import Foundation
import GRDB
import JAgent
import JStore

/// Persistent approval rules + audit log, backed by JStore.
struct ApprovalStore: ApprovalRuleStore {
    let database: JarvisDatabase

    func matchRule(tool: String, scopeKey: String?) async -> Bool? {
        let rows = (try? await database.reader.read { db in
            try ApprovalRuleRow.filter(Column("tool_name") == tool).fetchAll(db)
        }) ?? []
        let now = Date.now
        let live = rows.filter { ($0.expiresAt ?? .distantFuture) > now }
        // A scope-specific rule wins over an any-scope rule.
        if let scoped = live.first(where: { $0.scopeKey == scopeKey }) {
            return scoped.decision == "allow"
        }
        if let anyScope = live.first(where: { $0.scopeKey == nil }) {
            return anyScope.decision == "allow"
        }
        return nil
    }

    func rememberRule(tool: String, scopeKey: String?, allow: Bool) async {
        await database.loggingWrite("approval.rule") { db in
            try ApprovalRuleRow
                .filter(Column("tool_name") == tool && Column("scope_key") == scopeKey)
                .deleteAll(db)
            try ApprovalRuleRow(
                toolName: tool, scopeKey: scopeKey, decision: allow ? "allow" : "deny"
            ).insert(db)
        }
    }

    func logDecision(request: ApprovalRequest, allowed: Bool, by: ApprovalDecider) async {
        await database.loggingWrite("approval.event") { db in
            try ApprovalEventRow(
                runId: request.runID, toolCallId: request.toolCallID, toolName: request.toolName,
                summary: request.summary, allowed: allowed, decidedBy: by.rawValue
            ).insert(db)
        }
    }

    func recentDecisions(limit: Int = 60) async -> [ApprovalEventRow] {
        (try? await database.reader.read { db in
            try ApprovalEventRow.order(Column("created_at").desc).limit(limit).fetchAll(db)
        }) ?? []
    }
}
