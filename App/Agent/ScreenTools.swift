import Foundation
import JAgent
import JScreen

/// Recall tools over the passive screen buffer. Frames are never auto-fed to the
/// model — it pulls them here on demand. All read-only (prompt for Screen
/// Recording on first take_screenshot).
enum ScreenTools {
    static func registry(recall: ScreenRecall, buffer: ScreenBuffer) -> [ToolSpec] {
        [recallScreen(recall), searchScreen(recall), fetchFrames(recall), takeScreenshot(buffer)]
    }

    private static func searchScreen(_ recall: ScreenRecall) -> ToolSpec {
        ToolSpec(
            name: "search_screen",
            description: "Full-text search the OCR'd text from the user's past screen frames (screen rewind). Use to find when and where the user saw something — an error message, a name, a URL, a code snippet. Returns matching frames with a text snippet, app, window title, time, and frame id (pass ids to fetch_frames to actually see them).",
            parameters: obj([p("query", "Words to look for in past on-screen text"), pInt("limit", "Max results (default 20)")], required: ["query"]),
            tier: .readOnly, sensitive: true
        ) { input, _ in
            guard let query = str(input, "query") else { return ToolOutput("Missing 'query'.", isError: true) }
            let hits = await recall.search(query, limit: int(input, "limit") ?? 20)
            if hits.isEmpty { return ToolOutput("No screen text matched \"\(query)\".") }
            let lines = hits.map { hit in
                "\(hit.id) · \(hit.ts.formatted(date: .abbreviated, time: .shortened)) · \(hit.appName ?? "?")"
                    + (hit.windowTitle.map { " — \($0)" } ?? "")
                    + "\n    \(hit.snippet.replacingOccurrences(of: "\n", with: " "))"
            }
            return ToolOutput("Screen matches (id · time · app · window):\n" + lines.joined(separator: "\n"))
        }
    }

    private static func recallScreen(_ recall: ScreenRecall) -> ToolSpec {
        ToolSpec(
            name: "recall_screen",
            description: "List recently captured screen frames (what was on the user's screen) with their ids, so you can understand past context. Pass ids to fetch_frames to actually see them.",
            parameters: obj([pInt("hours", "How many hours back to look (default 24, max 72)"), p("app", "Filter by app name, e.g. Safari")], required: []),
            tier: .readOnly, sensitive: true
        ) { input, _ in
            let metas = await recall.recent(hours: int(input, "hours") ?? 24, app: str(input, "app"))
            if metas.isEmpty { return ToolOutput("No screen frames captured in that range.") }
            let lines = metas.map { meta in
                "\(meta.id) · \(meta.ts.formatted(date: .abbreviated, time: .shortened)) · \(meta.appName ?? "?")"
                    + (meta.windowTitle.map { " — \($0)" } ?? "")
            }
            return ToolOutput("Frames (id · time · app · window):\n" + lines.joined(separator: "\n"))
        }
    }

    private static func fetchFrames(_ recall: ScreenRecall) -> ToolSpec {
        ToolSpec(
            name: "fetch_frames",
            description: "Load up to 5 screen frames by id (from recall_screen) so you can see what was on screen.",
            parameters: obj([p("ids", "Comma- or space-separated frame ids from recall_screen")], required: ["ids"]),
            tier: .readOnly, sensitive: true
        ) { input, _ in
            guard let raw = str(input, "ids") else { return ToolOutput("Missing 'ids'.", isError: true) }
            let ids = raw.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
            let frames = await recall.frames(ids: ids, max: 5)
            if frames.isEmpty { return ToolOutput("No frames found for those ids.", isError: true) }
            let images = frames.map { ImageSource(mediaType: "image/jpeg", base64Data: $0.base64) }
            let caption = frames.map { "\($0.meta.appName ?? "?") at \($0.meta.ts.formatted(date: .abbreviated, time: .shortened))" }
                .joined(separator: "; ")
            return ToolOutput("Showing \(frames.count) frame(s): \(caption)", images: images)
        }
    }

    private static func takeScreenshot(_ buffer: ScreenBuffer) -> ToolSpec {
        ToolSpec(
            name: "take_screenshot",
            description: "Capture the current screen right now to see what the user is looking at.",
            parameters: obj([], required: []),
            tier: .readOnly, sensitive: true
        ) { _, _ in
            if !ScreenCapture.hasPermission {
                ScreenCapture.requestPermission()
                return ToolOutput("Screen Recording permission is required — I opened the prompt. Grant Jarvis access in System Settings › Privacy & Security › Screen Recording, then try again.", isError: true)
            }
            do {
                let frame = try await buffer.captureNow()
                let where_ = (frame.appName ?? "?") + (frame.windowTitle.map { " — \($0)" } ?? "")
                return ToolOutput("Current screen (\(where_)):", images: [ImageSource(mediaType: "image/jpeg", base64Data: frame.base64)])
            } catch {
                return ToolOutput((error as? ScreenError)?.errorDescription ?? error.localizedDescription, isError: true)
            }
        }
    }
}
