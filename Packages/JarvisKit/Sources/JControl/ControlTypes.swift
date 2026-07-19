import CoreGraphics
import Foundation

public enum ControlError: Error, LocalizedError {
    case accessibilityDenied
    case appNotFound(String)
    case noFrontmostApplication
    case noWindow(String)
    case elementNotFound(String)
    case eventSourceFailed
    case eventCreationFailed
    case unknownKey(String)
    case actionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .accessibilityDenied: "Accessibility permission is required. Grant it in System Settings › Privacy & Security › Accessibility."
        case .appNotFound(let a): "App not found: \(a)"
        case .noFrontmostApplication: "There is no frontmost application."
        case .noWindow(let a): "No usable window for \(a)."
        case .elementNotFound(let r): "Element not found: \(r)"
        case .eventSourceFailed: "Could not create a CoreGraphics event source."
        case .eventCreationFailed: "Could not create a CoreGraphics event."
        case .unknownKey(let k): "Unknown key: \(k)"
        case .actionFailed(let m): m
        }
    }
}

public struct ElementFrame: Sendable, Codable, Equatable {
    public var x: Int, y: Int, width: Int, height: Int
    public init(x: Int, y: Int, width: Int, height: Int) { self.x = x; self.y = y; self.width = width; self.height = height }
    public var center: CGPoint { CGPoint(x: Double(x) + Double(width) / 2, y: Double(y) + Double(height) / 2) }
}

public struct ElementCapabilities: Sendable, Codable, Equatable {
    public var canPress: Bool
    public var canFocus: Bool
    public var canScroll: Bool
    public var canAdjust: Bool
    public var canSetValue: Bool
}

/// A single semantic UI element the model can reference by `ref` (e.g. "{e5}").
public struct UIElement: Sendable, Codable, Equatable, Identifiable {
    public var id: Int
    public var ref: String
    public var role: String
    public var label: String
    public var value: String?
    public var frame: ElementFrame
    public var capabilities: ElementCapabilities

    /// Compact one-line description for the model.
    public var line: String {
        var parts = ["\(ref) \(role)"]
        if !label.isEmpty && label != role { parts.append("“\(label)”") }
        if let value, !value.isEmpty, value != label { parts.append("= \(value.prefix(60))") }
        var caps: [String] = []
        if capabilities.canPress { caps.append("press") }
        if capabilities.canSetValue { caps.append("editable") }
        if capabilities.canFocus { caps.append("focus") }
        if !caps.isEmpty { parts.append("[\(caps.joined(separator: ","))]") }
        return parts.joined(separator: " ")
    }
}

public struct UISnapshot: Sendable, Codable, Equatable {
    public var appName: String
    public var windowTitle: String?
    public var elements: [UIElement]

    public var rendered: String {
        var out = "App: \(appName)"
        if let windowTitle { out += " — \(windowTitle)" }
        out += "\n" + elements.map(\.line).joined(separator: "\n")
        return out
    }
}
