import JAgent
import SwiftUI

/// Full chat history: every past conversation (session segment) is one chat.
/// The list shows conversation cards; opening one renders the whole exchange
/// with the same visuals as the live transcript.
struct HistoryView: View {
    let sessions: SessionManager
    @State private var segments: [SessionManager.SegmentSummary] = []
    @State private var selected: SessionManager.SegmentSummary?
    @State private var detailMessages: [SessionManager.StoredMessage]?
    @State private var renaming: SessionManager.SegmentSummary?
    @State private var renameText = ""
    @State private var pendingDelete: SessionManager.SegmentSummary?

    var body: some View {
        ZStack {
            if let selected {
                conversationDetail(selected)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            } else {
                conversationList
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .animation(.snappy(duration: 0.3), value: selected?.id)
        .task { segments = await sessions.recentSegments() }
        .alert("Rename conversation", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Title", text: $renameText)
            Button("Rename") {
                if let segment = renaming {
                    let title = renameText
                    Task {
                        await sessions.rename(segmentID: segment.id, title: title)
                        segments = await sessions.recentSegments()
                    }
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog(
            "Delete “\(pendingDelete.map(title(for:)) ?? "conversation")”?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let segment = pendingDelete {
                    Task {
                        await sessions.deleteSegment(segment.id)
                        segments = await sessions.recentSegments()
                    }
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    private func title(for segment: SessionManager.SegmentSummary) -> String {
        segment.title ?? (segment.preview.isEmpty ? "Conversation" : segment.preview)
    }

    // MARK: - List

    @ViewBuilder
    private var conversationList: some View {
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
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(segments) { segment in
                        ConversationCard(
                            segment: segment,
                            open: { open(segment) },
                            rename: {
                                renameText = segment.title ?? ""
                                renaming = segment
                            },
                            delete: { pendingDelete = segment }
                        )
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .black.opacity(0.1)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 14)
                }
            }
        }
    }

    private func open(_ segment: SessionManager.SegmentSummary) {
        detailMessages = nil
        selected = segment
        Task {
            let loaded = await sessions.messages(inSegment: segment.id)
            withAnimation(.snappy(duration: 0.25)) { detailMessages = loaded }
        }
    }

    // MARK: - Detail (one conversation = one chat)

    private func conversationDetail(_ segment: SessionManager.SegmentSummary) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    selected = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.white.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Back to conversations")

                VStack(alignment: .leading, spacing: 1) {
                    Text(segment.title ?? (segment.preview.isEmpty ? "Conversation" : segment.preview))
                        .font(.jarvisBody.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    Text(segment.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.jarvisFootnote)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
            }
            .padding(.bottom, 10)

            if let detailMessages {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(detailMessages) { stored in
                            MessageRow(message: DisplayMessage(stored: stored))
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.hidden)
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.black.opacity(0.05), .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: 12)
                        Rectangle()
                        LinearGradient(colors: [.black, .black.opacity(0.1)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 12)
                    }
                }
            } else {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            }
        }
    }
}

private struct ConversationCard: View {
    let segment: SessionManager.SegmentSummary
    let open: () -> Void
    let rename: () -> Void
    let delete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(segment.title ?? (segment.preview.isEmpty ? "Conversation" : segment.preview))
                        .font(.jarvisBody.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(segment.startedAt.formatted(date: .abbreviated, time: .shortened))
                        Text("·")
                        Text("\(segment.messageCount) messages")
                    }
                    .font(.jarvisFootnote)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()

                // Hover-revealed management, mirrored in the context menu.
                if isHovering {
                    HStack(spacing: 2) {
                        Button(action: rename) {
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.65))
                                .frame(width: 24, height: 24)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        .accessibilityLabel("Rename conversation")

                        Button(action: delete) {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.65))
                                .frame(width: 24, height: 24)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        .accessibilityLabel("Delete conversation")
                    }
                    .transition(.opacity)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(14)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovering ? Color.jarvisSurfaceHover : Color.jarvisSurface)
                .strokeBorder(Color.jarvisStroke, lineWidth: 1)
        )
        .contextMenu {
            Button("Rename…", action: rename)
            Button("Delete", role: .destructive, action: delete)
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}
