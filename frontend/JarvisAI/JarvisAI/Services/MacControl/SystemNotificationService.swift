import Foundation
import AppKit
import Combine

@MainActor
class SystemNotificationService: ObservableObject {
    static let shared = SystemNotificationService()
    
    // MARK: - Published State
    @Published var recentNotifications: [SystemNotification] = []
    @Published var isListening = false
    
    // MARK: - Private
    private var observers: [NSObjectProtocol] = []
    private let distributedCenter = DistributedNotificationCenter.default()
    private let notificationCenter = NotificationCenter.default
    
    private init() {}
    
    // MARK: - Start Listening
    func startListening() {
        guard !isListening else { return }
        isListening = true
        
        // iTunes/Music track change
        observers.append(
            distributedCenter.addObserver(
                forName: NSNotification.Name("com.apple.Music.playerInfo"),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    self?.handleMusicNotification(notification)
                }
            }
        )
        
        // Spotify track change
        observers.append(
            distributedCenter.addObserver(
                forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    self?.handleSpotifyNotification(notification)
                }
            }
        )
        
        // Screen lock/unlock
        observers.append(
            distributedCenter.addObserver(
                forName: NSNotification.Name("com.apple.screenIsLocked"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.addNotification(SystemNotification(
                        name: "Screen Locked",
                        source: "System",
                        type: .screenLock
                    ))
                }
            }
        )
        
        observers.append(
            distributedCenter.addObserver(
                forName: NSNotification.Name("com.apple.screenIsUnlocked"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.addNotification(SystemNotification(
                        name: "Screen Unlocked",
                        source: "System",
                        type: .screenUnlock
                    ))
                }
            }
        )
        
        // Appearance change (dark mode)
        observers.append(
            distributedCenter.addObserver(
                forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    self?.addNotification(SystemNotification(
                        name: "Appearance Changed",
                        source: "System",
                        type: .appearanceChange,
                        userInfo: ["isDarkMode": isDark]
                    ))
                }
            }
        )
        
        // Accessibility status change
        observers.append(
            distributedCenter.addObserver(
                forName: NSNotification.Name("com.apple.accessibility.api"),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    self?.addNotification(SystemNotification(
                        name: "Accessibility Changed",
                        source: "System",
                        type: .accessibilityChange,
                        userInfo: notification.userInfo as? [String: Any]
                    ))
                }
            }
        )
        
        // Display configuration change
        observers.append(
            notificationCenter.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    let screenCount = NSScreen.screens.count
                    self?.addNotification(SystemNotification(
                        name: "Display Configuration Changed",
                        source: "System",
                        type: .displayChange,
                        userInfo: ["screenCount": screenCount]
                    ))
                }
            }
        )
        
        // Time zone change
        observers.append(
            notificationCenter.addObserver(
                forName: NSNotification.Name.NSSystemTimeZoneDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.addNotification(SystemNotification(
                        name: "Time Zone Changed",
                        source: "System",
                        type: .timeZoneChange,
                        userInfo: ["timeZone": TimeZone.current.identifier]
                    ))
                }
            }
        )
        
        // Locale change
        observers.append(
            notificationCenter.addObserver(
                forName: NSLocale.currentLocaleDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.addNotification(SystemNotification(
                        name: "Locale Changed",
                        source: "System",
                        type: .localeChange,
                        userInfo: ["locale": Locale.current.identifier]
                    ))
                }
            }
        )
        
        // Power source change
        observers.append(
            distributedCenter.addObserver(
                forName: NSNotification.Name("com.apple.system.powersources"),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    self?.addNotification(SystemNotification(
                        name: "Power Source Changed",
                        source: "System",
                        type: .powerSourceChange,
                        userInfo: notification.userInfo as? [String: Any]
                    ))
                }
            }
        )
        
        // Bluetooth state change
        observers.append(
            distributedCenter.addObserver(
                forName: NSNotification.Name("IOBluetoothHostControllerPoweredOnNotification"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.addNotification(SystemNotification(
                        name: "Bluetooth Enabled",
                        source: "System",
                        type: .bluetoothChange,
                        userInfo: ["enabled": true]
                    ))
                }
            }
        )
        
        observers.append(
            distributedCenter.addObserver(
                forName: NSNotification.Name("IOBluetoothHostControllerPoweredOffNotification"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.addNotification(SystemNotification(
                        name: "Bluetooth Disabled",
                        source: "System",
                        type: .bluetoothChange,
                        userInfo: ["enabled": false]
                    ))
                }
            }
        )
        
        print("[SystemNotificationService] Started listening to system notifications")
    }
    
    // MARK: - Stop Listening
    func stopListening() {
        for observer in observers {
            distributedCenter.removeObserver(observer)
            notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        isListening = false
        print("[SystemNotificationService] Stopped listening to system notifications")
    }
    
    // MARK: - Post Notification
    func postNotification(name: String, userInfo: [String: Any]? = nil) {
        distributedCenter.postNotificationName(
            NSNotification.Name(name),
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }
    
    // MARK: - Custom Notification Listening
    func listenForNotification(name: String, handler: @escaping ([String: Any]?) -> Void) -> NSObjectProtocol {
        let observer = distributedCenter.addObserver(
            forName: NSNotification.Name(name),
            object: nil,
            queue: .main
        ) { notification in
            handler(notification.userInfo as? [String: Any])
        }
        observers.append(observer)
        return observer
    }
    
    func removeObserver(_ observer: NSObjectProtocol) {
        distributedCenter.removeObserver(observer)
        if let index = observers.firstIndex(where: { $0 === observer }) {
            observers.remove(at: index)
        }
    }
    
    // MARK: - Event Handlers
    private func handleMusicNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo as? [String: Any] else { return }
        
        let name = userInfo["Name"] as? String ?? "Unknown"
        let artist = userInfo["Artist"] as? String ?? "Unknown"
        let album = userInfo["Album"] as? String ?? "Unknown"
        let state = userInfo["Player State"] as? String ?? "Unknown"
        
        addNotification(SystemNotification(
            name: "Music: \(state)",
            source: "Music",
            type: .mediaChange,
            userInfo: [
                "track": name,
                "artist": artist,
                "album": album,
                "state": state
            ]
        ))
    }
    
    private func handleSpotifyNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo as? [String: Any] else { return }
        
        let name = userInfo["Name"] as? String ?? "Unknown"
        let artist = userInfo["Artist"] as? String ?? "Unknown"
        let state = userInfo["Player State"] as? String ?? "Unknown"
        
        addNotification(SystemNotification(
            name: "Spotify: \(state)",
            source: "Spotify",
            type: .mediaChange,
            userInfo: [
                "track": name,
                "artist": artist,
                "state": state
            ]
        ))
    }
    
    private func addNotification(_ notification: SystemNotification) {
        recentNotifications.insert(notification, at: 0)
        if recentNotifications.count > 100 {
            recentNotifications.removeLast()
        }
        print("[SystemNotificationService] Notification: \(notification.name)")
    }
    
    // MARK: - Get Recent Notifications
    func getRecentNotifications(count: Int = 20) -> [SystemNotification] {
        return Array(recentNotifications.prefix(count))
    }
    
    func getNotifications(ofType type: NotificationType) -> [SystemNotification] {
        return recentNotifications.filter { $0.type == type }
    }
    
    func clearNotifications() {
        recentNotifications.removeAll()
    }
    
    // MARK: - System State Queries
    func isDarkModeEnabled() -> Bool {
        return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
    
    func getCurrentTrack() async -> [String: Any]? {
        let script = """
        tell application "Music"
            if player state is playing then
                set trackName to name of current track
                set trackArtist to artist of current track
                set trackAlbum to album of current track
                return trackName & "|" & trackArtist & "|" & trackAlbum
            else
                return "Not Playing"
            end if
        end tell
        """
        let result = await MacControlService.shared.executeAppleScript(script)
        if result.success, let output = result.output, output != "Not Playing" {
            let parts = output.components(separatedBy: "|")
            if parts.count >= 3 {
                return [
                    "track": parts[0],
                    "artist": parts[1],
                    "album": parts[2]
                ]
            }
        }
        return nil
    }
}

// MARK: - System Notification
struct SystemNotification: Identifiable {
    let id = UUID()
    let name: String
    let source: String
    let type: NotificationType
    var userInfo: [String: Any]? = nil
    let timestamp = Date()
    
    init(name: String, source: String, type: NotificationType, userInfo: [String: Any]? = nil) {
        self.name = name
        self.source = source
        self.type = type
        self.userInfo = userInfo
    }
    
    var description: String {
        var desc = "[\(source)] \(name)"
        if let info = userInfo {
            desc += " - \(info)"
        }
        return desc
    }
}

// MARK: - Notification Type
enum NotificationType: String, CaseIterable {
    case mediaChange = "media"
    case screenLock = "screenLock"
    case screenUnlock = "screenUnlock"
    case appearanceChange = "appearance"
    case accessibilityChange = "accessibility"
    case displayChange = "display"
    case timeZoneChange = "timeZone"
    case localeChange = "locale"
    case powerSourceChange = "power"
    case bluetoothChange = "bluetooth"
    case custom = "custom"
}
