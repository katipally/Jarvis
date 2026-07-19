import JAgent
import Observation

/// Bridges the actor-based ApprovalGate to the notch UI. The gate's `present`
/// callback enqueues here; the UI reads `current` and calls `resolve`.
@MainActor
@Observable
final class ApprovalPresenter {
    private(set) var queue: [ApprovalRequest] = []
    var gate: ApprovalGate?

    var current: ApprovalRequest? { queue.first }

    func enqueue(_ request: ApprovalRequest) {
        queue.append(request)
    }

    func resolve(_ request: ApprovalRequest, _ decision: ApprovalDecision) {
        queue.removeAll { $0.id == request.id }
        let gate = gate
        Task { await gate?.resolve(request.id, decision) }
    }

    /// Gate-initiated removal (timeout / run cancelled) — the card must never
    /// outlive its continuation, or its buttons resolve nothing.
    func dismiss(_ id: String) {
        queue.removeAll { $0.id == id }
    }
}
