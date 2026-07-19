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
            description: "Read an app's accessibility UI as a list of elements with {e#} refs you can click or type into. Omit 'app' for the frontmost app. Always snapshot before clicking.",
            parameters: obj([("app", "Application name, e.g. Notes (optional)")], required: []),
            tier: .readOnly
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
            parameters: obj([("ref", "Element ref number, e.g. 5"), ("x", "X coordinate"), ("y", "Y coordinate"), ("app", "App name (optional)")], required: []),
            tier: .externalEffect,
            scopeKey: { str($0, "app") },
            summarize: { "Click \(str($0, "ref").map { "element \($0)" } ?? "a position") in \(str($0, "app") ?? "the app")" }
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
            parameters: obj([("text", "Text to type")], required: ["text"]),
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
            parameters: obj([("ref", "Element ref number"), ("value", "New value")], required: ["ref", "value"]),
            tier: .externalEffect,
            summarize: { "Set element \(str($0, "ref") ?? "") to “\((str($0, "value") ?? "").prefix(30))”" }
        ) { input, _ in
            guard let ref = int(input, "ref"), let value = str(input, "value") else { return ToolOutput("Missing 'ref' or 'value'.", isError: true) }
            do { return try await ToolOutput(runtime.setValue(ref: ref, value: value)) } catch { return ToolOutput(errorText(error), isError: true) }
        }
    }

    private static func pressKey(_ runtime: ComputerUseRuntime) -> ToolSpec {
        ToolSpec(
            name: "ui_key",
            description: "Send a key or key-combo to the last snapshotted app, e.g. 'return', 'command+a', 'escape'.",
            parameters: obj([("combo", "Key combo, e.g. command+s")], required: ["combo"]),
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
            parameters: obj([("ref", "Element ref to scroll over (optional)"), ("dx", "Horizontal lines"), ("dy", "Vertical lines")], required: []),
            tier: .externalEffect,
            summarize: { _ in "Scroll" }
        ) { input, _ in
            do { return try await ToolOutput(runtime.scroll(ref: int(input, "ref"), deltaX: int(input, "dx") ?? 0, deltaY: int(input, "dy") ?? -3)) }
            catch { return ToolOutput(errorText(error), isError: true) }
        }
    }
}

// MARK: - JSON helpers

func obj(_ props: [(String, String)], required: [String]) -> JSONValue {
    var properties: [String: JSONValue] = [:]
    for (key, desc) in props { properties[key] = .object(["type": .string("string"), "description": .string(desc)]) }
    return .object(["type": .string("object"), "properties": .object(properties), "required": .array(required.map(JSONValue.string))])
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
