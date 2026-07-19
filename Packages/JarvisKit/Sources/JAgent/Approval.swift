import Foundation

/// A pending permission request surfaced to the notch.
public struct ApprovalRequest: Sendable, Identifiable {
    public let id: String
    public let runID: String
    public let toolCallID: String
    public let toolName: String
    public let scopeKey: String?
    public let summary: String
    public let input: JSONValue

    public init(id: String = UUID().uuidString, runID: String, toolCallID: String,
                toolName: String, scopeKey: String?, summary: String, input: JSONValue) {
        self.id = id
        self.runID = runID
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.scopeKey = scopeKey
        self.summary = summary
        self.input = input
    }
}

public enum ApprovalDecision: Sendable, Equatable {
    case allow(persist: Bool) // persist == "Always allow"
    case deny(persist: Bool)
}

public enum ApprovalDecider: String, Sendable {
    case user, rule, tierAuto, timeout, background, cancelled
}

/// Persistent allow/deny rules + audit log. Implemented by the app over JStore.
public protocol ApprovalRuleStore: Sendable {
    /// true = allow, false = deny, nil = no rule (must ask).
    func matchRule(tool: String, scopeKey: String?) async -> Bool?
    func rememberRule(tool: String, scopeKey: String?, allow: Bool) async
    func logDecision(request: ApprovalRequest, allowed: Bool, by: ApprovalDecider) async
}

/// Fail-closed permission gate. Read-only auto-runs; external-effect tools check
/// a rule, else park on a continuation surfaced to the UI; background runs never
/// prompt (they only ever hold a read-only registry, so this is belt-and-braces).
public actor ApprovalGate {
    private let store: any ApprovalRuleStore
    private let present: @Sendable (ApprovalRequest) -> Void
    private let dismiss: @Sendable (String) -> Void
    private let timeout: Duration

    private var pending: [String: CheckedContinuation<ApprovalDecision, Never>] = [:]
    private var timedOut: Set<String> = []
    private var timeoutTasks: [String: Task<Void, Never>] = [:]

    public init(
        store: any ApprovalRuleStore,
        timeout: Duration = .seconds(120),
        present: @escaping @Sendable (ApprovalRequest) -> Void,
        dismiss: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.store = store
        self.timeout = timeout
        self.present = present
        self.dismiss = dismiss
    }

    public func decide(_ request: ApprovalRequest, tier: RiskTier, isBackground: Bool) async -> (ApprovalDecision, ApprovalDecider) {
        if tier == .readOnly {
            return (.allow(persist: false), .tierAuto)
        }
        if isBackground {
            await store.logDecision(request: request, allowed: false, by: .background)
            return (.deny(persist: false), .background)
        }
        if let ruled = await store.matchRule(tool: request.toolName, scopeKey: request.scopeKey) {
            await store.logDecision(request: request, allowed: ruled, by: .rule)
            return (ruled ? .allow(persist: false) : .deny(persist: false), .rule)
        }

        let decision = await withCheckedContinuation { (continuation: CheckedContinuation<ApprovalDecision, Never>) in
            pending[request.id] = continuation
            present(request)
            scheduleTimeout(request.id)
        }

        let allowed: Bool
        switch decision {
        case .allow(let persist):
            allowed = true
            if persist { await store.rememberRule(tool: request.toolName, scopeKey: request.scopeKey, allow: true) }
        case .deny(let persist):
            allowed = false
            if persist { await store.rememberRule(tool: request.toolName, scopeKey: request.scopeKey, allow: false) }
        }
        let decider: ApprovalDecider = timedOut.remove(request.id) != nil ? .timeout : .user
        await store.logDecision(request: request, allowed: allowed, by: decider)
        return (decision, decider)
    }

    /// Called by the UI when the user taps Approve / Always / Deny.
    public func resolve(_ id: String, _ decision: ApprovalDecision) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        clearTimeout(id)
        continuation.resume(returning: decision)
    }

    /// Fail closed if the run is cancelled while a prompt is outstanding.
    public func cancel(_ id: String) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        clearTimeout(id)
        dismiss(id)
        continuation.resume(returning: .deny(persist: false))
    }

    public func cancelAll() {
        for (id, continuation) in pending {
            clearTimeout(id)
            dismiss(id)
            continuation.resume(returning: .deny(persist: false))
        }
        pending.removeAll()
    }

    private func scheduleTimeout(_ id: String) {
        let timeout = self.timeout
        timeoutTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            await self?.fireTimeout(id)
        }
    }

    private func clearTimeout(_ id: String) {
        timeoutTasks.removeValue(forKey: id)?.cancel()
    }

    private func fireTimeout(_ id: String) {
        timeoutTasks.removeValue(forKey: id)
        guard let continuation = pending.removeValue(forKey: id) else { return }
        timedOut.insert(id)
        dismiss(id) // remove the stale card from the notch
        continuation.resume(returning: .deny(persist: false))
    }
}
