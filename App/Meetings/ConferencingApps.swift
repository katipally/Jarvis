import Foundation

/// Known native conferencing apps, matched by bundle identifier. Browser-based
/// calls (Google Meet in a Chrome tab) are intentionally out of scope: detecting
/// them reliably needs window-title / Screen-Recording heuristics we don't want
/// in this opt-in slice. Bundle IDs copied from the omi desktop reference.
enum ConferencingApps {
    /// Bundle IDs of native call apps. Compared case-insensitively.
    static let bundleIDs: Set<String> = [
        "us.zoom.xos",                 // Zoom
        "com.microsoft.teams",         // Microsoft Teams (classic)
        "com.microsoft.teams2",        // Microsoft Teams (new)
        "com.apple.facetime",          // FaceTime
        "cisco-systems.spark",         // Webex App
        "com.cisco.webexmeetingsapp",  // Webex Meetings
        "com.webex.meetingmanager",    // Webex (older)
        "com.tinyspeck.slackmacgap",   // Slack (huddles)
        "com.hnc.discord",             // Discord
        "com.logmein.gotomeeting",     // GoTo Meeting
        "com.logmein.goto",            // GoTo
    ]

    /// Whether a bundle ID belongs to a known native conferencing app.
    static func isConferencingApp(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleIDs.contains(bundleID.lowercased())
    }

    /// Human-readable app name for the "Transcribing — <App>" indicator, falling
    /// back to the OS-reported name when the bundle ID isn't in our nice-name map.
    static func displayName(bundleID: String, fallback: String) -> String {
        switch bundleID.lowercased() {
        case "us.zoom.xos": return "Zoom"
        case "com.microsoft.teams", "com.microsoft.teams2": return "Microsoft Teams"
        case "com.apple.facetime": return "FaceTime"
        case "cisco-systems.spark", "com.cisco.webexmeetingsapp", "com.webex.meetingmanager": return "Webex"
        case "com.tinyspeck.slackmacgap": return "Slack"
        case "com.hnc.discord": return "Discord"
        case "com.logmein.gotomeeting", "com.logmein.goto": return "GoTo"
        default: return fallback
        }
    }
}
