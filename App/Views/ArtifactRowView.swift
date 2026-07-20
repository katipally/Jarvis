import AppKit
import GRDB
import JStore
import Quartz
import SwiftUI

/// One artifact row — used by the Activity timeline and the run detail view.
/// Filename + metadata, an optional preview line, and Quick Look /
/// reveal-in-Finder actions.
struct ArtifactRowView: View {
    let artifact: ArtifactRow

    private var url: URL { URL(fileURLWithPath: artifact.path) }
    private var exists: Bool { FileManager.default.fileExists(atPath: artifact.path) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(artifact.filename ?? url.lastPathComponent)
                        .font(.jarvisRow)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(artifact.kind)
                            .font(.jarvisFootnote).foregroundStyle(.white.opacity(0.5))
                        if let bytes = artifact.bytes {
                            Text(byteText(bytes))
                                .font(.jarvisFootnote).monospacedDigit()
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        Text(artifact.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.jarvisFootnote).foregroundStyle(.white.opacity(0.45))
                    }
                }
                Spacer(minLength: 0)
                actionButton("eye", "Quick Look") { QuickLookPresenter.shared.show(url) }
                actionButton("folder", "Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            if let preview = artifact.preview, !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.jarvisSurface))
        .opacity(exists ? 1 : 0.5)
    }

    private func actionButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.jarvisSurfaceHover))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .disabled(!exists)
        .help(help)
        .accessibilityLabel(help)
    }

    private var icon: String {
        switch artifact.kind {
        case "spill": "doc.text"
        case "shelf": "tray.full"
        case "generated": "sparkles"
        default: "doc"
        }
    }

    private func byteText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// Presents a file in a real Quick Look preview (QLPreviewView) inside a small
/// standalone window. Chosen over the shared QLPreviewPanel because it needs no
/// responder-chain plumbing — it works reliably from the notch's LSUIElement app.
@MainActor
final class QuickLookPresenter {
    static let shared = QuickLookPresenter()
    private var window: NSWindow?

    func show(_ url: URL) {
        let window = self.window ?? makeWindow()
        self.window = window
        let preview = QLPreviewView(frame: NSRect(x: 0, y: 0, width: 720, height: 540), style: .normal)
        preview?.autoresizingMask = [.width, .height]
        preview?.shouldCloseWithWindow = true
        preview?.previewItem = url as NSURL
        window.title = url.lastPathComponent
        window.contentView = preview
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        w.isReleasedWhenClosed = false
        return w
    }
}
