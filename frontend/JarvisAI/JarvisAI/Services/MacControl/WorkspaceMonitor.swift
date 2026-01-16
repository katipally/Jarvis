import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
class WorkspaceMonitor: ObservableObject {
    static let shared = WorkspaceMonitor()
    
    // MARK: - Published State
    @Published var runningApps: [AppInfo] = []
    @Published var frontmostApp: AppInfo?
    @Published var recentEvents: [WorkspaceEvent] = []
    @Published var isMonitoring = false
    
    // MARK: - Private
    private var observers: [NSObjectProtocol] = []
    private let workspace = NSWorkspace.shared
    private let notificationCenter: NotificationCenter
    
    private init() {
        self.notificationCenter = workspace.notificationCenter
        refreshRunningApps()
    }
    
    // MARK: - Start Monitoring
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        // App Launch
        observers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    self?.handleAppLaunch(notification)
                }
            }
        )
        
        // App Termination
        observers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    self?.handleAppTermination(notification)
                }
            }
        )
        
        // App Activation (became frontmost)
        observers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    self?.handleAppActivation(notification)
                }
            }
        )
        
        // App Deactivation
        observers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.didDeactivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    self?.handleAppDeactivation(notification)
                }
            }
        )
        
        // App Hidden
        observers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.didHideApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    self?.handleAppHidden(notification)
                }
            }
        )
        
        // App Unhidden
        observers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.didUnhideApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    self?.handleAppUnhidden(notification)
                }
            }
        )
        
        // Screen Sleep
        observers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.screensDidSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.addEvent(.screenSleep)
                }
            }
        )
        
        // Screen Wake
        observers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.addEvent(.screenWake)
                }
            }
        )
        
        // System Sleep
        observers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.addEvent(.systemWillSleep)
                }
            }
        )
        
        // System Wake
        observers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.addEvent(.systemDidWake)
                }
            }
        )
        
        // Volume Mount
        observers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.didMountNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    if let path = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
                        self?.addEvent(.volumeMounted(path: path.path))
                    }
                }
            }
        )
        
        // Volume Unmount
        observers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.didUnmountNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    if let path = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
                        self?.addEvent(.volumeUnmounted(path: path.path))
                    }
                }
            }
        )
        
        // Session Activity (user switch)
        observers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.sessionDidBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.addEvent(.sessionBecameActive)
                }
            }
        )
        
        observers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.sessionDidResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.addEvent(.sessionResignedActive)
                }
            }
        )
        
        print("[WorkspaceMonitor] Started monitoring workspace events")
    }
    
    // MARK: - Stop Monitoring
    func stopMonitoring() {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        isMonitoring = false
        print("[WorkspaceMonitor] Stopped monitoring workspace events")
    }
    
    // MARK: - App Info Methods
    func refreshRunningApps() {
        runningApps = workspace.runningApplications
            .filter { !$0.isTerminated && $0.activationPolicy == .regular }
            .compactMap { AppInfo(from: $0) }
        
        if let frontmost = workspace.frontmostApplication {
            frontmostApp = AppInfo(from: frontmost)
        }
    }
    
    func getRunningApps() -> [AppInfo] {
        refreshRunningApps()
        return runningApps
    }
    
    func getFrontmostApp() -> AppInfo? {
        if let frontmost = workspace.frontmostApplication {
            return AppInfo(from: frontmost)
        }
        return nil
    }
    
    func isAppRunning(bundleIdentifier: String) -> Bool {
        return workspace.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }
    
    func isAppRunning(name: String) -> Bool {
        return workspace.runningApplications.contains { 
            $0.localizedName?.lowercased() == name.lowercased() 
        }
    }
    
    // MARK: - App Control Methods
    func launchApp(bundleIdentifier: String) async -> Bool {
        guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return false
        }
        
        do {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            _ = try await workspace.openApplication(at: appURL, configuration: config)
            return true
        } catch {
            print("[WorkspaceMonitor] Failed to launch app: \(error)")
            return false
        }
    }
    
    func launchApp(name: String) async -> Bool {
        let script = """
        tell application "\(name)"
            activate
        end tell
        """
        let result = await MacControlService.shared.executeAppleScript(script)
        return result.success
    }
    
    func hideApp(bundleIdentifier: String) -> Bool {
        guard let app = workspace.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return false
        }
        return app.hide()
    }
    
    func unhideApp(bundleIdentifier: String) -> Bool {
        guard let app = workspace.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return false
        }
        return app.unhide()
    }
    
    func activateApp(bundleIdentifier: String) -> Bool {
        guard let app = workspace.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return false
        }
        return app.activate(options: [.activateIgnoringOtherApps])
    }
    
    func terminateApp(bundleIdentifier: String) -> Bool {
        guard let app = workspace.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return false
        }
        return app.terminate()
    }
    
    func forceTerminateApp(bundleIdentifier: String) -> Bool {
        guard let app = workspace.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return false
        }
        return app.forceTerminate()
    }
    
    // MARK: - File Operations
    func openFile(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        return workspace.open(url)
    }
    
    func openFile(path: String, withApplication appName: String) -> Bool {
        let fileURL = URL(fileURLWithPath: path)
        
        // Helper to perform the open with error logging
        func open(appURL: URL) {
            workspace.open([fileURL], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error = error {
                    print("[WorkspaceMonitor] Failed to open file with app: \(error.localizedDescription)")
                }
            }
        }

        if let appURL = workspace.urlForApplication(withBundleIdentifier: appName) ?? 
              NSWorkspace.shared.urlsForApplications(withBundleIdentifier: appName).first ??
              workspace.urlForApplication(toOpen: fileURL) {
            open(appURL: appURL)
            return true
        }
        
        // Fallback: try to find app by name
        let apps = NSWorkspace.shared.runningApplications.filter { $0.localizedName == appName }
        if let app = apps.first, let bundleURL = app.bundleURL {
            open(appURL: bundleURL)
            return true
        }
        
        return false
    }
    
    func openURL(_ url: URL) -> Bool {
        return workspace.open(url)
    }
    
    func revealInFinder(path: String) {
        workspace.selectFile(path, inFileViewerRootedAtPath: "")
    }
    
    func moveToTrash(path: String) async -> Bool {
        do {
            try await workspace.recycle([URL(fileURLWithPath: path)])
            return true
        } catch {
            print("[WorkspaceMonitor] Failed to move to trash: \(error)")
            return false
        }
    }
    
    func getIcon(forFile path: String) -> NSImage {
        return workspace.icon(forFile: path)
    }
    
    func getIcon(forApp bundleIdentifier: String) -> NSImage? {
        guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        return workspace.icon(forFile: appURL.path)
    }
    
    // MARK: - System Information
    func getFileType(path: String) -> String? {
        do {
            let resourceValues = try URL(fileURLWithPath: path).resourceValues(forKeys: [.typeIdentifierKey])
            return resourceValues.typeIdentifier
        } catch {
            return nil
        }
    }
    
    func getDefaultApp(forExtension ext: String) -> String? {
        guard UTType(filenameExtension: ext) != nil else { return nil }
        guard let appURL = workspace.urlForApplication(toOpen: URL(fileURLWithPath: "test.\(ext)")) else { return nil }
        return appURL.lastPathComponent.replacingOccurrences(of: ".app", with: "")
    }
    
    // MARK: - Event Handlers
    private func handleAppLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let appInfo = AppInfo(from: app)
        addEvent(.appLaunched(app: appInfo))
        refreshRunningApps()
    }
    
    private func handleAppTermination(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let appInfo = AppInfo(from: app)
        addEvent(.appTerminated(app: appInfo))
        refreshRunningApps()
    }
    
    private func handleAppActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let appInfo = AppInfo(from: app)
        frontmostApp = appInfo
        addEvent(.appActivated(app: appInfo))
    }
    
    private func handleAppDeactivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let appInfo = AppInfo(from: app)
        addEvent(.appDeactivated(app: appInfo))
    }
    
    private func handleAppHidden(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let appInfo = AppInfo(from: app)
        addEvent(.appHidden(app: appInfo))
    }
    
    private func handleAppUnhidden(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let appInfo = AppInfo(from: app)
        addEvent(.appUnhidden(app: appInfo))
    }
    
    private func addEvent(_ event: WorkspaceEvent) {
        recentEvents.insert(event, at: 0)
        if recentEvents.count > 100 {
            recentEvents.removeLast()
        }
        print("[WorkspaceMonitor] Event: \(event.description)")
    }
    
    // MARK: - Get Recent Events
    func getRecentEvents(count: Int = 20) -> [WorkspaceEvent] {
        return Array(recentEvents.prefix(count))
    }
    
    func clearEvents() {
        recentEvents.removeAll()
    }
}

// MARK: - App Info
struct AppInfo: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let bundleIdentifier: String?
    let processIdentifier: Int32
    let isActive: Bool
    let isHidden: Bool
    let launchDate: Date?
    
    init(from app: NSRunningApplication) {
        self.id = UUID()
        self.name = app.localizedName ?? "Unknown"
        self.bundleIdentifier = app.bundleIdentifier
        self.processIdentifier = app.processIdentifier
        self.isActive = app.isActive
        self.isHidden = app.isHidden
        self.launchDate = app.launchDate
    }
    
    var description: String {
        return "\(name) (\(bundleIdentifier ?? "unknown"))"
    }
}

// MARK: - Workspace Event
enum WorkspaceEvent: Identifiable {
    case appLaunched(app: AppInfo)
    case appTerminated(app: AppInfo)
    case appActivated(app: AppInfo)
    case appDeactivated(app: AppInfo)
    case appHidden(app: AppInfo)
    case appUnhidden(app: AppInfo)
    case screenSleep
    case screenWake
    case systemWillSleep
    case systemDidWake
    case volumeMounted(path: String)
    case volumeUnmounted(path: String)
    case sessionBecameActive
    case sessionResignedActive
    
    var id: UUID { UUID() }
    
    var description: String {
        switch self {
        case .appLaunched(let app): return "App Launched: \(app.name)"
        case .appTerminated(let app): return "App Terminated: \(app.name)"
        case .appActivated(let app): return "App Activated: \(app.name)"
        case .appDeactivated(let app): return "App Deactivated: \(app.name)"
        case .appHidden(let app): return "App Hidden: \(app.name)"
        case .appUnhidden(let app): return "App Unhidden: \(app.name)"
        case .screenSleep: return "Screen Sleep"
        case .screenWake: return "Screen Wake"
        case .systemWillSleep: return "System Will Sleep"
        case .systemDidWake: return "System Did Wake"
        case .volumeMounted(let path): return "Volume Mounted: \(path)"
        case .volumeUnmounted(let path): return "Volume Unmounted: \(path)"
        case .sessionBecameActive: return "Session Became Active"
        case .sessionResignedActive: return "Session Resigned Active"
        }
    }
    
    var timestamp: Date { Date() }
}
