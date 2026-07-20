import Foundation

// Cheap deterministic guards that run BEFORE any model call (openhuman
// registry.rs): dedupe window, then per-source token bucket. A duplicate is
// dropped before it consumes a rate token.

/// TTL'd dedupe: the same dedupe_key within the window is a duplicate.
public struct DedupeWindow: Sendable {
    public var ttl: TimeInterval
    var seen: [String: Date] = [:]

    public init(ttl: TimeInterval = 300) {
        self.ttl = ttl
    }

    /// True when the key is fresh (and records it). Lazy eviction.
    public mutating func admit(_ key: String, now: Date = .now) -> Bool {
        seen = seen.filter { now.timeIntervalSince($0.value) < ttl }
        if let last = seen[key], now.timeIntervalSince(last) < ttl { return false }
        seen[key] = now
        return true
    }
}

/// Per-source-family token bucket: capacity 30, refill 1/s.
public struct RateLimiter: Sendable {
    public var capacity: Double
    public var refillPerSecond: Double
    var buckets: [String: (tokens: Double, at: Date)] = [:]

    public init(capacity: Double = 30, refillPerSecond: Double = 1) {
        self.capacity = capacity
        self.refillPerSecond = refillPerSecond
    }

    public mutating func admit(family: String, now: Date = .now) -> Bool {
        var (tokens, at) = buckets[family] ?? (capacity, now)
        tokens = min(capacity, tokens + now.timeIntervalSince(at) * refillPerSecond)
        guard tokens >= 1 else {
            buckets[family] = (tokens, now)
            return false
        }
        buckets[family] = (tokens - 1, now)
        return true
    }
}

public enum AdmissionVerdict: Sendable, Equatable {
    case admitted, duplicate, rateLimited
}

public struct TriggerAdmission: Sendable {
    var dedupe: DedupeWindow
    var rate: RateLimiter

    public init(dedupeTTL: TimeInterval = 300, capacity: Double = 30, refillPerSecond: Double = 1) {
        self.dedupe = DedupeWindow(ttl: dedupeTTL)
        self.rate = RateLimiter(capacity: capacity, refillPerSecond: refillPerSecond)
    }

    public mutating func admit(_ trigger: Trigger, now: Date = .now) -> AdmissionVerdict {
        guard dedupe.admit(trigger.dedupeKey, now: now) else { return .duplicate }
        guard rate.admit(family: trigger.source, now: now) else { return .rateLimited }
        return .admitted
    }
}

/// Sliding-hour promotion budget (openhuman gate.rs): when exhausted, a
/// would-be promote is DOWNGRADED to acknowledge — never silently discarded.
public struct PromotionBudget: Sendable {
    public var maxPerHour: Int
    var timestamps: [Date] = []

    public init(maxPerHour: Int = 30) {
        self.maxPerHour = maxPerHour
    }

    public mutating func tryConsume(now: Date = .now) -> Bool {
        guard maxPerHour > 0 else { return false }
        timestamps = timestamps.filter { now.timeIntervalSince($0) < 3600 }
        guard timestamps.count < maxPerHour else { return false }
        timestamps.append(now)
        return true
    }
}
