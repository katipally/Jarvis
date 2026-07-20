import AppKit
import Foundation

/// Full Disk Access has no request API — you can only probe (try to read a
/// TCC-protected path) and deep-link the user to the settings pane.
enum FullDiskAccess {
    static var granted: Bool {
        // ~/Library/Mail is TCC-protected; listing it succeeds only with FDA.
        let probe = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mail").path
        return (try? FileManager.default.contentsOfDirectory(atPath: probe)) != nil
    }

    static func openSettings() {
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
    }
}
