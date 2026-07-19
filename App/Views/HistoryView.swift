import JAgent
import MarkdownUI
import SwiftUI

struct HistoryView: View {
    let sessions: SessionManager
    @State private var segments: [SessionManager.SegmentSummary] = []
    @State private var expanded: String?
    @State private var messages: [SessionManager.StoredMessage] = []

    var body: some View {
        Group {
            if segments.isEmpty {
                VStack(spacing: 11) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("No conversations yet")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 11) {
                        ForEach(segments) { segment in
                            segmentRow(segment)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .task { segments = await sessions.recentSegments() }
    }

    @ViewBuilder
    private func segmentRow(_ segment: SessionManager.SegmentSummary) -> some View {
        let isOpen = expanded == segment.id
        VStack(alignment: .leading, spacing: 11) {
            Button {
                Task { await toggle(segment) }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(segment.title ?? (segment.preview.isEmpty ? "Conversation" : segment.preview))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                        Text(segment.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .buttonStyle(.plain)

            if isOpen {
                ForEach(messages) { message in
                    historyMessage(message)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.05)))
    }

    @ViewBuilder
    private func historyMessage(_ message: SessionManager.StoredMessage) -> some View {
        let text = message.content.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined()
        HStack(alignment: .top, spacing: 11) {
            Text(message.role == .user ? "You" : "Jarvis")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 42, alignment: .leading)
            if message.role == .user {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                Markdown(text).markdownTheme(.jarvis).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggle(_ segment: SessionManager.SegmentSummary) async {
        if expanded == segment.id {
            expanded = nil
            messages = []
        } else {
            expanded = segment.id
            messages = await sessions.messages(inSegment: segment.id)
        }
    }
}
