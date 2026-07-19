import AppKit
import Foundation
import JAgent

/// The M2 starter toolset. Read-only tools auto-run; external-effect tools pass
/// the approval gate. macOS calls hop to the main actor.
enum StarterTools {
    static func specs(artifacts: ArtifactStore, scratch: URL) -> [ToolSpec] {
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        return [
            listApps(), frontmostApp(), clipboardRead(), readFile(scratch), readArtifact(artifacts),
            openURL(), launchApp(), activateApp(), clipboardWrite(), writeFile(scratch),
        ]
    }

    // MARK: read-only

    private static func listApps() -> ToolSpec {
        ToolSpec(name: "list_apps", description: "List currently running applications with bundle identifiers.",
                 parameters: emptyObject(), tier: .readOnly) { _, _ in
            let lines = await MainActor.run {
                NSWorkspace.shared.runningApplications
                    .filter { $0.activationPolicy == .regular }
                    .compactMap { app -> String? in
                        guard let name = app.localizedName else { return nil }
                        return "\(name) [\(app.bundleIdentifier ?? "?")]"
                    }
            }
            return ToolOutput(lines.joined(separator: "\n"))
        }
    }

    private static func frontmostApp() -> ToolSpec {
        ToolSpec(name: "get_frontmost_app", description: "Get the frontmost (active) application.",
                 parameters: emptyObject(), tier: .readOnly) { _, _ in
            let text = await MainActor.run { () -> String in
                let app = NSWorkspace.shared.frontmostApplication
                return "\(app?.localizedName ?? "unknown") [\(app?.bundleIdentifier ?? "?")]"
            }
            return ToolOutput(text)
        }
    }

    private static func clipboardRead() -> ToolSpec {
        ToolSpec(name: "clipboard_read", description: "Read the current text on the clipboard.",
                 parameters: emptyObject(), tier: .readOnly) { _, _ in
            let text = await MainActor.run { NSPasteboard.general.string(forType: .string) ?? "" }
            return ToolOutput(text.isEmpty ? "(clipboard is empty or not text)" : text)
        }
    }

    private static func readArtifact(_ artifacts: ArtifactStore) -> ToolSpec {
        ToolSpec(name: "read_artifact", description: "Read the full content of a spilled artifact by reference (e.g. artifact:abc).",
                 parameters: object([("ref", "The artifact reference")], required: ["ref"]), tier: .readOnly) { input, _ in
            guard let ref = string(input, "ref") else { return ToolOutput("Missing 'ref'.", isError: true) }
            if let content = await artifacts.read(ref: ref) { return ToolOutput(content) }
            return ToolOutput("Artifact not found: \(ref)", isError: true)
        }
    }

    private static func readFile(_ scratch: URL) -> ToolSpec {
        ToolSpec(name: "read_file", description: "Read a UTF-8 text file inside Jarvis's scratch directory.",
                 parameters: object([("path", "Relative path within the scratch directory")], required: ["path"]), tier: .readOnly) { input, _ in
            guard let rel = string(input, "path") else { return ToolOutput("Missing 'path'.", isError: true) }
            guard let url = safePath(scratch, rel) else { return ToolOutput("Path escapes the scratch directory.", isError: true) }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return ToolOutput("Cannot read \(rel).", isError: true) }
            return ToolOutput(content)
        }
    }

    // MARK: external-effect

    private static func openURL() -> ToolSpec {
        ToolSpec(name: "open_url", description: "Open a URL in the default browser.",
                 parameters: object([("url", "The URL to open")], required: ["url"]),
                 tier: .externalEffect,
                 scopeKey: { input in string(input, "url").flatMap { URL(string: $0)?.host } },
                 summarize: { "Open \(string($0, "url") ?? "a URL")" }) { input, _ in
            guard let raw = string(input, "url"), let url = URL(string: raw) else { return ToolOutput("Invalid URL.", isError: true) }
            await MainActor.run { _ = NSWorkspace.shared.open(url) }
            return ToolOutput("Opened \(raw)")
        }
    }

    private static func launchApp() -> ToolSpec {
        ToolSpec(name: "launch_app", description: "Launch or open an application by name.",
                 parameters: object([("name", "Application name, e.g. Notes")], required: ["name"]),
                 tier: .externalEffect,
                 scopeKey: { string($0, "name") },
                 summarize: { "Launch \(string($0, "name") ?? "an app")" }) { input, _ in
            guard let name = string(input, "name") else { return ToolOutput("Missing 'name'.", isError: true) }
            let ok = await MainActor.run { () -> Bool in
                guard let url = appURL(named: name) else { return false }
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                return true
            }
            return ok ? ToolOutput("Launched \(name).") : ToolOutput("App not found: \(name).", isError: true)
        }
    }

    private static func activateApp() -> ToolSpec {
        ToolSpec(name: "activate_app", description: "Bring a running application to the front.",
                 parameters: object([("name", "Application name")], required: ["name"]),
                 tier: .externalEffect,
                 scopeKey: { string($0, "name") },
                 summarize: { "Bring \(string($0, "name") ?? "an app") to the front" }) { input, _ in
            guard let name = string(input, "name") else { return ToolOutput("Missing 'name'.", isError: true) }
            let ok = await MainActor.run { () -> Bool in
                guard let app = NSWorkspace.shared.runningApplications.first(where: {
                    $0.localizedName == name || $0.bundleIdentifier == name
                }) else { return false }
                return app.activate()
            }
            return ok ? ToolOutput("Activated \(name).") : ToolOutput("Not running: \(name).", isError: true)
        }
    }

    private static func clipboardWrite() -> ToolSpec {
        ToolSpec(name: "clipboard_write", description: "Write text to the clipboard.",
                 parameters: object([("text", "Text to copy")], required: ["text"]),
                 tier: .externalEffect,
                 summarize: { _ in "Copy text to the clipboard" }) { input, _ in
            guard let text = string(input, "text") else { return ToolOutput("Missing 'text'.", isError: true) }
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            return ToolOutput("Copied \(text.count) characters.")
        }
    }

    private static func writeFile(_ scratch: URL) -> ToolSpec {
        ToolSpec(name: "write_file", description: "Write a UTF-8 text file inside Jarvis's scratch directory.",
                 parameters: object([("path", "Relative path within scratch"), ("content", "File content")], required: ["path", "content"]),
                 tier: .externalEffect,
                 summarize: { "Write file \(string($0, "path") ?? "")" }) { input, _ in
            guard let rel = string(input, "path"), let content = string(input, "content") else {
                return ToolOutput("Missing 'path' or 'content'.", isError: true)
            }
            guard let url = safePath(scratch, rel) else { return ToolOutput("Path escapes the scratch directory.", isError: true) }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.write(to: url, atomically: true, encoding: .utf8)
                return ToolOutput("Wrote \(rel).")
            } catch {
                return ToolOutput("Write failed: \(error.localizedDescription)", isError: true)
            }
        }
    }
}

// MARK: - Helpers

private func emptyObject() -> JSONValue {
    .object(["type": .string("object"), "properties": .object([:])])
}

private func object(_ props: [(String, String)], required: [String]) -> JSONValue {
    var properties: [String: JSONValue] = [:]
    for (key, desc) in props {
        properties[key] = .object(["type": .string("string"), "description": .string(desc)])
    }
    return .object([
        "type": .string("object"),
        "properties": .object(properties),
        "required": .array(required.map(JSONValue.string)),
    ])
}

private func string(_ input: JSONValue, _ key: String) -> String? {
    if case .object(let obj) = input, case .string(let value)? = obj[key] { return value }
    return nil
}

private func safePath(_ base: URL, _ rel: String) -> URL? {
    let url = base.appendingPathComponent(rel).standardizedFileURL
    let basePath = base.standardizedFileURL.path
    return url.path.hasPrefix(basePath) ? url : nil
}

@MainActor
private func appURL(named name: String) -> URL? {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) { return url }
    let candidates = [
        "/Applications/\(name).app",
        "/System/Applications/\(name).app",
        "/System/Applications/Utilities/\(name).app",
    ]
    for path in candidates where FileManager.default.fileExists(atPath: path) {
        return URL(fileURLWithPath: path)
    }
    return nil
}
