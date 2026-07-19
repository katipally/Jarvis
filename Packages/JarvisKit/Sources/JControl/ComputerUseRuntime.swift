import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// The Mac control surface: builds a semantic AX snapshot of a target app and
/// actuates elements (AX press/focus/set-value with verify, background clicks/
/// typing that never steal the cursor). Ported from OpenWork's handsfree layer.
/// All AXUIElement state is confined to this actor.
public actor ComputerUseRuntime {
    private let maxElements = 250
    private let maxDepth = 22

    private var records: [Int: AXUIElement] = [:]
    private var currentTarget: Target?
    private var enhancedPIDs: Set<pid_t> = []

    public init() {}

    public static var hasAccessibility: Bool { AXIsProcessTrusted() }

    @discardableResult
    public static func requestAccessibility() -> Bool {
        // Key literal avoids referencing the non-concurrency-safe global CFString.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    struct Target {
        let appName: String
        let pid: pid_t
        let windowNumber: Int
        let windowTitle: String?
        let axWindow: AXUIElement
    }

    private let importantRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
        "AXComboBox", "AXTextField", "AXTextArea", "AXSearchField", "AXLink",
        "AXSlider", "AXIncrementor", "AXTab", "AXMenuItem", "AXCell", "AXRow",
        "AXStaticText", "AXImage", "AXGroup",
    ]

    // MARK: - Snapshot

    public func snapshot(app: String?) throws -> UISnapshot {
        guard AXIsProcessTrusted() else { throw ControlError.accessibilityDenied }
        let target = try resolveTarget(app: app)
        currentTarget = target
        records = [:]

        var elements: [UIElement] = []
        collect(element: target.axWindow, depth: 0, into: &elements)
        return UISnapshot(appName: target.appName, windowTitle: target.windowTitle, elements: elements)
    }

    private func collect(element: AXUIElement, depth: Int, into elements: inout [UIElement]) {
        guard depth <= maxDepth, elements.count < maxElements else { return }

        let rawRole = axString(element, kAXRoleAttribute) ?? "AXUnknown"
        let value = axString(element, kAXValueAttribute).map { String($0.prefix(120)) }
        let label = semanticLabel(element, value: value)
        let actions = axActions(element)
        let caps = capabilities(element, rawRole: rawRole, actions: actions)
        let frame = axFrame(element)

        if shouldSurface(rawRole: rawRole, label: label, value: value, frame: frame, caps: caps), let frame {
            let id = elements.count + 1
            records[id] = element
            elements.append(UIElement(
                id: id, ref: "{e\(id)}",
                role: rawRole.hasPrefix("AX") ? String(rawRole.dropFirst(2)) : rawRole,
                label: label, value: value,
                frame: ElementFrame(x: Int(frame.origin.x), y: Int(frame.origin.y), width: Int(frame.width), height: Int(frame.height)),
                capabilities: caps
            ))
        }

        for child in axChildren(element) {
            collect(element: child, depth: depth + 1, into: &elements)
            if elements.count >= maxElements { break }
        }
    }

    // MARK: - Actuation

    public func click(ref: Int) async throws -> String {
        guard let element = records[ref], let target = currentTarget else { throw ControlError.elementNotFound("{e\(ref)}") }
        if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success { return "Pressed {e\(ref)}." }
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        if let frame = axFrame(element) {
            try await BackgroundInput.click(pid: target.pid, windowNumber: target.windowNumber, point: CGPoint(x: frame.midX, y: frame.midY))
            return "Clicked {e\(ref)} at its position."
        }
        throw ControlError.actionFailed("Could not press or click {e\(ref)}.")
    }

    public func click(x: Double, y: Double) async throws -> String {
        guard let target = currentTarget else { throw ControlError.actionFailed("Take a ui_snapshot first.") }
        try await BackgroundInput.click(pid: target.pid, windowNumber: target.windowNumber, point: CGPoint(x: x, y: y))
        return "Clicked at (\(Int(x)), \(Int(y)))."
    }

    public func setValue(ref: Int, value: String) async throws -> String {
        guard let element = records[ref], let target = currentTarget else { throw ControlError.elementNotFound("{e\(ref)}") }
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success, settable.boolValue,
           AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFString) == .success,
           axString(element, kAXValueAttribute) == value {
            return "Set {e\(ref)} to “\(value)”."
        }
        // Fallback: focus, select-all, retype.
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        try? await Task.sleep(nanoseconds: 40_000_000)
        try BackgroundInput.pressKey(pid: target.pid, combo: "command+a")
        try? await Task.sleep(nanoseconds: 20_000_000)
        try BackgroundInput.typeText(pid: target.pid, text: value)
        return "Typed “\(value)” into {e\(ref)}."
    }

    public func type(text: String) throws -> String {
        guard let target = currentTarget else { throw ControlError.actionFailed("Take a ui_snapshot first.") }
        try BackgroundInput.typeText(pid: target.pid, text: text)
        return "Typed \(text.count) characters."
    }

    public func pressKey(combo: String) throws -> String {
        guard let target = currentTarget else { throw ControlError.actionFailed("Take a ui_snapshot first.") }
        try BackgroundInput.pressKey(pid: target.pid, combo: combo)
        return "Pressed \(combo)."
    }

    public func scroll(ref: Int?, deltaX: Int, deltaY: Int) throws -> String {
        guard let target = currentTarget else { throw ControlError.actionFailed("Take a ui_snapshot first.") }
        let point: CGPoint
        if let ref, let element = records[ref], let frame = axFrame(element) {
            point = CGPoint(x: frame.midX, y: frame.midY)
        } else {
            point = .zero
        }
        try BackgroundInput.scroll(pid: target.pid, windowNumber: target.windowNumber, point: point, deltaX: Int32(deltaX), deltaY: Int32(deltaY))
        return "Scrolled."
    }

    // MARK: - Target resolution

    private func resolveTarget(app: String?) throws -> Target {
        let running = try resolveApp(app)
        let pid = running.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        if enableEnhanced(axApp: axApp, pid: pid) {
            Thread.sleep(forTimeInterval: 0.35) // Chromium/Electron build the tree lazily.
        }
        guard let window = firstWindow(axApp: axApp) else {
            throw ControlError.noWindow(running.localizedName ?? app ?? "app")
        }
        let title = axString(window, kAXTitleAttribute)
        let number = windowNumber(pid: pid, title: title) ?? 0
        return Target(appName: running.localizedName ?? "app", pid: pid, windowNumber: number, windowTitle: title, axWindow: window)
    }

    private func resolveApp(_ app: String?) throws -> NSRunningApplication {
        guard let name = app?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            guard let front = NSWorkspace.shared.frontmostApplication else { throw ControlError.noFrontmostApplication }
            return front
        }
        let needle = name.lowercased()
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        if let exact = apps.first(where: { $0.localizedName?.lowercased() == needle }) { return exact }
        if let contains = apps.first(where: { $0.localizedName?.lowercased().contains(needle) == true }) { return contains }
        throw ControlError.appNotFound(name)
    }

    private func firstWindow(axApp: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.first { window in
            guard let frame = axFrame(window) else { return false }
            return frame.width > 20 && frame.height > 20
        }
    }

    private func windowNumber(pid: pid_t, title: String?) -> Int? {
        guard let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let matches = infos.filter {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
        }
        if let title, let m = matches.first(where: { ($0[kCGWindowName as String] as? String) == title }) {
            return m[kCGWindowNumber as String] as? Int
        }
        return matches.first?[kCGWindowNumber as String] as? Int
    }

    @discardableResult
    private func enableEnhanced(axApp: AXUIElement, pid: pid_t) -> Bool {
        guard enhancedPIDs.insert(pid).inserted else { return false }
        AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return true
    }

    // MARK: - AX helpers

    private func shouldSurface(rawRole: String, label: String, value: String?, frame: CGRect?, caps: ElementCapabilities) -> Bool {
        guard let frame, frame.width > 1, frame.height > 1 else { return false }
        let interactive = caps.canPress || caps.canFocus || caps.canScroll || caps.canAdjust || caps.canSetValue
        if interactive { return true }
        if !importantRoles.contains(rawRole) { return false }
        let hasText = !label.isEmpty || value?.isEmpty == false
        if rawRole == "AXGroup" { return hasText && frame.width < 900 && frame.height < 700 }
        return hasText
    }

    private func semanticLabel(_ element: AXUIElement, value: String?) -> String {
        for candidate in [axString(element, kAXTitleAttribute), axString(element, kAXDescriptionAttribute),
                          axString(element, kAXHelpAttribute), axString(element, kAXIdentifierAttribute), value] {
            if let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                return String(trimmed.prefix(120))
            }
        }
        return ""
    }

    private func capabilities(_ element: AXUIElement, rawRole: String, actions: [String]) -> ElementCapabilities {
        var settable = DarwinBoolean(false)
        let canSetValue = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue
        var focusSettable = DarwinBoolean(false)
        let canFocus = AXUIElementIsAttributeSettable(element, kAXFocusedAttribute as CFString, &focusSettable) == .success && focusSettable.boolValue
        let canAdjust = actions.contains(kAXIncrementAction) || actions.contains(kAXDecrementAction) || rawRole == "AXSlider"
        let canScroll = actions.contains("AXScrollToVisible") || rawRole == "AXScrollArea"
        let canPress = actions.contains(kAXPressAction) ||
            ["AXButton", "AXCheckBox", "AXRadioButton", "AXLink", "AXMenuItem", "AXPopUpButton", "AXMenuButton", "AXCell"].contains(rawRole)
        return ElementCapabilities(canPress: canPress, canFocus: canFocus, canScroll: canScroll, canAdjust: canAdjust, canSetValue: canSetValue)
    }

    private func axChildren(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return [] }
        return children
    }

    private func axActions(_ element: AXUIElement) -> [String] {
        var actions: CFArray?
        guard AXUIElementCopyActionNames(element, &actions) == .success, let names = actions as? [String] else { return [] }
        return names
    }

    private func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { return nil }
        if let s = value as? String, !s.isEmpty { return s }
        if let a = value as? NSAttributedString, !a.string.isEmpty { return a.string }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private func axFrame(_ element: AXUIElement) -> CGRect? {
        guard let position = axValue(element, kAXPositionAttribute, .cgPoint) as? CGPoint,
              let size = axValue(element, kAXSizeAttribute, .cgSize) as? CGSize else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func axValue(_ element: AXUIElement, _ attribute: String, _ type: AXValueType) -> Any? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == type else { return nil }
        if type == .cgPoint {
            var point = CGPoint.zero
            return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
        } else if type == .cgSize {
            var size = CGSize.zero
            return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
        }
        return nil
    }
}
