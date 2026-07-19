import Foundation
import JAgent
import JControl

/// Wraps the AX/CGEvent control runtime as agent tools. ui_snapshot is read-only
/// (auto-runs, prompts for Accessibility on first use); actuation is external-effect.
enum ControlTools {
    static func registry(runtime: ComputerUseRuntime) -> [ToolSpec] {
        [snapshot(runtime), click(runtime), typeText(runtime), setValue(runtime), pressKey(runtime), scroll(runtime)]
    }

    private static func snapshot(_ runtime: ComputerUseRuntime) -> ToolSpec {
        ToolSpec(
            name: "ui_snapshot",
            description: "Read an app's accessibility UI as a list of elements with {e#} refs you can click or type into. Omit 'app' for the frontmost app. Always snapshot before clicking or typing — refs go stale when the UI changes.",
            parameters: obj([p("app", "Application name, e.g. Notes. Omit for the frontmost app.")], required: []),
            tier: .readOnly, sensitive: true
        ) { input, _ in
            if !ComputerUseRuntime.hasAccessibility {
                ComputerUseRuntime.requestAccessibility()
                return ToolOutput("Accessibility permission is required — I opened the system prompt. Grant Jarvis access in System Settings › Privacy & Security › Accessibility, then try again.", isError: true)
            }
            do {
                let snap = try await runtime.snapshot(app: str(input, "app"))
                return ToolOutput(snap.rendered)
            } catch {
                return ToolOutput(errorText(error), isError: true)
            }
        }
    }

    private static func click(_ runtime: ComputerUseRuntime) -> ToolSpec {
        ToolSpec(
            name: "ui_click",
            description: "Click a UI element by its {e#} ref number (from ui_snapshot), or at window coordinates x,y.",
            parameters: obj([pInt("ref", "Element ref number from ui_snapshot, e.g. 5"), pNum("x", "Window X coordinate (use with y when no ref fits)"), pNum("y", "Window Y coordinate"), p("app", "App name; omit for the last snapshotted app")], required: []),
            tier: .externalEffect,
            scopeKey: { str($0, "app") },
            summarize: { "Click \(int($0, "ref").map { "element \($0)" } ?? "a position") in \(str($0, "app") ?? "the app")" }
        ) { input, _ in
            do {
                if let ref = int(input, "ref") { return try await ToolOutput(runtime.click(ref: ref)) }
                if let x = dbl(input, "x"), let y = dbl(input, "y") { return try await ToolOutput(runtime.click(x: x, y: y)) }
                return ToolOutput("Provide 'ref' or both 'x' and 'y'.", isError: true)
            } catch { return ToolOutput(errorText(error), isError: true) }
        }
    }

    private static func typeText(_ runtime: ComputerUseRuntime) -> ToolSpec {
        ToolSpec(
            name: "ui_type",
            description: "Type text into the currently focused field of the last snapshotted app.",
            parameters: obj([p("text", "Text to type into the focused field")], required: ["text"]),
            tier: .externalEffect,
            summarize: { "Type “\((str($0, "text") ?? "").prefix(40))” " }
        ) { input, _ in
            guard let text = str(input, "text") else { return ToolOutput("Missing 'text'.", isError: true) }
            do { return try await ToolOutput(runtime.type(text: text)) } catch { return ToolOutput(errorText(error), isError: true) }
        }
    }

    private static func setValue(_ runtime: ComputerUseRuntime) -> ToolSpec {
        ToolSpec(
            name: "ui_set_value",
            description: "Set the value of a text element by {e#} ref (verifies, falls back to select-all + retype).",
            parameters: obj([pInt("ref", "Element ref number from ui_snapshot"), p("value", "The full replacement value for the field")], required: ["ref", "value"]),
            tier: .externalEffect,
            summarize: { "Set element \(int($0, "ref").map(String.init) ?? "?") to “\((str($0, "value") ?? "").prefix(30))”" }
        ) { input, _ in
            guard let ref = int(input, "ref"), let value = str(input, "value") else { return ToolOutput("Missing 'ref' or 'value'.", isError: true) }
            do { return try await ToolOutput(runtime.setValue(ref: ref, value: value)) } catch { return ToolOutput(errorText(error), isError: true) }
        }
    }

    private static func pressKey(_ runtime: ComputerUseRuntime) -> ToolSpec {
        ToolSpec(
            name: "ui_key",
            description: "Send a key or key-combo to the last snapshotted app, e.g. 'return', 'command+a', 'escape'.",
            parameters: obj([p("combo", "Key or combo: 'return', 'escape', 'tab', or modifiers like 'command+s', 'command+shift+t'")], required: ["combo"]),
            tier: .externalEffect,
            summarize: { "Press \(str($0, "combo") ?? "a key")" }
        ) { input, _ in
            guard let combo = str(input, "combo") else { return ToolOutput("Missing 'combo'.", isError: true) }
            do { return try await ToolOutput(runtime.pressKey(combo: combo)) } catch { return ToolOutput(errorText(error), isError: true) }
        }
    }

    private static func scroll(_ runtime: ComputerUseRuntime) -> ToolSpec {
        ToolSpec(
            name: "ui_scroll",
            description: "Scroll within the last snapshotted app. Positive dy scrolls up, negative down.",
            parameters: obj([pInt("ref", "Element ref to scroll over; omit for the window center"), pInt("dx", "Horizontal scroll lines (positive = right)"), pInt("dy", "Vertical scroll lines (positive = up, negative = down; default -3)")], required: []),
            tier: .externalEffect,
            summarize: { _ in "Scroll" }
        ) { input, _ in
            do { return try await ToolOutput(runtime.scroll(ref: int(input, "ref"), deltaX: int(input, "dx") ?? 0, deltaY: int(input, "dy") ?? -3)) }
            catch { return ToolOutput(errorText(error), isError: true) }
        }
    }
}

// MARK: - JSON helpers

/// One JSON-Schema property. Use the factory helpers so tool schemas tell the
/// model the truth about types (numbers as numbers, not strings).
struct Prop {
    let name: String
    let type: String
    let desc: String
    var enumValues: [String]? = nil
}

func p(_ name: String, _ desc: String) -> Prop { Prop(name: name, type: "string", desc: desc) }
func pInt(_ name: String, _ desc: String) -> Prop { Prop(name: name, type: "integer", desc: desc) }
func pNum(_ name: String, _ desc: String) -> Prop { Prop(name: name, type: "number", desc: desc) }
func pEnum(_ name: String, _ desc: String, _ values: [String]) -> Prop {
    Prop(name: name, type: "string", desc: desc, enumValues: values)
}

func obj(_ props: [Prop], required: [String]) -> JSONValue {
    var properties: [String: JSONValue] = [:]
    for prop in props {
        var fields: [String: JSONValue] = [
            "type": .string(prop.type),
            "description": .string(prop.desc),
        ]
        if let values = prop.enumValues {
            fields["enum"] = .array(values.map(JSONValue.string))
        }
        properties[prop.name] = .object(fields)
    }
    return .object([
        "type": .string("object"),
        "properties": .object(properties),
        "required": .array(required.map(JSONValue.string)),
        "additionalProperties": .bool(false),
    ])
}

func str(_ input: JSONValue, _ key: String) -> String? {
    if case .object(let o) = input, case .string(let s)? = o[key] { return s.isEmpty ? nil : s }
    return nil
}

func int(_ input: JSONValue, _ key: String) -> Int? {
    if case .object(let o) = input {
        switch o[key] {
        case .number(let n): return Int(n)
        case .string(let s): return Int(s)
        default: return nil
        }
    }
    return nil
}

func dbl(_ input: JSONValue, _ key: String) -> Double? {
    if case .object(let o) = input {
        switch o[key] {
        case .number(let n): return n
        case .string(let s): return Double(s)
        default: return nil
        }
    }
    return nil
}

func errorText(_ error: Error) -> String {
    (error as? ControlError)?.errorDescription ?? error.localizedDescription
}
