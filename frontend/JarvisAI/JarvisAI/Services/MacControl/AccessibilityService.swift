import Foundation
import AppKit
import ApplicationServices

@MainActor
class AccessibilityService: ObservableObject {
    static let shared = AccessibilityService()
    
    private init() {}
    
    // MARK: - Permission Check
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }
    
    func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - Get Application Element
    func getApplicationElement(bundleIdentifier: String) -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return nil
        }
        return AXUIElementCreateApplication(app.processIdentifier)
    }
    
    func getApplicationElement(name: String) -> AXUIElement? {
        let workspace = NSWorkspace.shared
        guard let app = workspace.runningApplications.first(where: { 
            $0.localizedName?.lowercased() == name.lowercased() 
        }) else {
            return nil
        }
        return AXUIElementCreateApplication(app.processIdentifier)
    }
    
    // MARK: - Get Focused Element
    func getFocusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let element = focusedElement else {
            return nil
        }
        return (element as! AXUIElement)
    }
    
    // MARK: - Get Element at Point
    func getElementAtPoint(_ point: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        
        guard result == .success else { return nil }
        return element
    }
    
    // MARK: - Get Attribute Value
    nonisolated func getAttribute<T>(_ element: AXUIElement, attribute: String) -> T? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? T
    }
    
    // MARK: - Set Attribute Value
    func setAttribute(_ element: AXUIElement, attribute: String, value: CFTypeRef) -> Bool {
        let result = AXUIElementSetAttributeValue(element, attribute as CFString, value)
        return result == .success
    }
    
    // MARK: - Perform Action
    func performAction(_ element: AXUIElement, action: String) -> Bool {
        let result = AXUIElementPerformAction(element, action as CFString)
        return result == .success
    }
    
    // MARK: - Get Children
    nonisolated func getChildren(_ element: AXUIElement) -> [AXUIElement] {
        guard let children: CFArray = getAttribute(element, attribute: kAXChildrenAttribute) else {
            return []
        }
        return children as? [AXUIElement] ?? []
    }
    
    // MARK: - Get Role
    nonisolated func getRole(_ element: AXUIElement) -> String? {
        return getAttribute(element, attribute: kAXRoleAttribute)
    }
    
    // MARK: - Get Title
    nonisolated func getTitle(_ element: AXUIElement) -> String? {
        return getAttribute(element, attribute: kAXTitleAttribute)
    }
    
    // MARK: - Get Description
    nonisolated func getDescription(_ element: AXUIElement) -> String? {
        return getAttribute(element, attribute: kAXDescriptionAttribute)
    }
    
    // MARK: - Get Value
    func getValue(_ element: AXUIElement) -> Any? {
        return getAttribute(element, attribute: kAXValueAttribute)
    }
    
    // MARK: - Set Value (for text fields)
    func setValue(_ element: AXUIElement, value: String) -> Bool {
        return setAttribute(element, attribute: kAXValueAttribute, value: value as CFTypeRef)
    }
    
    // MARK: - Get Position
    nonisolated func getPosition(_ element: AXUIElement) -> CGPoint? {
        var position: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position)
        guard result == .success, let positionValue = position else { return nil }
        
        var point = CGPoint.zero
        if AXValueGetValue(positionValue as! AXValue, .cgPoint, &point) {
            return point
        }
        return nil
    }
    
    // MARK: - Get Size
    nonisolated func getSize(_ element: AXUIElement) -> CGSize? {
        var size: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size)
        guard result == .success, let sizeValue = size else { return nil }
        
        var cgSize = CGSize.zero
        if AXValueGetValue(sizeValue as! AXValue, .cgSize, &cgSize) {
            return cgSize
        }
        return nil
    }
    
    // MARK: - Get Frame
    nonisolated func getFrame(_ element: AXUIElement) -> CGRect? {
        guard let position = getPosition(element),
              let size = getSize(element) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }
    
    // MARK: - Find Elements by Role
    func findElements(in element: AXUIElement, withRole role: String, maxDepth: Int = 10) -> [AXUIElement] {
        var results: [AXUIElement] = []
        findElementsRecursive(element: element, role: role, depth: 0, maxDepth: maxDepth, results: &results)
        return results
    }
    
    private func findElementsRecursive(element: AXUIElement, role: String, depth: Int, maxDepth: Int, results: inout [AXUIElement]) {
        guard depth < maxDepth else { return }
        
        if let elementRole = getRole(element), elementRole == role {
            results.append(element)
        }
        
        for child in getChildren(element) {
            findElementsRecursive(element: child, role: role, depth: depth + 1, maxDepth: maxDepth, results: &results)
        }
    }
    
    // MARK: - Find Element by Title or Description
    func findElement(in element: AXUIElement, matching text: String, maxDepth: Int = 10) -> AXUIElement? {
        return findElementRecursive(element: element, matching: text.lowercased(), depth: 0, maxDepth: maxDepth)
    }
    
    private func findElementRecursive(element: AXUIElement, matching text: String, depth: Int, maxDepth: Int) -> AXUIElement? {
        guard depth < maxDepth else { return nil }
        
        if let title = getTitle(element)?.lowercased(), title.contains(text) {
            return element
        }
        if let desc = getDescription(element)?.lowercased(), desc.contains(text) {
            return element
        }
        if let value = getValue(element) as? String, value.lowercased().contains(text) {
            return element
        }
        
        for child in getChildren(element) {
            if let found = findElementRecursive(element: child, matching: text, depth: depth + 1, maxDepth: maxDepth) {
                return found
            }
        }
        
        return nil
    }
    
    // MARK: - Click Element (High-Level)
    func clickElement(appName: String, elementDescription: String) async -> String {
        guard hasAccessibilityPermission else {
            requestAccessibilityPermission()
            return "Accessibility permission required. Please grant permission in System Settings."
        }
        
        guard let appElement = getApplicationElement(name: appName) else {
            return "Could not find application: \(appName)"
        }
        
        guard let targetElement = findElement(in: appElement, matching: elementDescription) else {
            return "Could not find element matching: \(elementDescription)"
        }
        
        if performAction(targetElement, action: kAXPressAction) {
            return "Clicked: \(elementDescription)"
        } else {
            if let frame = getFrame(targetElement) {
                let centerX = frame.origin.x + frame.size.width / 2
                let centerY = frame.origin.y + frame.size.height / 2
                InputSimulator.shared.clickAt(x: centerX, y: centerY)
                return "Clicked at position: (\(centerX), \(centerY))"
            }
            return "Failed to click element"
        }
    }
    
    // MARK: - Get All Windows
    func getAllWindows(for appElement: AXUIElement) -> [AXUIElement] {
        return findElements(in: appElement, withRole: kAXWindowRole)
    }
    
    // MARK: - Get All Buttons
    func getAllButtons(for element: AXUIElement) -> [AXUIElement] {
        return findElements(in: element, withRole: kAXButtonRole)
    }
    
    // MARK: - Get All Text Fields
    func getAllTextFields(for element: AXUIElement) -> [AXUIElement] {
        return findElements(in: element, withRole: kAXTextFieldRole)
    }
    
    // MARK: - Get All Menu Items
    func getAllMenuItems(for element: AXUIElement) -> [AXUIElement] {
        return findElements(in: element, withRole: kAXMenuItemRole)
    }
    
    // MARK: - Click Menu Item
    func clickMenuItem(appName: String, menuPath: [String]) async -> String {
        guard hasAccessibilityPermission else {
            requestAccessibilityPermission()
            return "Accessibility permission required"
        }
        
        guard let appElement = getApplicationElement(name: appName) else {
            return "Could not find application: \(appName)"
        }
        
        let menuBars: [AXUIElement] = findElements(in: appElement, withRole: kAXMenuBarRole, maxDepth: 2)
        guard let menuBar = menuBars.first else {
            return "Could not find menu bar"
        }
        
        var currentElement: AXUIElement? = menuBar
        
        for (index, menuName) in menuPath.enumerated() {
            guard let current = currentElement else {
                return "Failed at menu path step \(index)"
            }
            
            if let menuItem = findElement(in: current, matching: menuName, maxDepth: 3) {
                if index == menuPath.count - 1 {
                    if performAction(menuItem, action: kAXPressAction) {
                        return "Clicked menu item: \(menuPath.joined(separator: " > "))"
                    } else {
                        return "Failed to click menu item"
                    }
                } else {
                    _ = performAction(menuItem, action: kAXPressAction)
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    currentElement = menuItem
                }
            } else {
                return "Could not find menu: \(menuName)"
            }
        }
        
        return "Menu navigation completed"
    }
    
    // MARK: - Set Text Field Value
    func setTextFieldValue(appName: String, fieldDescription: String, value: String) async -> String {
        guard hasAccessibilityPermission else {
            requestAccessibilityPermission()
            return "Accessibility permission required"
        }
        
        guard let appElement = getApplicationElement(name: appName) else {
            return "Could not find application: \(appName)"
        }
        
        guard let textField = findElement(in: appElement, matching: fieldDescription) else {
            return "Could not find text field: \(fieldDescription)"
        }
        
        if setValue(textField, value: value) {
            return "Set value: \(value)"
        } else {
            return "Failed to set value"
        }
    }
    
    // MARK: - Get Element Tree (for debugging)
    func getElementTree(_ element: AXUIElement, maxDepth: Int = 3) -> [String: Any] {
        return buildElementTree(element: element, depth: 0, maxDepth: maxDepth)
    }
    
    private func buildElementTree(element: AXUIElement, depth: Int, maxDepth: Int) -> [String: Any] {
        var tree: [String: Any] = [:]
        
        tree["role"] = getRole(element) ?? "Unknown"
        tree["title"] = getTitle(element) ?? ""
        tree["description"] = getDescription(element) ?? ""
        
        if let frame = getFrame(element) {
            tree["frame"] = [
                "x": frame.origin.x,
                "y": frame.origin.y,
                "width": frame.size.width,
                "height": frame.size.height
            ]
        }
        
        if depth < maxDepth {
            let children = getChildren(element)
            if !children.isEmpty {
                tree["children"] = children.prefix(20).map { child in
                    buildElementTree(element: child, depth: depth + 1, maxDepth: maxDepth)
                }
            }
        }
        
        return tree
    }
    
    // MARK: - Observer Support
    func createObserver(for element: AXUIElement) -> AXObserver? {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        
        var observer: AXObserver?
        let callback: AXObserverCallback = { observer, element, notification, refcon in
            let notificationStr = notification as String
            print("[AccessibilityService] Notification: \(notificationStr)")
        }
        
        let result = AXObserverCreate(pid, callback, &observer)
        
        guard result == .success, let obs = observer else {
            return nil
        }
        
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        
        return obs
    }
    
    func addNotification(_ observer: AXObserver, element: AXUIElement, notification: String) {
        AXObserverAddNotification(observer, element, notification as CFString, nil)
    }
}

// MARK: - Element Info Structure
struct ElementInfo: Identifiable, Codable {
    let id: UUID
    let role: String
    let title: String?
    let description: String?
    let frame: CGRect?
    let isEnabled: Bool
    let hasChildren: Bool
    
    init(element: AXUIElement, service: AccessibilityService) {
        self.id = UUID()
        self.role = service.getRole(element) ?? "Unknown"
        self.title = service.getTitle(element)
        self.description = service.getDescription(element)
        self.frame = service.getFrame(element)
        self.isEnabled = service.getAttribute(element, attribute: kAXEnabledAttribute) ?? true
        self.hasChildren = !service.getChildren(element).isEmpty
    }
}
