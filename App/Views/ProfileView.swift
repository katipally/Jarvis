import GRDB
import JKnowledge
import JStore
import SwiftUI

/// Profile tab — your virtual profile and how Jarvis reasons about it.
/// Graph = the knowledge graph Jarvis built from your data. Decisions = what
/// Jarvis chose to tell you (or held back) and WHY. Follow-ups = the things
/// it's tracking to remind you about.
struct ProfileView: View {
    var knowledge: KnowledgeService?
    var graphReader: GraphReader?
    var taskStore: TaskStore?
    let database: JarvisDatabase
    @State private var segment = 0

    var body: some View {
        VStack(spacing: 8) {
            Picker("", selection: $segment) {
                Text("Graph").tag(0)
                Text("Decisions").tag(1)
                Text("Follow-ups").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 400)
            .padding(.top, 6)

            Group {
                switch segment {
                case 0:
                    if let store = knowledge?.store {
                        MemoriesPane(store: store, graphReader: graphReader, startInGraph: true)
                    } else {
                        JarvisEmptyState(symbol: "point.3.connected.trianglepath.dotted",
                                         title: "The graph isn't available")
                    }
                case 1:
                    DecisionsPane(database: database)
                default:
                    if let taskStore {
                        TasksPane(store: taskStore)
                    } else {
                        JarvisEmptyState(symbol: "checklist", title: "Follow-ups aren't available")
                    }
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
        .animation(.snappy(duration: 0.3), value: segment)
    }
}

/// The "why" surface: every verdict Jarvis reached — spoke up, held back,
/// learned something, stayed quiet — with its reason. Read straight off the
/// decision ledger (Hive's explain-decision pattern).
private struct DecisionsPane: View {
    let database: JarvisDatabase

    @State private var rows: [DecisionRow]?

    var body: some View {
        Group {
            if let rows {
                if rows.isEmpty {
                    JarvisEmptyState(
                        symbol: "brain",
                        title: "No decisions yet",
                        message: "As Jarvis watches your world it decides what's worth telling you — and what isn't. Everything it decides, and why, shows up here.")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(rows) { DecisionRowCard(decision: $0) }
                        }
                        .padding(.bottom, 10)
                    }
                }
            } else {
                JarvisLoadingState()
            }
        }
        .task {
            do {
                // Live: re-emits whenever the engine writes a new verdict.
                let observation = ValueObservation.tracking { db in
                    try DecisionRow.order(Column("ts").desc).limit(120).fetchAll(db)
                }
                for try await list in observation.values(in: database.reader) {
                    rows = list
                }
            } catch {
                if rows == nil { rows = [] }
            }
        }
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
        case "task_added": "Added a follow-up"
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
