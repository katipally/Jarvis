import Foundation
import CoreGraphics
import AppKit
import Carbon.HIToolbox

@MainActor
class InputSimulator: ObservableObject {
    static let shared = InputSimulator()
    
    private init() {}
    
    // MARK: - Permission Check
    var hasInputMonitoringPermission: Bool {
        CGPreflightListenEventAccess()
    }
    
    func requestInputMonitoringPermission() {
        CGRequestListenEventAccess()
    }
    
    // MARK: - Mouse Movement
    func moveMouse(to point: CGPoint) {
        let moveEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        moveEvent?.post(tap: .cghidEventTap)
    }
    
    // MARK: - Mouse Click at Current Position
    func click(button: CGMouseButton = .left) {
        let currentLocation = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let flippedY = screenHeight - currentLocation.y
        clickAt(x: currentLocation.x, y: flippedY)
    }
    
    // MARK: - Mouse Click at Specific Position
    func clickAt(x: CGFloat, y: CGFloat, button: CGMouseButton = .left) {
        let point = CGPoint(x: x, y: y)
        
        let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: button == .left ? .leftMouseDown : .rightMouseDown,
            mouseCursorPosition: point,
            mouseButton: button
        )
        
        let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: button == .left ? .leftMouseUp : .rightMouseUp,
            mouseCursorPosition: point,
            mouseButton: button
        )
        
        mouseDown?.post(tap: .cghidEventTap)
        usleep(50000)
        mouseUp?.post(tap: .cghidEventTap)
    }
    
    // MARK: - Double Click
    func doubleClick(at point: CGPoint, button: CGMouseButton = .left) {
        let mouseDown1 = CGEvent(
            mouseEventSource: nil,
            mouseType: button == .left ? .leftMouseDown : .rightMouseDown,
            mouseCursorPosition: point,
            mouseButton: button
        )
        mouseDown1?.setIntegerValueField(.mouseEventClickState, value: 1)
        
        let mouseUp1 = CGEvent(
            mouseEventSource: nil,
            mouseType: button == .left ? .leftMouseUp : .rightMouseUp,
            mouseCursorPosition: point,
            mouseButton: button
        )
        mouseUp1?.setIntegerValueField(.mouseEventClickState, value: 1)
        
        let mouseDown2 = CGEvent(
            mouseEventSource: nil,
            mouseType: button == .left ? .leftMouseDown : .rightMouseDown,
            mouseCursorPosition: point,
            mouseButton: button
        )
        mouseDown2?.setIntegerValueField(.mouseEventClickState, value: 2)
        
        let mouseUp2 = CGEvent(
            mouseEventSource: nil,
            mouseType: button == .left ? .leftMouseUp : .rightMouseUp,
            mouseCursorPosition: point,
            mouseButton: button
        )
        mouseUp2?.setIntegerValueField(.mouseEventClickState, value: 2)
        
        mouseDown1?.post(tap: .cghidEventTap)
        mouseUp1?.post(tap: .cghidEventTap)
        usleep(50000)
        mouseDown2?.post(tap: .cghidEventTap)
        mouseUp2?.post(tap: .cghidEventTap)
    }
    
    // MARK: - Right Click
    func rightClick(at point: CGPoint) {
        clickAt(x: point.x, y: point.y, button: .right)
    }
    
    // MARK: - Mouse Drag
    func drag(from start: CGPoint, to end: CGPoint, button: CGMouseButton = .left) async {
        let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: button == .left ? .leftMouseDown : .rightMouseDown,
            mouseCursorPosition: start,
            mouseButton: button
        )
        mouseDown?.post(tap: .cghidEventTap)
        
        let steps = 20
        let dx = (end.x - start.x) / CGFloat(steps)
        let dy = (end.y - start.y) / CGFloat(steps)
        
        for i in 1...steps {
            let currentPoint = CGPoint(
                x: start.x + dx * CGFloat(i),
                y: start.y + dy * CGFloat(i)
            )
            
            let dragEvent = CGEvent(
                mouseEventSource: nil,
                mouseType: button == .left ? .leftMouseDragged : .rightMouseDragged,
                mouseCursorPosition: currentPoint,
                mouseButton: button
            )
            dragEvent?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        
        let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: button == .left ? .leftMouseUp : .rightMouseUp,
            mouseCursorPosition: end,
            mouseButton: button
        )
        mouseUp?.post(tap: .cghidEventTap)
    }
    
    // MARK: - Scroll
    func scroll(deltaX: Int32 = 0, deltaY: Int32, at point: CGPoint? = nil) {
        if let point = point {
            moveMouse(to: point)
            usleep(10000)
        }
        
        let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        )
        scrollEvent?.post(tap: .cghidEventTap)
    }
    
    // MARK: - Type Single Character
    func typeCharacter(_ char: Character) {
        guard let keyCode = keyCodeForCharacter(char) else { return }
        
        let needsShift = char.isUppercase || shiftCharacters.contains(char)
        
        if needsShift {
            keyDown(keyCode: CGKeyCode(kVK_Shift))
        }
        
        keyDown(keyCode: keyCode)
        keyUp(keyCode: keyCode)
        
        if needsShift {
            keyUp(keyCode: CGKeyCode(kVK_Shift))
        }
    }
    
    // MARK: - Type Text String
    func typeText(_ text: String, delayBetweenKeys: UInt32 = 20000) async -> Bool {
        for char in text {
            typeCharacter(char)
            usleep(delayBetweenKeys)
        }
        return true
    }
    
    // MARK: - Type Text Fast (using clipboard)
    func typeTextFast(_ text: String) async -> Bool {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        pressKey(.v, modifiers: [.command])
        
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        if let previous = previousContents {
            pasteboard.clearContents()
            pasteboard.setString(previous, forType: .string)
        }
        
        return true
    }
    
    // MARK: - Key Press
    func keyDown(keyCode: CGKeyCode) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        event?.post(tap: .cghidEventTap)
    }
    
    func keyUp(keyCode: CGKeyCode) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        event?.post(tap: .cghidEventTap)
    }
    
    func pressKey(_ key: KeyCode, modifiers: [KeyModifier] = []) {
        for modifier in modifiers {
            keyDown(keyCode: modifier.keyCode)
        }
        
        keyDown(keyCode: key.rawValue)
        keyUp(keyCode: key.rawValue)
        
        for modifier in modifiers.reversed() {
            keyUp(keyCode: modifier.keyCode)
        }
    }
    
    // MARK: - Keyboard Shortcuts
    func pressShortcut(_ shortcut: KeyboardShortcut) {
        pressKey(shortcut.key, modifiers: shortcut.modifiers)
    }
    
    func copy() {
        pressKey(.c, modifiers: [.command])
    }
    
    func paste() {
        pressKey(.v, modifiers: [.command])
    }
    
    func cut() {
        pressKey(.x, modifiers: [.command])
    }
    
    func selectAll() {
        pressKey(.a, modifiers: [.command])
    }
    
    func undo() {
        pressKey(.z, modifiers: [.command])
    }
    
    func redo() {
        pressKey(.z, modifiers: [.command, .shift])
    }
    
    func save() {
        pressKey(.s, modifiers: [.command])
    }
    
    func newTab() {
        pressKey(.t, modifiers: [.command])
    }
    
    func closeTab() {
        pressKey(.w, modifiers: [.command])
    }
    
    func switchTab(next: Bool = true) {
        if next {
            pressKey(.rightBracket, modifiers: [.command, .shift])
        } else {
            pressKey(.leftBracket, modifiers: [.command, .shift])
        }
    }
    
    func pressEnter() {
        pressKey(.return)
    }
    
    func pressEscape() {
        pressKey(.escape)
    }
    
    func pressTab() {
        pressKey(.tab)
    }
    
    func pressSpace() {
        pressKey(.space)
    }
    
    func pressDelete() {
        pressKey(.delete)
    }
    
    func pressArrow(_ direction: ArrowDirection) {
        pressKey(direction.keyCode)
    }
    
    // MARK: - Special Actions
    func spotlight() {
        pressKey(.space, modifiers: [.command])
    }
    
    func missionControl() {
        pressKey(.upArrow, modifiers: [.control])
    }
    
    func showDesktop() {
        pressKey(.f11)
    }
    
    func screenshot() {
        pressKey(.three, modifiers: [.command, .shift])
    }
    
    func screenshotToClipboard() {
        pressKey(.three, modifiers: [.command, .shift, .control])
    }
    
    func screenshotSelection() {
        pressKey(.four, modifiers: [.command, .shift])
    }
    
    func forceQuit() {
        pressKey(.escape, modifiers: [.command, .option])
    }
    
    func lockScreen() {
        pressKey(.q, modifiers: [.command, .control])
    }
    
    // MARK: - Key Code Mapping
    private let shiftCharacters: Set<Character> = ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+", "{", "}", "|", ":", "\"", "<", ">", "?", "~"]
    
    private func keyCodeForCharacter(_ char: Character) -> CGKeyCode? {
        let lowercased = char.lowercased().first ?? char
        return characterToKeyCode[lowercased]
    }
    
    private let characterToKeyCode: [Character: CGKeyCode] = [
        "a": CGKeyCode(kVK_ANSI_A),
        "b": CGKeyCode(kVK_ANSI_B),
        "c": CGKeyCode(kVK_ANSI_C),
        "d": CGKeyCode(kVK_ANSI_D),
        "e": CGKeyCode(kVK_ANSI_E),
        "f": CGKeyCode(kVK_ANSI_F),
        "g": CGKeyCode(kVK_ANSI_G),
        "h": CGKeyCode(kVK_ANSI_H),
        "i": CGKeyCode(kVK_ANSI_I),
        "j": CGKeyCode(kVK_ANSI_J),
        "k": CGKeyCode(kVK_ANSI_K),
        "l": CGKeyCode(kVK_ANSI_L),
        "m": CGKeyCode(kVK_ANSI_M),
        "n": CGKeyCode(kVK_ANSI_N),
        "o": CGKeyCode(kVK_ANSI_O),
        "p": CGKeyCode(kVK_ANSI_P),
        "q": CGKeyCode(kVK_ANSI_Q),
        "r": CGKeyCode(kVK_ANSI_R),
        "s": CGKeyCode(kVK_ANSI_S),
        "t": CGKeyCode(kVK_ANSI_T),
        "u": CGKeyCode(kVK_ANSI_U),
        "v": CGKeyCode(kVK_ANSI_V),
        "w": CGKeyCode(kVK_ANSI_W),
        "x": CGKeyCode(kVK_ANSI_X),
        "y": CGKeyCode(kVK_ANSI_Y),
        "z": CGKeyCode(kVK_ANSI_Z),
        "0": CGKeyCode(kVK_ANSI_0),
        "1": CGKeyCode(kVK_ANSI_1),
        "2": CGKeyCode(kVK_ANSI_2),
        "3": CGKeyCode(kVK_ANSI_3),
        "4": CGKeyCode(kVK_ANSI_4),
        "5": CGKeyCode(kVK_ANSI_5),
        "6": CGKeyCode(kVK_ANSI_6),
        "7": CGKeyCode(kVK_ANSI_7),
        "8": CGKeyCode(kVK_ANSI_8),
        "9": CGKeyCode(kVK_ANSI_9),
        " ": CGKeyCode(kVK_Space),
        "\n": CGKeyCode(kVK_Return),
        "\t": CGKeyCode(kVK_Tab),
        "-": CGKeyCode(kVK_ANSI_Minus),
        "=": CGKeyCode(kVK_ANSI_Equal),
        "[": CGKeyCode(kVK_ANSI_LeftBracket),
        "]": CGKeyCode(kVK_ANSI_RightBracket),
        "\\": CGKeyCode(kVK_ANSI_Backslash),
        ";": CGKeyCode(kVK_ANSI_Semicolon),
        "'": CGKeyCode(kVK_ANSI_Quote),
        ",": CGKeyCode(kVK_ANSI_Comma),
        ".": CGKeyCode(kVK_ANSI_Period),
        "/": CGKeyCode(kVK_ANSI_Slash),
        "`": CGKeyCode(kVK_ANSI_Grave)
    ]
}

// MARK: - Key Code Enum
enum KeyCode: CGKeyCode {
    case a = 0x00
    case s = 0x01
    case d = 0x02
    case f = 0x03
    case h = 0x04
    case g = 0x05
    case z = 0x06
    case x = 0x07
    case c = 0x08
    case v = 0x09
    case b = 0x0B
    case q = 0x0C
    case w = 0x0D
    case e = 0x0E
    case r = 0x0F
    case y = 0x10
    case t = 0x11
    case one = 0x12
    case two = 0x13
    case three = 0x14
    case four = 0x15
    case six = 0x16
    case five = 0x17
    case equal = 0x18
    case nine = 0x19
    case seven = 0x1A
    case minus = 0x1B
    case eight = 0x1C
    case zero = 0x1D
    case rightBracket = 0x1E
    case o = 0x1F
    case u = 0x20
    case leftBracket = 0x21
    case i = 0x22
    case p = 0x23
    case l = 0x25
    case j = 0x26
    case quote = 0x27
    case k = 0x28
    case semicolon = 0x29
    case backslash = 0x2A
    case comma = 0x2B
    case slash = 0x2C
    case n = 0x2D
    case m = 0x2E
    case period = 0x2F
    case grave = 0x32
    case keypadDecimal = 0x41
    case keypadMultiply = 0x43
    case keypadPlus = 0x45
    case keypadClear = 0x47
    case keypadDivide = 0x4B
    case keypadEnter = 0x4C
    case keypadMinus = 0x4E
    case keypadEquals = 0x51
    case keypad0 = 0x52
    case keypad1 = 0x53
    case keypad2 = 0x54
    case keypad3 = 0x55
    case keypad4 = 0x56
    case keypad5 = 0x57
    case keypad6 = 0x58
    case keypad7 = 0x59
    case keypad8 = 0x5B
    case keypad9 = 0x5C
    case `return` = 0x24
    case tab = 0x30
    case space = 0x31
    case delete = 0x33
    case escape = 0x35
    case command = 0x37
    case shift = 0x38
    case capsLock = 0x39
    case option = 0x3A
    case control = 0x3B
    case rightCommand = 0x36
    case rightShift = 0x3C
    case rightOption = 0x3D
    case rightControl = 0x3E
    case function = 0x3F
    case f17 = 0x40
    case volumeUp = 0x48
    case volumeDown = 0x49
    case mute = 0x4A
    case f18 = 0x4F
    case f19 = 0x50
    case f20 = 0x5A
    case f5 = 0x60
    case f6 = 0x61
    case f7 = 0x62
    case f3 = 0x63
    case f8 = 0x64
    case f9 = 0x65
    case f11 = 0x67
    case f13 = 0x69
    case f16 = 0x6A
    case f14 = 0x6B
    case f10 = 0x6D
    case f12 = 0x6F
    case f15 = 0x71
    case help = 0x72
    case home = 0x73
    case pageUp = 0x74
    case forwardDelete = 0x75
    case f4 = 0x76
    case end = 0x77
    case f2 = 0x78
    case pageDown = 0x79
    case f1 = 0x7A
    case leftArrow = 0x7B
    case rightArrow = 0x7C
    case downArrow = 0x7D
    case upArrow = 0x7E
}

// MARK: - Key Modifier Enum
enum KeyModifier {
    case command
    case shift
    case option
    case control
    case function
    
    var keyCode: CGKeyCode {
        switch self {
        case .command: return CGKeyCode(kVK_Command)
        case .shift: return CGKeyCode(kVK_Shift)
        case .option: return CGKeyCode(kVK_Option)
        case .control: return CGKeyCode(kVK_Control)
        case .function: return CGKeyCode(kVK_Function)
        }
    }
}

// MARK: - Arrow Direction
enum ArrowDirection {
    case up, down, left, right
    
    var keyCode: KeyCode {
        switch self {
        case .up: return .upArrow
        case .down: return .downArrow
        case .left: return .leftArrow
        case .right: return .rightArrow
        }
    }
}

// MARK: - Keyboard Shortcut
struct KeyboardShortcut {
    let key: KeyCode
    let modifiers: [KeyModifier]
    
    static let copy = KeyboardShortcut(key: .c, modifiers: [.command])
    static let paste = KeyboardShortcut(key: .v, modifiers: [.command])
    static let cut = KeyboardShortcut(key: .x, modifiers: [.command])
    static let selectAll = KeyboardShortcut(key: .a, modifiers: [.command])
    static let undo = KeyboardShortcut(key: .z, modifiers: [.command])
    static let redo = KeyboardShortcut(key: .z, modifiers: [.command, .shift])
    static let save = KeyboardShortcut(key: .s, modifiers: [.command])
    static let find = KeyboardShortcut(key: .f, modifiers: [.command])
    static let newTab = KeyboardShortcut(key: .t, modifiers: [.command])
    static let closeTab = KeyboardShortcut(key: .w, modifiers: [.command])
    static let quit = KeyboardShortcut(key: .q, modifiers: [.command])
    static let spotlight = KeyboardShortcut(key: .space, modifiers: [.command])
}
