import Foundation
import AppKit
import Carbon.HIToolbox
import CoreGraphics

@MainActor
class GlobalHotkeyService: ObservableObject {
    static let shared = GlobalHotkeyService()
    
    // MARK: - Published State
    @Published var registeredHotkeys: [HotkeyBinding] = []
    @Published var isEnabled = false
    @Published var recentKeyEvents: [KeyEvent] = []
    
    // MARK: - Private
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hotkeyRefs: [EventHotKeyRef] = []
    private var hotkeyHandlers: [UInt32: () -> Void] = [:]
    private var nextHotkeyID: UInt32 = 1
    
    private init() {}
    
    // MARK: - Permission Check
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }
    
    func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - Register Global Hotkey (Carbon API)
    func registerHotkey(
        key: UInt32,
        modifiers: UInt32,
        name: String,
        handler: @escaping () -> Void
    ) -> Bool {
        let hotkeyID = EventHotKeyID(signature: OSType(0x4A525653), id: nextHotkeyID) // "JRVS"
        var hotkeyRef: EventHotKeyRef?
        
        let status = RegisterEventHotKey(
            key,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
        
        if status == noErr, let ref = hotkeyRef {
            hotkeyRefs.append(ref)
            hotkeyHandlers[nextHotkeyID] = handler
            
            let binding = HotkeyBinding(
                id: nextHotkeyID,
                name: name,
                keyCode: key,
                modifiers: modifiers
            )
            registeredHotkeys.append(binding)
            
            nextHotkeyID += 1
            print("[GlobalHotkeyService] Registered hotkey: \(name)")
            return true
        }
        
        print("[GlobalHotkeyService] Failed to register hotkey: \(name)")
        return false
    }
    
    // MARK: - Unregister Hotkey
    func unregisterHotkey(id: UInt32) {
        if let index = registeredHotkeys.firstIndex(where: { $0.id == id }) {
            if index < hotkeyRefs.count {
                UnregisterEventHotKey(hotkeyRefs[index])
                hotkeyRefs.remove(at: index)
            }
            registeredHotkeys.remove(at: index)
            hotkeyHandlers.removeValue(forKey: id)
            print("[GlobalHotkeyService] Unregistered hotkey ID: \(id)")
        }
    }
    
    func unregisterAllHotkeys() {
        for ref in hotkeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotkeyRefs.removeAll()
        hotkeyHandlers.removeAll()
        registeredHotkeys.removeAll()
        print("[GlobalHotkeyService] Unregistered all hotkeys")
    }
    
    // MARK: - Convenience Registration Methods
    func registerJarvisHotkey(handler: @escaping () -> Void) -> Bool {
        // Default: Cmd+Shift+J to activate Jarvis
        return registerHotkey(
            key: UInt32(kVK_ANSI_J),
            modifiers: UInt32(cmdKey | shiftKey),
            name: "Activate Jarvis",
            handler: handler
        )
    }
    
    func registerScreenshotHotkey(handler: @escaping () -> Void) -> Bool {
        // Cmd+Shift+5 alternative for Jarvis screenshot
        return registerHotkey(
            key: UInt32(kVK_ANSI_5),
            modifiers: UInt32(cmdKey | shiftKey | optionKey),
            name: "Jarvis Screenshot",
            handler: handler
        )
    }
    
    func registerQuickNoteHotkey(handler: @escaping () -> Void) -> Bool {
        // Cmd+Option+N for quick note
        return registerHotkey(
            key: UInt32(kVK_ANSI_N),
            modifiers: UInt32(cmdKey | optionKey),
            name: "Quick Note",
            handler: handler
        )
    }
    
    // MARK: - Event Tap (CGEvent)
    func startEventTap(eventMask: CGEventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)) {
        guard hasAccessibilityPermission else {
            requestAccessibilityPermission()
            return
        }
        
        guard eventTap == nil else {
            print("[GlobalHotkeyService] Event tap already running")
            return
        }
        
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let service = Unmanaged<GlobalHotkeyService>.fromOpaque(refcon).takeUnretainedValue()
            
            Task { @MainActor in
                service.handleCGEvent(type: type, event: event)
            }
            
            return Unmanaged.passRetained(event)
        }
        
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: refcon
        )
        
        guard let tap = eventTap else {
            print("[GlobalHotkeyService] Failed to create event tap")
            return
        }
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        isEnabled = true
        print("[GlobalHotkeyService] Event tap started")
    }
    
    func stopEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        
        eventTap = nil
        runLoopSource = nil
        isEnabled = false
        print("[GlobalHotkeyService] Event tap stopped")
    }
    
    // MARK: - Handle CGEvent
    private func handleCGEvent(type: CGEventType, event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        
        let keyEvent = KeyEvent(
            keyCode: Int(keyCode),
            type: type == .keyDown ? .keyDown : .keyUp,
            modifiers: KeyModifiers(from: flags),
            timestamp: Date()
        )
        
        recentKeyEvents.insert(keyEvent, at: 0)
        if recentKeyEvents.count > 50 {
            recentKeyEvents.removeLast()
        }
    }
    
    // MARK: - Monitor Key Events (Read-Only)
    func startKeyMonitoring() {
        guard hasAccessibilityPermission else {
            requestAccessibilityPermission()
            return
        }
        
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        startEventTap(eventMask: mask)
    }
    
    // MARK: - Get Key Name
    nonisolated func getKeyName(keyCode: Int) -> String {
        let keyNames: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
            kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_Return: "Return", kVK_Tab: "Tab", kVK_Space: "Space",
            kVK_Delete: "Delete", kVK_Escape: "Escape",
            kVK_Command: "Command", kVK_Shift: "Shift",
            kVK_Option: "Option", kVK_Control: "Control",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_LeftArrow: "←", kVK_RightArrow: "→"
        ]
        return keyNames[keyCode] ?? "Key\(keyCode)"
    }
    
    // MARK: - Recent Events
    func getRecentKeyEvents(count: Int = 20) -> [KeyEvent] {
        return Array(recentKeyEvents.prefix(count))
    }
    
    func clearKeyEvents() {
        recentKeyEvents.removeAll()
    }
}

// MARK: - Hotkey Binding
struct HotkeyBinding: Identifiable {
    let id: UInt32
    let name: String
    let keyCode: UInt32
    let modifiers: UInt32
    
    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        parts.append(GlobalHotkeyService.shared.getKeyName(keyCode: Int(keyCode)))
        return parts.joined()
    }
}

// MARK: - Key Event
struct KeyEvent: Identifiable {
    let id = UUID()
    let keyCode: Int
    let type: KeyEventType
    let modifiers: KeyModifiers
    let timestamp: Date
    
    var description: String {
        let keyName = GlobalHotkeyService.shared.getKeyName(keyCode: keyCode)
        return "\(modifiers.displayString)\(keyName) (\(type.rawValue))"
    }
}

enum KeyEventType: String {
    case keyDown = "Down"
    case keyUp = "Up"
}

// MARK: - Key Modifiers
struct KeyModifiers: OptionSet {
    let rawValue: UInt64
    
    static let command = KeyModifiers(rawValue: CGEventFlags.maskCommand.rawValue)
    static let shift = KeyModifiers(rawValue: CGEventFlags.maskShift.rawValue)
    static let option = KeyModifiers(rawValue: CGEventFlags.maskAlternate.rawValue)
    static let control = KeyModifiers(rawValue: CGEventFlags.maskControl.rawValue)
    static let function = KeyModifiers(rawValue: CGEventFlags.maskSecondaryFn.rawValue)
    
    init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
    
    init(from flags: CGEventFlags) {
        self.rawValue = flags.rawValue
    }
    
    var displayString: String {
        var parts: [String] = []
        if contains(.control) { parts.append("⌃") }
        if contains(.option) { parts.append("⌥") }
        if contains(.shift) { parts.append("⇧") }
        if contains(.command) { parts.append("⌘") }
        return parts.joined()
    }
}

// MARK: - Mouse Event Monitoring
extension GlobalHotkeyService {
    func startMouseMonitoring() {
        guard hasAccessibilityPermission else {
            requestAccessibilityPermission()
            return
        }
        
        let mask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue) |
                                (1 << CGEventType.leftMouseUp.rawValue) |
                                (1 << CGEventType.rightMouseDown.rawValue) |
                                (1 << CGEventType.rightMouseUp.rawValue) |
                                (1 << CGEventType.mouseMoved.rawValue)
        
        startEventTap(eventMask: mask)
    }
    
    func startFullInputMonitoring() {
        guard hasAccessibilityPermission else {
            requestAccessibilityPermission()
            return
        }
        
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                                (1 << CGEventType.keyUp.rawValue) |
                                (1 << CGEventType.leftMouseDown.rawValue) |
                                (1 << CGEventType.leftMouseUp.rawValue) |
                                (1 << CGEventType.rightMouseDown.rawValue) |
                                (1 << CGEventType.rightMouseUp.rawValue) |
                                (1 << CGEventType.scrollWheel.rawValue)
        
        startEventTap(eventMask: mask)
    }
}

// MARK: - Predefined Jarvis Hotkeys
extension GlobalHotkeyService {
    struct JarvisHotkeys {
        static let activateJarvis = (key: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey | shiftKey))
        static let toggleFocusMode = (key: UInt32(kVK_ANSI_F), modifiers: UInt32(cmdKey | shiftKey | optionKey))
        static let quickCapture = (key: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey | shiftKey | optionKey))
        static let voiceCommand = (key: UInt32(kVK_Space), modifiers: UInt32(cmdKey | optionKey))
        static let clipboardHistory = (key: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey))
    }
    
    func registerDefaultJarvisHotkeys(
        onActivate: @escaping () -> Void,
        onFocusMode: @escaping () -> Void,
        onQuickCapture: @escaping () -> Void,
        onVoiceCommand: @escaping () -> Void
    ) {
        _ = registerHotkey(
            key: JarvisHotkeys.activateJarvis.key,
            modifiers: JarvisHotkeys.activateJarvis.modifiers,
            name: "Activate Jarvis",
            handler: onActivate
        )
        
        _ = registerHotkey(
            key: JarvisHotkeys.toggleFocusMode.key,
            modifiers: JarvisHotkeys.toggleFocusMode.modifiers,
            name: "Toggle Focus Mode",
            handler: onFocusMode
        )
        
        _ = registerHotkey(
            key: JarvisHotkeys.quickCapture.key,
            modifiers: JarvisHotkeys.quickCapture.modifiers,
            name: "Quick Capture",
            handler: onQuickCapture
        )
        
        _ = registerHotkey(
            key: JarvisHotkeys.voiceCommand.key,
            modifiers: JarvisHotkeys.voiceCommand.modifiers,
            name: "Voice Command",
            handler: onVoiceCommand
        )
    }
}
