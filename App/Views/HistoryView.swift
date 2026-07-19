import JAgent
import MarkdownUI
import SwiftUI

struct HistoryView: View {
    let sessions: SessionManager
    @State private var segments: [SessionManager.SegmentSummary] = []
    @State private var expanded: String?
    /// Messages keyed by segment id, so expanding one segment can never show
    /// another segment's rows while its own are still loading.
    @State private var messagesBySegment: [String: [SessionManager.StoredMessage]] = [:]

    var body: some View {
        Group {
            if segments.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("No conversations yet")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(segments) { segment in
                            SegmentRow(
                                segment: segment,
                                isOpen: expanded == segment.id,
                                messages: messagesBySegment[segment.id],
                                toggle: { toggle(segment) }
                            )
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .task { segments = await sessions.recentSegments() }
    }

    private func toggle(_ segment: SessionManager.SegmentSummary) {
        if expanded == segment.id {
            withAnimation(.snappy(duration: 0.3)) { expanded = nil }
        } else {
            withAnimation(.snappy(duration: 0.3)) { expanded = segment.id }
            if messagesBySegment[segment.id] == nil {
                Task {
                    let loaded = await sessions.messages(inSegment: segment.id)
                    withAnimation(.snappy(duration: 0.3)) { messagesBySegment[segment.id] = loaded }
                }
            }
        }
    }
}

private struct SegmentRow: View {
    let segment: SessionManager.SegmentSummary
    let isOpen: Bool
    let messages: [SessionManager.StoredMessage]?
    let toggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: toggle) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(segment.title ?? (segment.preview.isEmpty ? "Conversation" : segment.preview))
                            .font(.jarvisBody.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                        Text(segment.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.jarvisFootnote)
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.jarvisFootnote)
                        .foregroundStyle(.white.opacity(0.55))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)

            if isOpen {
                if let messages {
                    ForEach(messages) { message in
                        historyMessage(message)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(isHovering ? 0.09 : 0.05))
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
    }

    @ViewBuilder
    private func historyMessage(_ message: SessionManager.StoredMessage) -> some View {
        let text = message.content.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined()
        HStack(alignment: .top, spacing: 12) {
            Text(message.role == .user ? "You" : "Jarvis")
                .font(.jarvisFootnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
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
}
