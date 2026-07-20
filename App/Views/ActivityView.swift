import GRDB
import JAgent
import JKnowledge
import JStore
import SwiftUI

/// Activity tab — the consciousness feed. Feed is a live chronological stream
/// of what Jarvis did AND decided (world syncs, decisions with reasons —
/// including suppressed ones — nudges, runs, meetings, approvals); Sources is
/// the per-world sync control surface; Tasks is the actionable to-do surface.
/// The knowledge graph lives in its own notch tab.
struct ActivityView: View {
    let agent: AgentServices
    var knowledge: KnowledgeService?
    var worlds: WorldSyncEngine?
    var graphReader: GraphReader?
    var taskStore: TaskStore?
    @State private var segment = 0

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $segment) {
                Text("Feed").tag(0)
                Text("Graph").tag(1)
                Text("Sources").tag(2)
                Text("Tasks").tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 400)
            .padding(.top, 10)

            Group {
                switch segment {
                case 0:
                    TimelinePane(agent: agent)
                case 1:
                    if let store = knowledge?.store {
                        MemoriesPane(store: store, graphReader: graphReader, startInGraph: true)
                    } else {
                        JarvisEmptyState(symbol: "point.3.connected.trianglepath.dotted",
                                         title: "The graph isn't available")
                    }
                case 2:
                    if let knowledge, let worlds {
                        ScrollView { SourcesPane(knowledge: knowledge, engine: worlds).padding(.bottom, 10) }
                    } else {
                        JarvisEmptyState(symbol: "antenna.radiowaves.left.and.right", title: "Sources aren't available")
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

    @State private var entries: [ConsciousnessFeedStore.Entry]?
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
                for try await list in ConsciousnessFeedStore(database: agent.runStore.database).observe() {
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

    private var grouped: [(key: String, rows: [ConsciousnessFeedStore.Entry])] {
        let cal = Calendar.current
        var order: [String] = []
        var map: [String: [ConsciousnessFeedStore.Entry]] = [:]
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
    let entry: ConsciousnessFeedStore.Entry
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
        case .ingest(let run, let worldName):
            IngestRowCard(run: run, worldName: worldName)
        case .decision(let decision):
            DecisionRowCard(decision: decision)
        case .quietSpan(let count, let from, let to):
            QuietSpanRow(count: count, from: from, to: to)
        }
    }
}

/// A world sync that brought something in: "Mail synced — 12 items, 5 facts".
private struct IngestRowCard: View {
    let run: IngestRunRow
    let worldName: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.jarvisCaption)
                .foregroundStyle(Color.jarvisAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(worldName) synced")
                    .font(.jarvisRow).foregroundStyle(Color.jarvisTextPrimary)
                Text(summary)
                    .font(.jarvisFootnote).foregroundStyle(Color.jarvisTextTertiary)
            }
            Spacer(minLength: 0)
            Text(run.startedAt.formatted(date: .omitted, time: .shortened))
                .font(.jarvisFootnote).monospacedDigit()
                .foregroundStyle(Color.jarvisTextTertiary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: JarvisRadius.card, style: .continuous).fill(Color.jarvisSurface))
    }

    private var summary: String {
        var parts: [String] = []
        if run.episodesAdded > 0 { parts.append("\(run.episodesAdded) item\(run.episodesAdded == 1 ? "" : "s")") }
        if run.factsAdded > 0 { parts.append("\(run.factsAdded) fact\(run.factsAdded == 1 ? "" : "s")") }
        if run.entitiesAdded > 0 { parts.append("\(run.entitiesAdded) entit\(run.entitiesAdded == 1 ? "y" : "ies")") }
        if run.edgesAdded > 0 { parts.append("\(run.edgesAdded) link\(run.edgesAdded == 1 ? "" : "s")") }
        return parts.isEmpty ? "up to date" : parts.joined(separator: ", ")
    }
}

/// One engine verdict with its reason — the "why" line is the whole point.
private struct DecisionRowCard: View {
    let decision: DecisionRow
    @State private var expanded = false

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .symbolRenderingMode(.hierarchical)
                        .font(.jarvisCaption)
                        .foregroundStyle(tint)
                    Text(headline)
                        .font(.jarvisRow)
                        .foregroundStyle(Color.jarvisTextPrimary)
                    Text("· \(decision.source)")
                        .font(.jarvisFootnote)
                        .foregroundStyle(Color.jarvisTextTertiary)
                    Spacer(minLength: 0)
                    Text(decision.ts.formatted(date: .omitted, time: .shortened))
                        .font(.jarvisFootnote).monospacedDigit()
                        .foregroundStyle(Color.jarvisTextTertiary)
                }
                Text(decision.reason)
                    .font(.jarvisFootnote)
                    .foregroundStyle(Color.jarvisTextTertiary)
                    .lineLimit(expanded ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: JarvisRadius.card, style: .continuous)
                .fill(Color.jarvisSurface.opacity(0.6)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var headline: String {
        switch decision.action {
        case "acknowledged": "Acknowledged"
        case "reacted": "Looked into it"
        case "escalated": "Escalated"
        case "notified": "Spoke up"
        case "suppressed": "Held back"
        case "budget_downgraded": "Deferred"
        case "noted_fact": "Learned"
        case "task_added": "Added a task"
        case "quiet": "Stayed quiet"
        default: decision.action.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private var symbol: String {
        switch decision.action {
        case "notified": "bell.fill"
        case "suppressed", "budget_downgraded": "bell.slash"
        case "escalated": "exclamationmark.triangle"
        case "reacted": "magnifyingglass"
        case "noted_fact": "brain"
        case "task_added": "checklist"
        default: "moon.zzz"
        }
    }

    private var tint: Color {
        switch decision.action {
        case "notified": .jarvisLink
        case "escalated": .jarvisWarning
        case "noted_fact", "task_added": .jarvisAccent
        default: .jarvisTextTertiary
        }
    }
}

/// A collapsed run of routine quiet verdicts — proof the engine is alive
/// without a wall of noise.
private struct QuietSpanRow: View {
    let count: Int
    let from: Date
    let to: Date

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.zzz")
                .font(.jarvisFootnote)
                .foregroundStyle(Color.jarvisTextTertiary)
            Text("Handled \(count) background events quietly")
                .font(.jarvisFootnote)
                .foregroundStyle(Color.jarvisTextTertiary)
            Spacer(minLength: 0)
            Text("\(from.formatted(date: .omitted, time: .shortened))–\(to.formatted(date: .omitted, time: .shortened))")
                .font(.jarvisFootnote).monospacedDigit()
                .foregroundStyle(Color.jarvisTextTertiary.opacity(0.7))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
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
