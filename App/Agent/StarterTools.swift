import AppKit
import Foundation
import JAgent

/// The core starter toolset. Read-only tools auto-run; external-effect tools pass
/// the approval gate. macOS calls hop to the main actor.
enum StarterTools {
    static func specs(artifacts: ArtifactStore, scratch: URL) -> [ToolSpec] {
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        return [
            listApps(), frontmostApp(), clipboardRead(), readFile(scratch), listFiles(scratch),
            readArtifact(artifacts), fetchURL(),
            openURL(), launchApp(), activateApp(), clipboardWrite(), writeFile(scratch),
        ]
    }

    /// Cap on file/artifact/web content returned per call — big payloads paginate
    /// via 'offset' instead of blowing up the context window.
    private static let readSlice = 12_000

    // MARK: read-only

    private static func listApps() -> ToolSpec {
        ToolSpec(name: "list_apps",
                 description: "List the currently running applications with their bundle identifiers. Use before activate_app to find the exact name.",
                 parameters: obj([], required: []), tier: .readOnly) { _, _ in
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
        ToolSpec(name: "get_frontmost_app",
                 description: "Get the app the user is looking at right now (name and bundle identifier).",
                 parameters: obj([], required: []), tier: .readOnly) { _, _ in
            let text = await MainActor.run { () -> String in
                let app = NSWorkspace.shared.frontmostApplication
                return "\(app?.localizedName ?? "unknown") [\(app?.bundleIdentifier ?? "?")]"
            }
            return ToolOutput(text)
        }
    }

    private static func clipboardRead() -> ToolSpec {
        ToolSpec(name: "clipboard_read",
                 description: "Read the current text on the clipboard. Use only when the user refers to something they copied.",
                 parameters: obj([], required: []), tier: .readOnly, sensitive: true) { _, _ in
            let text = await MainActor.run { NSPasteboard.general.string(forType: .string) ?? "" }
            return ToolOutput(text.isEmpty ? "(clipboard is empty or not text)" : text)
        }
    }

    private static func readArtifact(_ artifacts: ArtifactStore) -> ToolSpec {
        ToolSpec(name: "read_artifact",
                 description: "Read a spilled artifact by reference (e.g. artifact:abc from a truncated tool result). Long artifacts return \(readSlice) characters per call — pass 'offset' to continue.",
                 parameters: obj([p("ref", "The artifact reference, e.g. artifact:abc"),
                                  pInt("offset", "Character offset to start from (default 0)")],
                                 required: ["ref"]), tier: .readOnly) { input, _ in
            guard let ref = str(input, "ref") else { return ToolOutput("Missing 'ref'.", isError: true) }
            guard let content = await artifacts.read(ref: ref) else {
                return ToolOutput("Artifact not found: \(ref)", isError: true)
            }
            return ToolOutput(slice(content, offset: int(input, "offset") ?? 0))
        }
    }

    private static func readFile(_ scratch: URL) -> ToolSpec {
        ToolSpec(name: "read_file",
                 description: "Read a UTF-8 text file from Jarvis's scratch directory (files written earlier with write_file — use list_files to discover them). Long files return \(readSlice) characters per call — pass 'offset' to continue.",
                 parameters: obj([p("path", "Relative path within the scratch directory"),
                                  pInt("offset", "Character offset to start from (default 0)")],
                                 required: ["path"]), tier: .readOnly) { input, _ in
            guard let rel = str(input, "path") else { return ToolOutput("Missing 'path'.", isError: true) }
            guard let url = safePath(scratch, rel) else { return ToolOutput("Path escapes the scratch directory.", isError: true) }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return ToolOutput("Cannot read \(rel).", isError: true) }
            return ToolOutput(slice(content, offset: int(input, "offset") ?? 0))
        }
    }

    private static func listFiles(_ scratch: URL) -> ToolSpec {
        ToolSpec(name: "list_files",
                 description: "List the files in Jarvis's scratch directory (its private workspace for notes and intermediate results).",
                 parameters: obj([], required: []), tier: .readOnly) { _, _ in
            let fm = FileManager.default
            guard let entries = try? fm.subpathsOfDirectory(atPath: scratch.path), !entries.isEmpty else {
                return ToolOutput("The scratch directory is empty.")
            }
            let lines = entries.sorted().compactMap { rel -> String? in
                let full = scratch.appendingPathComponent(rel)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: full.path, isDirectory: &isDir), !isDir.boolValue else { return nil }
                let size = (try? fm.attributesOfItem(atPath: full.path)[.size] as? Int) ?? nil
                return "\(rel) (\(size.map { "\($0) bytes" } ?? "?"))"
            }
            return ToolOutput(lines.isEmpty ? "The scratch directory is empty." : lines.joined(separator: "\n"))
        }
    }

    private static func fetchURL() -> ToolSpec {
        ToolSpec(name: "fetch_url",
                 description: "Fetch a web page or API endpoint over HTTPS and return its text (HTML is stripped to readable text). Use for current information you don't know — news, docs, prices, weather pages. Long pages return \(readSlice) characters per call — pass 'offset' to continue.",
                 parameters: obj([p("url", "Absolute http(s) URL to fetch"),
                                  pInt("offset", "Character offset into the extracted text (default 0)")],
                                 required: ["url"]), tier: .readOnly) { input, _ in
            guard let raw = str(input, "url"), let url = URL(string: raw),
                  let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
                return ToolOutput("Provide an absolute http(s) URL.", isError: true)
            }
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.setValue("Jarvis/0.1 (macOS assistant)", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    return ToolOutput("HTTP \(http.statusCode) from \(url.host ?? raw).", isError: true)
                }
                let body = String(data: data.prefix(2_000_000), encoding: .utf8) ?? ""
                let isHTML = (response.mimeType ?? "").contains("html") || body.lowercased().contains("<html")
                let text = isHTML ? stripHTML(body) : body
                let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { return ToolOutput("The page had no extractable text.", isError: true) }
                return ToolOutput(slice(cleaned, offset: int(input, "offset") ?? 0))
            } catch {
                return ToolOutput("Fetch failed: \(error.localizedDescription)", isError: true)
            }
        }
    }

    // MARK: external-effect

    private static func openURL() -> ToolSpec {
        ToolSpec(name: "open_url", description: "Open a URL in the user's default browser (visible to the user — use fetch_url to read a page yourself).",
                 parameters: obj([p("url", "The URL to open")], required: ["url"]),
                 tier: .externalEffect,
                 scopeKey: { input in str(input, "url").flatMap { URL(string: $0)?.host } },
                 summarize: { "Open \(str($0, "url") ?? "a URL")" }) { input, _ in
            guard let raw = str(input, "url"), let url = URL(string: raw) else { return ToolOutput("Invalid URL.", isError: true) }
            await MainActor.run { _ = NSWorkspace.shared.open(url) }
            return ToolOutput("Opened \(raw)")
        }
    }

    private static func launchApp() -> ToolSpec {
        ToolSpec(name: "launch_app", description: "Launch an application that isn't running yet, by name.",
                 parameters: obj([p("name", "Application name, e.g. Notes")], required: ["name"]),
                 tier: .externalEffect,
                 scopeKey: { str($0, "name") },
                 summarize: { "Launch \(str($0, "name") ?? "an app")" }) { input, _ in
            guard let name = str(input, "name") else { return ToolOutput("Missing 'name'.", isError: true) }
            let ok = await MainActor.run { () -> Bool in
                guard let url = appURL(named: name) else { return false }
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                return true
            }
            return ok ? ToolOutput("Launched \(name).") : ToolOutput("App not found: \(name).", isError: true)
        }
    }

    private static func activateApp() -> ToolSpec {
        ToolSpec(name: "activate_app", description: "Bring a running application's window to the front (use list_apps for exact names).",
                 parameters: obj([p("name", "Application name or bundle identifier")], required: ["name"]),
                 tier: .externalEffect,
                 scopeKey: { str($0, "name") },
                 summarize: { "Bring \(str($0, "name") ?? "an app") to the front" }) { input, _ in
            guard let name = str(input, "name") else { return ToolOutput("Missing 'name'.", isError: true) }
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
        ToolSpec(name: "clipboard_write", description: "Replace the clipboard contents with text (the user can then paste it anywhere).",
                 parameters: obj([p("text", "Text to copy to the clipboard")], required: ["text"]),
                 tier: .externalEffect,
                 summarize: { input in
                     let text = str(input, "text") ?? ""
                     return "Copy to clipboard: “\(text.count > 80 ? text.prefix(80) + "…" : text[...])”"
                 }) { input, _ in
            guard let text = str(input, "text") else { return ToolOutput("Missing 'text'.", isError: true) }
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            return ToolOutput("Copied \(text.count) characters.")
        }
    }

    private static func writeFile(_ scratch: URL) -> ToolSpec {
        ToolSpec(name: "write_file", description: "Write a UTF-8 text file into Jarvis's scratch directory (overwrites; for notes and intermediate results, not the user's documents).",
                 parameters: obj([p("path", "Relative path within scratch, e.g. notes/plan.md"),
                                  p("content", "Full file content")],
                                 required: ["path", "content"]),
                 tier: .externalEffect,
                 summarize: { "Write scratch file \(str($0, "path") ?? "") (\((str($0, "content") ?? "").count) chars)" }) { input, _ in
            guard let rel = str(input, "path"), let content = string(input, "content") else {
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

    // MARK: - Helpers

    /// Return one pageable slice of a long string with a continuation hint.
    private static func slice(_ content: String, offset: Int) -> String {
        guard offset < content.count else { return "(offset \(offset) is past the end — total length \(content.count))" }
        let start = content.index(content.startIndex, offsetBy: max(0, offset))
        let end = content.index(start, offsetBy: readSlice, limitedBy: content.endIndex) ?? content.endIndex
        var out = String(content[start..<end])
        if end < content.endIndex {
            out += "\n\n…[\(content.distance(from: end, to: content.endIndex)) more characters — call again with offset \(content.distance(from: content.startIndex, to: end))]"
        }
        return out
    }

    /// Crude but dependency-free readable-text extraction.
    private static func stripHTML(_ html: String) -> String {
        var text = html
        for block in ["script", "style", "noscript", "svg", "head"] {
            text = text.replacingOccurrences(
                of: "<\(block)[^>]*>[\\s\\S]*?</\(block)>",
                with: " ", options: [.regularExpression, .caseInsensitive]
            )
        }
        text = text.replacingOccurrences(of: "<br[^>]*>|</p>|</div>|</li>|</h[1-6]>|</tr>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, char) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")] {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        // Collapse whitespace runs left behind by tag removal.
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text
    }
}

/// Full-length string accessor (the shared `str` treats "" as nil, which is
/// wrong for file content).
private func string(_ input: JSONValue, _ key: String) -> String? {
    if case .object(let obj) = input, case .string(let value)? = obj[key] { return value }
    return nil
}

/// Resolves `rel` inside `base`, rejecting traversal and symlink escapes.
private func safePath(_ base: URL, _ rel: String) -> URL? {
    let url = base.appendingPathComponent(rel).standardizedFileURL.resolvingSymlinksInPath()
    let basePath = base.standardizedFileURL.resolvingSymlinksInPath().path
    // Trailing separator so ".../scratch-evil" can't pass as ".../scratch".
    return url.path == basePath || url.path.hasPrefix(basePath + "/") ? url : nil
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
