import Foundation
import JStore

/// User-tunable policy for the passive screen buffer. Persisted via `SettingsStore`
/// under `screen_rewind_policy`; `ScreenBuffer` reads a live copy each tick and
/// re-reads it whenever `setPolicy` is called.
public struct ScreenCapturePolicy: Codable, Sendable, Equatable {
    /// Master switch — when false, no frames are captured at all.
    public var enabled: Bool
    /// Retention window in hours. The UI offers 24 / 72 / 168 (1d / 3d / 1wk).
    public var retentionHours: Int
    /// Bundle IDs to never capture, layered on top of the built-in
    /// password-manager blocklist.
    public var excludedBundleIDs: [String]
    /// Disk ceiling in bytes; the oldest frames are swept first once exceeded.
    public var ceilingBytes: Int

    public init(
        enabled: Bool = true,
        retentionHours: Int = 72,
        excludedBundleIDs: [String] = [],
        ceilingBytes: Int = 1_000_000_000
    ) {
        self.enabled = enabled
        self.retentionHours = retentionHours
        self.excludedBundleIDs = excludedBundleIDs
        self.ceilingBytes = ceilingBytes
    }

    public static let `default` = ScreenCapturePolicy()

    /// SettingsStore key the policy is persisted under.
    public static let settingsKey = "screen_rewind_policy"

    /// Load the saved policy, falling back to `.default` when unset or undecodable.
    public static func load(from settings: SettingsStore) async -> ScreenCapturePolicy {
        (try? await settings.get(settingsKey, as: ScreenCapturePolicy.self)) ?? .default
    }

    /// Persist this policy.
    public func save(to settings: SettingsStore) async {
        try? await settings.set(Self.settingsKey, to: self)
    }
}
