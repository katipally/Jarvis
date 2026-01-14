import Foundation
import AppKit

@available(macOS 13.0, *)
@MainActor
class JarvisIntentHandler: ObservableObject {
    static let shared = JarvisIntentHandler()
    
    private let macControlService = MacControlService.shared
    private let accessibilityService = AccessibilityService.shared
    private let inputSimulator = InputSimulator.shared
    
    private init() {}
    
    // MARK: - Process Natural Language Query
    func processQuery(_ query: String) async -> String {
        do {
            let url = URL(string: "\(Config.apiBaseURL)/chat/stream")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 60
            
            let body: [String: Any] = [
                "messages": [["role": "user", "content": query]],
                "file_ids": [],
                "include_reasoning": false
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (bytes, _) = try await URLSession.shared.bytes(for: request)
            var response = ""
            
            for try await line in bytes.lines {
                if line.hasPrefix("data: ") {
                    let data = String(line.dropFirst(6))
                    if let eventData = data.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
                       let type = json["type"] as? String,
                       type == "content",
                       let content = json["content"] as? String {
                        response += content
                    }
                }
            }
            
            return response.isEmpty ? "I processed your request." : response
        } catch {
            return "Error processing query: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Open Application
    func openApp(_ appName: String) async -> String {
        let script = """
        tell application "\(appName)"
            activate
        end tell
        """
        
        let result = await macControlService.executeAppleScript(script)
        return result.success ? "Opened \(appName)" : "Failed to open \(appName): \(result.error ?? "Unknown error")"
    }
    
    // MARK: - Control Media
    func controlMedia(_ action: MediaAction) async -> String {
        let script: String
        switch action {
        case .play:
            script = """
            tell application "Music"
                play
            end tell
            """
        case .pause:
            script = """
            tell application "Music"
                pause
            end tell
            """
        case .next:
            script = """
            tell application "Music"
                next track
            end tell
            """
        case .previous:
            script = """
            tell application "Music"
                previous track
            end tell
            """
        case .stop:
            script = """
            tell application "Music"
                stop
            end tell
            """
        }
        
        let result = await macControlService.executeAppleScript(script)
        return result.success ? "Media: \(action.rawValue)" : "Failed: \(result.error ?? "Unknown error")"
    }
    
    // MARK: - Set Volume
    func setVolume(_ level: Int) async -> String {
        let script = "set volume output volume \(level)"
        let result = await macControlService.executeAppleScript(script)
        return result.success ? "Volume set to \(level)%" : "Failed to set volume: \(result.error ?? "Unknown error")"
    }
    
    // MARK: - Take Screenshot
    func takeScreenshot(_ type: ScreenshotType) async -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let desktopPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("Screenshot_\(timestamp).png")
            .path
        
        let command: String
        switch type {
        case .fullScreen:
            command = "screencapture -x \"\(desktopPath)\""
        case .window:
            command = "screencapture -x -w \"\(desktopPath)\""
        case .selection:
            command = "screencapture -x -s \"\(desktopPath)\""
        }
        
        let result = await macControlService.executeShellCommand(command)
        return result.success ? desktopPath : "Failed to capture: \(result.error ?? "Unknown error")"
    }
    
    // MARK: - Toggle Dark Mode
    func toggleDarkMode() async -> String {
        let script = """
        tell application "System Events"
            tell appearance preferences
                set dark mode to not dark mode
                return dark mode
            end tell
        end tell
        """
        
        let result = await macControlService.executeAppleScript(script)
        if result.success {
            let isDark = result.output?.contains("true") ?? false
            return "Dark mode \(isDark ? "enabled" : "disabled")"
        }
        return "Failed to toggle dark mode: \(result.error ?? "Unknown error")"
    }
    
    // MARK: - Get System Info
    func getSystemInfo(_ type: SystemInfoType) async -> String {
        switch type {
        case .battery:
            let result = await macControlService.executeShellCommand("pmset -g batt | grep -o '[0-9]*%'")
            return result.success ? "Battery: \(result.output ?? "Unknown")" : "Failed to get battery info"
            
        case .wifi:
            let script = """
            do shell script "networksetup -getairportnetwork en0 | cut -d: -f2 | xargs"
            """
            let result = await macControlService.executeAppleScript(script)
            return result.success ? "WiFi: \(result.output ?? "Not connected")" : "Failed to get WiFi info"
            
        case .storage:
            let result = await macControlService.executeShellCommand("df -h / | tail -1 | awk '{print $4 \" available of \" $2}'")
            return result.success ? "Storage: \(result.output ?? "Unknown")" : "Failed to get storage info"
            
        case .memory:
            let result = await macControlService.executeShellCommand("vm_stat | head -5")
            return result.success ? "Memory info retrieved" : "Failed to get memory info"
            
        case .all:
            let battery = await getSystemInfo(.battery)
            let wifi = await getSystemInfo(.wifi)
            let storage = await getSystemInfo(.storage)
            return "\(battery)\n\(wifi)\n\(storage)"
        }
    }
    
    // MARK: - Run Automation Script
    func runAutomation(scriptId: String, parameters: String?) async -> String {
        do {
            let url = URL(string: "\(Config.apiBaseURL)/mac/run-script")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            var body: [String: Any] = ["script_id": scriptId]
            if let params = parameters,
               let paramsData = params.data(using: .utf8),
               let paramsDict = try? JSONSerialization.jsonObject(with: paramsData) as? [String: Any] {
                body["parameters"] = paramsDict
            }
            
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? String {
                return result
            }
            return "Automation completed"
        } catch {
            return "Failed to run automation: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Click UI Element
    func clickElement(appName: String, elementDescription: String) async -> String {
        let result = await accessibilityService.clickElement(
            appName: appName,
            elementDescription: elementDescription
        )
        return result
    }
    
    // MARK: - Type Text
    func typeText(_ text: String) async -> String {
        let success = await inputSimulator.typeText(text)
        return success ? "Typed: \(text)" : "Failed to type text"
    }
}

// MARK: - Mac Control Service
@MainActor
class MacControlService: ObservableObject {
    static let shared = MacControlService()
    
    struct ExecutionResult {
        let success: Bool
        let output: String?
        let error: String?
    }
    
    private init() {}
    
    func executeAppleScript(_ script: String) async -> ExecutionResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let appleScript = NSAppleScript(source: script)
                let result = appleScript?.executeAndReturnError(&error)
                
                DispatchQueue.main.async {
                    if let error = error {
                        let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                        continuation.resume(returning: ExecutionResult(success: false, output: nil, error: errorMessage))
                    } else {
                        let output = result?.stringValue
                        continuation.resume(returning: ExecutionResult(success: true, output: output, error: nil))
                    }
                }
            }
        }
    }
    
    func executeShellCommand(_ command: String) async -> ExecutionResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                let errorPipe = Pipe()
                
                process.standardOutput = pipe
                process.standardError = errorPipe
                process.arguments = ["-c", command]
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    DispatchQueue.main.async {
                        if process.terminationStatus == 0 {
                            continuation.resume(returning: ExecutionResult(success: true, output: output, error: nil))
                        } else {
                            continuation.resume(returning: ExecutionResult(success: false, output: output, error: errorOutput))
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        continuation.resume(returning: ExecutionResult(success: false, output: nil, error: error.localizedDescription))
                    }
                }
            }
        }
    }
}
