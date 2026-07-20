import GRDB
import JAgent
import JMemory
import JStore
import SwiftUI

/// Activity tab: three panes. Timeline is one live chronological feed of
/// everything Jarvis does (runs, meetings, nudges — delivered and held back —
/// approvals, artifacts); Memory is the memory list with a graph explorer;
/// Tasks is the actionable to-do surface.
struct ActivityView: View {
    let agent: AgentServices
    var graphReader: GraphReader?
    var memoryStore: MemoryStore?
    var taskStore: TaskStore?
    @State private var segment = 0

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $segment) {
                Text("Timeline").tag(0)
                Text("Memory").tag(1)
                Text("Tasks").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)
            .padding(.top, 10)

            Group {
                switch segment {
                case 0:
                    TimelinePane(agent: agent)
                case 1:
                    if let memoryStore {
                        MemoriesPane(store: memoryStore, graphReader: graphReader)
                    } else {
                        JarvisEmptyState(symbol: "brain", title: "Memory isn't available")
                    }
                default:
                    if let taskStore {
                        TasksPane(store: taskStore)
                    } else {
                        JarvisEmptyState(symbol: "checklist", title: "Tasks aren't available")
                    }
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
        .animation(.snappy(duration: 0.3), value: segment)
    }
}

// MARK: - Timeline

private enum TimelineSelection: Equatable {
    case run(String)
    case meeting(String)
}

private struct TimelinePane: View {
    let agent: AgentServices

    @State private var entries: [TimelineStore.Entry]?
    @State private var selection: TimelineSelection?

    var body: some View {
        Group {
            switch selection {
            case .run(let id):
                RunDetailView(runID: id, runStore: agent.runStore) { selection = nil }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            case .meeting(let id):
                MeetingDetailView(meetingID: id, database: agent.runStore.database) { selection = nil }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            case nil:
                feed
            }
        }
        .animation(.snappy(duration: 0.25), value: selection)
        .task {
            do {
                for try await list in TimelineStore(database: agent.runStore.database).observe() {
                    entries = list
                }
            } catch {
                // Observation ended (tab switch / read error): keep last snapshot.
                if entries == nil { entries = [] }
            }
        }
    }

    @ViewBuilder
    private var feed: some View {
        if let entries {
            if entries.isEmpty {
                JarvisEmptyState(
                    symbol: "sparkles",
                    title: "Nothing here yet",
                    message: "Everything Jarvis does shows up here — runs, meetings, nudges, and the files it creates. Ask Jarvis anything to get started."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                        ForEach(grouped, id: \.key) { group in
                            Section {
                                ForEach(group.rows) { entry in
                                    TimelineEntryRow(entry: entry) { selection = $0 }
                                }
                            } header: {
                                Text(group.key.uppercased())
                                    .font(.jarvisCaption.weight(.semibold))
                                    .foregroundStyle(Color.jarvisTextTertiary)
                                    .tracking(0.5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                    .background(.black)
                            }
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        } else {
            JarvisLoadingState()
        }
    }

    private var grouped: [(key: String, rows: [TimelineStore.Entry])] {
        let cal = Calendar.current
        var order: [String] = []
        var map: [String: [TimelineStore.Entry]] = [:]
        for entry in entries ?? [] {
            let label: String = if cal.isDateInToday(entry.date) {
                "Today"
            } else if cal.isDateInYesterday(entry.date) {
                "Yesterday"
            } else {
                entry.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            }
            if map[label] == nil { order.append(label) }
            map[label, default: []].append(entry)
        }
        return order.map { (key: $0, rows: map[$0] ?? []) }
    }
}

/// One feed row. Runs and meetings navigate to a detail view; nudges expand in
/// place; approvals are read-only; artifacts carry Quick Look / reveal actions.
private struct TimelineEntryRow: View {
    let entry: TimelineStore.Entry
    let onSelect: (TimelineSelection) -> Void

    var body: some View {
        switch entry.payload {
        case .run(let run, let artifactCount):
            Button { onSelect(.run(run.id)) } label: {
                RunRowCard(run: run, artifactCount: artifactCount)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
        case .meeting(let meeting, let taskCount):
            Button { onSelect(.meeting(meeting.id)) } label: {
                MeetingRowCard(meeting: meeting, taskCount: taskCount)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
        case .nudge(let nudge):
            NudgeRowCard(nudge: nudge)
        case .approval(let event):
            ApprovalRowCard(event: event)
        case .artifact(let artifact):
            ArtifactRowView(artifact: artifact)
        }
    }
}

private struct MeetingRowCard: View {
    let meeting: MeetingRow
    let taskCount: Int

    private var duration: TimeInterval? {
        meeting.endedAt.map { $0.timeIntervalSince(meeting.startedAt) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.jarvisCaption)
                    .foregroundStyle(Color.jarvisAccent)
                Text(meeting.title ?? (meeting.endedAt == nil ? "Meeting in progress" : "Meeting"))
                    .font(.jarvisRow)
                    .foregroundStyle(Color.jarvisTextPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(meeting.startedAt.formatted(date: .omitted, time: .shortened))
                    .font(.jarvisFootnote).monospacedDigit()
                    .foregroundStyle(Color.jarvisTextTertiary)
            }
            HStack(spacing: 10) {
                if let dur = RunFormat.duration(duration) { metric(dur) }
                if taskCount > 0 { metric("\(taskCount) task\(taskCount == 1 ? "" : "s")") }
                if meeting.summaryStatus == MeetingRow.SummaryStatus.skipped.rawValue { metric("no summary") }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: JarvisRadius.card, style: .continuous).fill(Color.jarvisSurface))
        .contentShape(Rectangle())
    }

    private func metric(_ text: String) -> some View {
        Text(text)
            .font(.jarvisFootnote).monospacedDigit()
            .foregroundStyle(Color.jarvisTextTertiary)
    }
}

private struct NudgeRowCard: View {
    let nudge: NudgeRow
    @State private var expanded = false

    private var suppressed: Bool { nudge.state == "suppressed" }

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: suppressed ? "bell.slash" : "bell.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.jarvisCaption)
                        .foregroundStyle(suppressed ? Color.jarvisTextTertiary : Color.jarvisLink)
                    Text(suppressed ? "Held back" : (nudge.title ?? "Nudge"))
                        .font(.jarvisRow)
                        .foregroundStyle(suppressed ? Color.jarvisTextSecondary : Color.jarvisTextPrimary)
                    Text(triggerLabel)
                        .font(.jarvisFootnote)
                        .foregroundStyle(Color.jarvisTextTertiary)
                    Spacer(minLength: 0)
                    Text(nudge.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.jarvisFootnote).monospacedDigit()
                        .foregroundStyle(Color.jarvisTextTertiary)
                }
                Text(nudge.body)
                    .font(.jarvisCaption)
                    .foregroundStyle(suppressed ? Color.jarvisTextTertiary : Color.jarvisTextSecondary)
                    .lineLimit(expanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: JarvisRadius.card, style: .continuous).fill(Color.jarvisSurface))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(suppressed ? 0.75 : 1)
    }

    private var triggerLabel: String {
        switch nudge.trigger {
        case "context_switch": "· screen"
        case "heartbeat": "· heartbeat"
        case "commitment": "· commitment"
        case "brief": "· brief"
        case "cron": "· scheduled"
        default: ""
        }
    }
}

private struct ApprovalRowCard: View {
    let event: ApprovalEventRow

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: event.allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 12))
                .foregroundStyle(event.allowed ? Color.jarvisSuccess : Color.jarvisError)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.summary ?? event.toolName)
                    .font(.jarvisRow).foregroundStyle(Color.jarvisTextPrimary).lineLimit(1)
                Text("\(event.allowed ? "Allowed" : "Denied") · \(event.decidedBy)")
                    .font(.jarvisFootnote).foregroundStyle(Color.jarvisTextTertiary)
            }
            Spacer(minLength: 0)
            Text(event.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.jarvisFootnote).monospacedDigit()
                .foregroundStyle(Color.jarvisTextTertiary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: JarvisRadius.card, style: .continuous).fill(Color.jarvisSurface))
    }
}

// MARK: - Meeting detail

/// A finished meeting: summary header plus the attributed transcript.
private struct MeetingDetailView: View {
    let meetingID: String
    let database: JarvisDatabase
    var onBack: () -> Void

    @State private var meeting: MeetingRow?
    @State private var segments: [MeetingSegmentRow] = []
    @State private var didLoad = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let meeting {
                    header(meeting)

                    if let overview = meeting.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.jarvisBody)
                            .foregroundStyle(Color.jarvisTextPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !segments.isEmpty {
                        Text("Transcript")
                            .font(.jarvisFootnote.weight(.semibold))
                            .foregroundStyle(Color.jarvisTextTertiary)
                            .padding(.top, 4)
                        ForEach(segments) { segment in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(segment.source == MeetingSegmentRow.Source.mic.rawValue ? "You" : "Them")
                                    .font(.jarvisFootnote.weight(.semibold))
                                    .foregroundStyle(Color.jarvisTextTertiary)
                                    .frame(width: 34, alignment: .leading)
                                Text(segment.text)
                                    .font(.jarvisCaption)
                                    .foregroundStyle(Color.jarvisTextSecondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else if meeting.overview?.isEmpty ?? true {
                        Text("No transcript was captured for this meeting.")
                            .font(.jarvisCaption)
                            .foregroundStyle(Color.jarvisTextTertiary)
                    }
                } else if !didLoad {
                    JarvisLoadingState().padding(.top, 30)
                } else {
                    Text("Couldn't load this meeting.")
                        .font(.jarvisCaption)
                        .foregroundStyle(Color.jarvisTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 30)
                }
            }
            .padding(.bottom, 10)
        }
        .task(id: meetingID) {
            didLoad = false
            let loaded: (MeetingRow, [MeetingSegmentRow])? = try? await database.reader.read { db in
                guard let m = try MeetingRow.fetchOne(db, key: meetingID) else { return nil }
                let segs = try MeetingSegmentRow
                    .filter(Column("meeting_id") == meetingID)
                    .order(Column("ts"))
                    .fetchAll(db)
                return (m, segs)
            }
            meeting = loaded?.0
            segments = loaded?.1 ?? []
            didLoad = true
        }
    }

    private func header(_ m: MeetingRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.jarvisSurfaceHover))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .accessibilityLabel("Back to timeline")
                Image(systemName: "waveform")
                    .font(.jarvisCaption)
                    .foregroundStyle(Color.jarvisAccent)
                Text(m.title ?? "Meeting")
                    .font(.jarvisRow)
                    .foregroundStyle(Color.jarvisTextPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            HStack(spacing: 14) {
                Text(m.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.jarvisFootnote).foregroundStyle(Color.jarvisTextTertiary)
                if let end = m.endedAt, let dur = RunFormat.duration(end.timeIntervalSince(m.startedAt)) {
                    Text(dur).font(.jarvisFootnote).monospacedDigit()
                        .foregroundStyle(Color.jarvisTextTertiary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: JarvisRadius.card, style: .continuous).fill(Color.jarvisSurface))
    }
}
