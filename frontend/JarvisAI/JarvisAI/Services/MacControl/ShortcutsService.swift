import Foundation
import AppKit

@MainActor
class ShortcutsService: ObservableObject {
    static let shared = ShortcutsService()
    
    @Published var availableShortcuts: [ShortcutInfo] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private init() {
        Task {
            await loadAvailableShortcuts()
        }
    }
    
    // MARK: - Load Available Shortcuts
    func loadAvailableShortcuts() async {
        isLoading = true
        defer { isLoading = false }
        
        let script = """
        tell application "Shortcuts Events"
            set shortcutList to name of every shortcut
            set output to ""
            repeat with shortcutName in shortcutList
                set output to output & shortcutName & linefeed
            end repeat
            return output
        end tell
        """
        
        let result = await MacControlService.shared.executeAppleScript(script)
        
        if result.success, let output = result.output {
            let names = output.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            availableShortcuts = names.map { ShortcutInfo(name: $0) }
        } else {
            error = result.error
        }
    }
    
    // MARK: - Run Shortcut by Name
    func runShortcut(named name: String, input: String? = nil) async -> ShortcutResult {
        let script: String
        if let input = input {
            script = """
            tell application "Shortcuts Events"
                run shortcut "\(name)" with input "\(input)"
            end tell
            """
        } else {
            script = """
            tell application "Shortcuts Events"
                run shortcut "\(name)"
            end tell
            """
        }
        
        let result = await MacControlService.shared.executeAppleScript(script)
        
        return ShortcutResult(
            success: result.success,
            output: result.output,
            error: result.error
        )
    }
    
    // MARK: - Run Shortcut with Dictionary Input
    func runShortcut(named name: String, inputDict: [String: Any]) async -> ShortcutResult {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: inputDict),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return ShortcutResult(success: false, output: nil, error: "Failed to serialize input")
        }
        
        return await runShortcut(named: name, input: jsonString)
    }
    
    // MARK: - Open Shortcuts App
    func openShortcutsApp() async {
        _ = await MacControlService.shared.executeAppleScript("""
            tell application "Shortcuts"
                activate
            end tell
        """)
    }
    
    // MARK: - Open Specific Shortcut in Editor
    func editShortcut(named name: String) async {
        _ = await MacControlService.shared.executeAppleScript("""
            tell application "Shortcuts"
                activate
            end tell
            delay 0.5
            tell application "System Events"
                tell process "Shortcuts"
                    keystroke "f" using command down
                    delay 0.2
                    keystroke "\(name)"
                    delay 0.3
                    keystroke return
                end tell
            end tell
        """)
    }
    
    // MARK: - Create Shortcut (Opens Shortcuts with new shortcut)
    func createNewShortcut() async {
        _ = await MacControlService.shared.executeAppleScript("""
            tell application "Shortcuts"
                activate
            end tell
            delay 0.5
            tell application "System Events"
                tell process "Shortcuts"
                    keystroke "n" using command down
                end tell
            end tell
        """)
    }
    
    // MARK: - Common Shortcut Workflows
    
    func runMorningRoutine() async -> ShortcutResult {
        return await runShortcut(named: "Morning Routine")
    }
    
    func runWorkSetup() async -> ShortcutResult {
        return await runShortcut(named: "Work Setup")
    }
    
    func runMeetingPrep() async -> ShortcutResult {
        return await runShortcut(named: "Meeting Prep")
    }
    
    func runEndOfDay() async -> ShortcutResult {
        return await runShortcut(named: "End of Day")
    }
    
    // MARK: - Shortcut Suggestions
    func getSuggestedShortcuts(for context: String) -> [String] {
        let lowercased = context.lowercased()
        
        if lowercased.contains("morning") || lowercased.contains("start") {
            return ["Morning Routine", "Work Setup", "Open Daily Apps"]
        } else if lowercased.contains("meeting") {
            return ["Meeting Prep", "Do Not Disturb", "Open Zoom"]
        } else if lowercased.contains("end") || lowercased.contains("finish") {
            return ["End of Day", "Close All Apps", "Summary"]
        } else if lowercased.contains("focus") || lowercased.contains("work") {
            return ["Focus Mode", "Do Not Disturb", "Hide Distractions"]
        }
        
        return availableShortcuts.prefix(5).map { $0.name }
    }
}

// MARK: - Shortcut Info
struct ShortcutInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    var icon: String = "shortcuts"
    var color: String = "blue"
}

// MARK: - Shortcut Result
struct ShortcutResult {
    let success: Bool
    let output: String?
    let error: String?
    
    var description: String {
        if success {
            return output ?? "Shortcut completed successfully"
        } else {
            return "Error: \(error ?? "Unknown error")"
        }
    }
}

// MARK: - Predefined Jarvis Shortcuts
enum JarvisShortcutAction: String, CaseIterable {
    case morningRoutine = "Jarvis Morning Routine"
    case workSetup = "Jarvis Work Setup"
    case meetingMode = "Jarvis Meeting Mode"
    case focusMode = "Jarvis Focus Mode"
    case breakTime = "Jarvis Break Time"
    case endOfDay = "Jarvis End of Day"
    case systemCleanup = "Jarvis System Cleanup"
    case quickCapture = "Jarvis Quick Capture"
    
    var description: String {
        switch self {
        case .morningRoutine:
            return "Open morning apps, check calendar, set up workspace"
        case .workSetup:
            return "Open work apps, arrange windows, set status"
        case .meetingMode:
            return "Prepare for meetings - open Zoom, mute notifications"
        case .focusMode:
            return "Enable Do Not Disturb, close distracting apps"
        case .breakTime:
            return "Lock screen, play relaxing music, set timer"
        case .endOfDay:
            return "Save work, close apps, generate summary"
        case .systemCleanup:
            return "Clear caches, organize desktop, optimize storage"
        case .quickCapture:
            return "Take screenshot, save to organized folder"
        }
    }
    
    var icon: String {
        switch self {
        case .morningRoutine: return "sunrise"
        case .workSetup: return "desktopcomputer"
        case .meetingMode: return "video"
        case .focusMode: return "moon.fill"
        case .breakTime: return "cup.and.saucer"
        case .endOfDay: return "sunset"
        case .systemCleanup: return "trash"
        case .quickCapture: return "camera"
        }
    }
}

// MARK: - Shortcut Builder Helper
struct ShortcutBuilder {
    static func buildWorkspaceSetup(apps: [String], windowLayout: WindowLayout) -> String {
        var actions: [String] = []
        
        for app in apps {
            actions.append("Open \(app)")
        }
        
        switch windowLayout {
        case .sideBySide:
            actions.append("Arrange windows side by side")
        case .stacked:
            actions.append("Stack windows vertically")
        case .grid:
            actions.append("Arrange windows in grid")
        case .focused:
            actions.append("Maximize front window")
        }
        
        return actions.joined(separator: "\n")
    }
    
    enum WindowLayout {
        case sideBySide
        case stacked
        case grid
        case focused
    }
}
