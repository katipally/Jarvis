import AppIntents
import Foundation

// MARK: - Jarvis App Shortcuts Provider
@available(macOS 13.0, *)
struct JarvisShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskJarvisIntent(),
            phrases: [
                "Ask \(.applicationName) something",
                "Hey \(.applicationName)",
                "Talk to \(.applicationName)"
            ],
            shortTitle: "Ask Jarvis",
            systemImageName: "brain.head.profile"
        )
        
        AppShortcut(
            intent: ControlMediaIntent(),
            phrases: [
                "\(.applicationName) \(\.$action) music",
                "Tell \(.applicationName) to \(\.$action)"
            ],
            shortTitle: "Control Media",
            systemImageName: "music.note"
        )
        
        AppShortcut(
            intent: TakeScreenshotIntent(),
            phrases: [
                "Take a screenshot with \(.applicationName)",
                "\(.applicationName) capture screen",
                "Screenshot using \(.applicationName)"
            ],
            shortTitle: "Take Screenshot",
            systemImageName: "camera.viewfinder"
        )
        
        AppShortcut(
            intent: ToggleDarkModeIntent(),
            phrases: [
                "Toggle dark mode with \(.applicationName)",
                "\(.applicationName) switch dark mode",
                "Dark mode \(.applicationName)"
            ],
            shortTitle: "Toggle Dark Mode",
            systemImageName: "moon.fill"
        )
        
        AppShortcut(
            intent: GetSystemInfoIntent(),
            phrases: [
                "Get system info with \(.applicationName)",
                "\(.applicationName) system status",
                "Battery status \(.applicationName)"
            ],
            shortTitle: "System Info",
            systemImageName: "info.circle"
        )
    }
}

// MARK: - Ask Jarvis Intent
@available(macOS 13.0, *)
struct AskJarvisIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Jarvis"
    static var description = IntentDescription("Ask Jarvis to help you with any task")
    static var openAppWhenRun: Bool = false
    
    @Parameter(title: "Query", description: "What would you like Jarvis to do?")
    var query: String
    
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let response = await JarvisIntentHandler.shared.processQuery(query)
        return .result(value: response, dialog: IntentDialog(stringLiteral: response))
    }
}

// MARK: - Open App Intent
@available(macOS 13.0, *)
struct OpenAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Application"
    static var description = IntentDescription("Open any application on your Mac")
    
    @Parameter(title: "App Name", description: "Name of the app to open")
    var appName: String
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await JarvisIntentHandler.shared.openApp(appName)
        return .result(dialog: IntentDialog(stringLiteral: result))
    }
}

// MARK: - Control Media Intent
@available(macOS 13.0, *)
struct ControlMediaIntent: AppIntent {
    static var title: LocalizedStringResource = "Control Media"
    static var description = IntentDescription("Control music playback")
    
    @Parameter(title: "Action", description: "Media action to perform")
    var action: MediaAction
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await JarvisIntentHandler.shared.controlMedia(action)
        return .result(dialog: IntentDialog(stringLiteral: result))
    }
}

@available(macOS 13.0, *)
enum MediaAction: String, AppEnum {
    case play = "play"
    case pause = "pause"
    case next = "next"
    case previous = "previous"
    case stop = "stop"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Media Action"
    static var caseDisplayRepresentations: [MediaAction: DisplayRepresentation] = [
        .play: "Play",
        .pause: "Pause",
        .next: "Next Track",
        .previous: "Previous Track",
        .stop: "Stop"
    ]
}

// MARK: - Set Volume Intent
@available(macOS 13.0, *)
struct SetVolumeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Volume"
    static var description = IntentDescription("Set the system volume level")
    
    @Parameter(title: "Level", description: "Volume level (0-100)", default: 50)
    var level: Int
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let clampedLevel = max(0, min(100, level))
        let result = await JarvisIntentHandler.shared.setVolume(clampedLevel)
        return .result(dialog: IntentDialog(stringLiteral: result))
    }
}

// MARK: - Take Screenshot Intent
@available(macOS 13.0, *)
struct TakeScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Take Screenshot"
    static var description = IntentDescription("Capture the screen")
    
    @Parameter(title: "Type", description: "Type of screenshot", default: .fullScreen)
    var captureType: ScreenshotType
    
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let result = await JarvisIntentHandler.shared.takeScreenshot(captureType)
        return .result(value: result, dialog: IntentDialog(stringLiteral: "Screenshot saved to: \(result)"))
    }
}

@available(macOS 13.0, *)
enum ScreenshotType: String, AppEnum {
    case fullScreen = "full"
    case window = "window"
    case selection = "selection"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Screenshot Type"
    static var caseDisplayRepresentations: [ScreenshotType: DisplayRepresentation] = [
        .fullScreen: "Full Screen",
        .window: "Window",
        .selection: "Selection"
    ]
}

// MARK: - Toggle Dark Mode Intent
@available(macOS 13.0, *)
struct ToggleDarkModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Dark Mode"
    static var description = IntentDescription("Toggle system dark mode")
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await JarvisIntentHandler.shared.toggleDarkMode()
        return .result(dialog: IntentDialog(stringLiteral: result))
    }
}

// MARK: - Get System Info Intent
@available(macOS 13.0, *)
struct GetSystemInfoIntent: AppIntent {
    static var title: LocalizedStringResource = "Get System Info"
    static var description = IntentDescription("Get system information like battery, CPU, memory")
    
    @Parameter(title: "Info Type", description: "Type of system info", default: .battery)
    var infoType: SystemInfoType
    
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let result = await JarvisIntentHandler.shared.getSystemInfo(infoType)
        return .result(value: result, dialog: IntentDialog(stringLiteral: result))
    }
}

@available(macOS 13.0, *)
enum SystemInfoType: String, AppEnum {
    case battery = "battery"
    case wifi = "wifi"
    case storage = "storage"
    case memory = "memory"
    case all = "all"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "System Info Type"
    static var caseDisplayRepresentations: [SystemInfoType: DisplayRepresentation] = [
        .battery: "Battery Status",
        .wifi: "WiFi Status",
        .storage: "Storage Info",
        .memory: "Memory Usage",
        .all: "All System Info"
    ]
}

// MARK: - Run Automation Intent
@available(macOS 13.0, *)
struct RunAutomationIntent: AppIntent {
    static var title: LocalizedStringResource = "Run Automation"
    static var description = IntentDescription("Run a pre-defined automation script")
    
    @Parameter(title: "Script ID", description: "ID of the automation script to run")
    var scriptId: String
    
    @Parameter(title: "Parameters", description: "Optional parameters as JSON", default: nil)
    var parameters: String?
    
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let result = await JarvisIntentHandler.shared.runAutomation(scriptId: scriptId, parameters: parameters)
        return .result(value: result, dialog: IntentDialog(stringLiteral: result))
    }
}

// MARK: - Click Element Intent
@available(macOS 13.0, *)
struct ClickElementIntent: AppIntent {
    static var title: LocalizedStringResource = "Click UI Element"
    static var description = IntentDescription("Click a UI element in an application")
    
    @Parameter(title: "App Name", description: "Name of the target application")
    var appName: String
    
    @Parameter(title: "Element Description", description: "Description of the element to click (e.g., 'Submit button', 'Close')")
    var elementDescription: String
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await JarvisIntentHandler.shared.clickElement(appName: appName, elementDescription: elementDescription)
        return .result(dialog: IntentDialog(stringLiteral: result))
    }
}

// MARK: - Type Text Intent
@available(macOS 13.0, *)
struct TypeTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Type Text"
    static var description = IntentDescription("Type text using keyboard simulation")
    
    @Parameter(title: "Text", description: "Text to type")
    var text: String
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await JarvisIntentHandler.shared.typeText(text)
        return .result(dialog: IntentDialog(stringLiteral: result))
    }
}
