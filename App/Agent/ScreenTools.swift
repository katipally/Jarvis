import Foundation
import JAgent
import JScreen

/// Recall tools over the passive screen buffer. Frames are never auto-fed to the
/// model — it pulls them here on demand. All read-only (prompt for Screen
/// Recording on first take_screenshot).
enum ScreenTools {
    static func registry(recall: ScreenRecall, buffer: ScreenBuffer) -> [ToolSpec] {
        [recallScreen(recall), fetchFrames(recall), takeScreenshot(buffer)]
    }

    private static func recallScreen(_ recall: ScreenRecall) -> ToolSpec {
        ToolSpec(
            name: "recall_screen",
            description: "List recently captured screen frames (what was on the user's screen) with their ids, so you can understand past context. Pass ids to fetch_frames to actually see them.",
            parameters: obj([("hours", "How many hours back (default 24)"), ("app", "Filter by app name (optional)")], required: []),
            tier: .readOnly
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
            parameters: obj([("ids", "Comma-separated frame ids")], required: ["ids"]),
            tier: .readOnly
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
            tier: .readOnly
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
