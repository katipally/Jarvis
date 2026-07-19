import AppKit
import JScreen
import SwiftUI

/// Screen Rewind pane: full-text search past OCR'd frames, or browse a recent
/// timeline grouped by hour. Tap any result for a larger preview. Matches the
/// ActivityView pane style (surface cards, jarvis fonts).
struct RewindPane: View {
    let recall: ScreenRecall

    @State private var query = ""
    @State private var hits: [ScreenRecall.SearchHit] = []
    @State private var recent: [ScreenRecall.FrameMeta] = []
    @State private var preview: Preview?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 10) {
            searchField
            content
        }
        .overlay { previewOverlay }
        .animation(.easeInOut(duration: 0.15), value: preview?.id)
        .task { recent = await recall.recent(hours: 24, app: nil, limit: 80) }
        .onChange(of: query) { _, new in scheduleSearch(new) }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.jarvisCaption).foregroundStyle(.white.opacity(0.45))
            TextField("Search what was on screen…", text: $query)
                .textFieldStyle(.plain)
                .font(.jarvisBody)
                .foregroundStyle(.white.opacity(0.9))
            if !query.isEmpty {
                Button { query = ""; hits = [] } label: {
                    Image(systemName: "xmark.circle.fill").font(.jarvisCaption).foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.jarvisSurface))
        .padding(.horizontal, 2)
        .padding(.top, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            timeline
        } else if hits.isEmpty {
            emptyState(symbol: "text.magnifyingglass", label: "No screen text matches “\(query)”")
        } else {
            hitList
        }
    }

    private var hitList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(hits) { hit in
                    Button { preview = Preview(hit) } label: { hitRow(hit) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 10)
        }
    }

    private func hitRow(_ hit: ScreenRecall.SearchHit) -> some View {
        HStack(alignment: .top, spacing: 10) {
            FrameThumbnail(path: hit.jpegPath)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(hit.appName ?? "?").font(.jarvisRow).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                    Spacer()
                    Text(hit.ts.formatted(.relative(presentation: .named)))
                        .font(.jarvisFootnote).foregroundStyle(.white.opacity(0.5))
                }
                if let title = hit.windowTitle, !title.isEmpty {
                    Text(title).font(.jarvisFootnote).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Text(hit.snippet.isEmpty ? "—" : hit.snippet)
                    .font(.jarvisCaption).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.jarvisSurface))
    }

    // MARK: - Timeline (empty query)

    @ViewBuilder
    private var timeline: some View {
        if recent.isEmpty {
            emptyState(symbol: "clock.arrow.circlepath", label: "No screen frames captured yet")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(hourGroups, id: \.key) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.label.uppercased())
                                .font(.jarvisFootnote.weight(.semibold)).tracking(0.5)
                                .foregroundStyle(.white.opacity(0.45))
                            ForEach(group.frames) { frame in
                                Button { preview = Preview(frame) } label: { timelineRow(frame) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.bottom, 10)
            }
        }
    }

    private func timelineRow(_ frame: ScreenRecall.FrameMeta) -> some View {
        HStack(spacing: 10) {
            FrameThumbnail(path: frame.jpegPath)
            VStack(alignment: .leading, spacing: 2) {
                Text(frame.appName ?? "?").font(.jarvisRow).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                if let title = frame.windowTitle, !title.isEmpty {
                    Text(title).font(.jarvisFootnote).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
            }
            Spacer()
            Text(frame.ts.formatted(date: .omitted, time: .shortened))
                .font(.jarvisFootnote).monospacedDigit().foregroundStyle(.white.opacity(0.5))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.jarvisSurface))
    }

    private struct HourGroup { let key: Date; let label: String; let frames: [ScreenRecall.FrameMeta] }

    private var hourGroups: [HourGroup] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: recent) { frame in
            cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: frame.ts)) ?? frame.ts
        }
        return grouped.keys.sorted(by: >).map { key in
            HourGroup(key: key, label: key.formatted(.dateTime.weekday(.abbreviated).hour()), frames: grouped[key] ?? [])
        }
    }

    // MARK: - Preview overlay

    private struct Preview: Identifiable {
        let id: String
        let jpegPath: String
        let caption: String
        init(_ hit: ScreenRecall.SearchHit) {
            id = hit.id
            jpegPath = hit.jpegPath
            caption = (hit.appName ?? "?") + " · " + hit.ts.formatted(date: .abbreviated, time: .shortened)
        }
        init(_ frame: ScreenRecall.FrameMeta) {
            id = frame.id
            jpegPath = frame.jpegPath
            caption = (frame.appName ?? "?") + " · " + frame.ts.formatted(date: .abbreviated, time: .shortened)
        }
    }

    @ViewBuilder
    private var previewOverlay: some View {
        if let preview {
            PreviewOverlay(path: preview.jpegPath, caption: preview.caption) { self.preview = nil }
                .transition(.opacity)
        }
    }

    // MARK: - Helpers

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { hits = []; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let results = await recall.search(trimmed, limit: 30)
            guard !Task.isCancelled else { return }
            hits = results
        }
    }

    private func emptyState(symbol: String, label: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(.white.opacity(0.5))
            Text(label).font(.jarvisCaption).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Loads a frame JPEG off-main into a small rounded thumbnail.
private struct FrameThumbnail: View {
    let path: String
    var width: CGFloat = 68
    var height: CGFloat = 42
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.06))
                    .overlay(Image(systemName: "photo").font(.jarvisFootnote).foregroundStyle(.white.opacity(0.35)))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task(id: path) {
            let p = path
            // Data is Sendable — read off-main, build NSImage back on the main actor.
            let data = await Task.detached(priority: .utility) { try? Data(contentsOf: URL(fileURLWithPath: p)) }.value
            if let data { image = NSImage(data: data) }
        }
    }
}

/// Full-frame preview shown over the pane; tap anywhere to dismiss.
private struct PreviewOverlay: View {
    let path: String
    let caption: String
    let onClose: () -> Void
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()
            VStack(spacing: 8) {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.jarvisStroke, lineWidth: 1))
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(caption).font(.jarvisCaption).foregroundStyle(.white.opacity(0.7))
            }
            .padding(20)
        }
        .contentShape(Rectangle())
        .onTapGesture { onClose() }
        .task(id: path) {
            let p = path
            let data = await Task.detached(priority: .userInitiated) { try? Data(contentsOf: URL(fileURLWithPath: p)) }.value
            if let data { image = NSImage(data: data) }
        }
    }
}
