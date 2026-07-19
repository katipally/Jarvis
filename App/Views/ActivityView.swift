import JAgent
import JMemory
import JStore
import SwiftUI

struct ActivityView: View {
    let agent: AgentServices
    var graphReader: GraphReader?
    var memoryStore: MemoryStore?
    var taskStore: TaskStore?
    @State private var segment = 0

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $segment) {
                Text("Runs").tag(0)
                Text("Memory").tag(1)
                Text("Graph").tag(2)
                Text("Rewind").tag(3)
                Text("Tasks").tag(4)
                Text("Files").tag(5)
                Text("Log").tag(6)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 460)
            .padding(.top, 10)

            Group {
                switch segment {
                case 0: RunsPane(runStore: agent.runStore)
                case 1:
                    if let memoryStore { MemoriesPane(store: memoryStore) }
                    else { ComingSoonPane(symbol: "brain", label: "Memories") }
                case 2:
                    if let graphReader { GraphView(reader: graphReader) }
                    else { ComingSoonPane(symbol: "point.3.connected.trianglepath.dotted", label: "Knowledge graph") }
                case 3: RewindPane(recall: agent.screenRecall)
                case 4:
                    if let taskStore { TasksPane(store: taskStore) }
                    else { ComingSoonPane(symbol: "checklist", label: "Tasks") }
                case 5: ArtifactsPane(database: agent.runStore.database)
                case 6: DecisionsPane(approvalStore: agent.approvalStore)
                default: EmptyView()
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
        .animation(.snappy(duration: 0.3), value: segment)
    }
}

private struct RunsPane: View {
    let runStore: RunStore
    @State private var runs: [RunStore.RunSummary] = []
    @State private var selectedRunID: String?

    var body: some View {
        Group {
            if let selectedRunID {
                RunDetailView(runID: selectedRunID, runStore: runStore) {
                    self.selectedRunID = nil
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if runs.isEmpty {
                ComingSoonPane(symbol: "play.circle", label: "No agent runs yet")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(runs) { run in
                            Button { selectedRunID = run.id } label: { RunRowCard(run: run) }
                                .buttonStyle(.plain)
                                .pointerStyle(.link)
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: selectedRunID)
        // Live: streams as runs + tool calls land, instead of a one-shot load.
        .task {
            do {
                for try await list in runStore.observeRecentRuns() { runs = list }
            } catch {
                // Observation ended (tab switch / read error): keep last snapshot.
            }
        }
    }
}

private struct DecisionsPane: View {
    let approvalStore: ApprovalStore
    @State private var events: [ApprovalEventRow] = []

    var body: some View {
        Group {
            if events.isEmpty {
                ComingSoonPane(symbol: "checkmark.shield", label: "No decisions yet")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(events) { event in
                            HStack(spacing: 10) {
                                Image(systemName: event.allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .font(.system(size: 12))
                                    .foregroundStyle(event.allowed ? Color.jarvisSuccess : Color.jarvisError)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(event.summary ?? event.toolName)
                                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                                    Text("\(event.allowed ? "allowed" : "denied") · \(event.decidedBy)")
                                        .font(.jarvisFootnote).foregroundStyle(.white.opacity(0.55))
                                }
                                Spacer()
                                Text(event.createdAt.formatted(date: .omitted, time: .shortened))
                                    .font(.jarvisFootnote).monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.jarvisSurface))
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        .task { events = await approvalStore.recentDecisions() }
    }
}

private struct ComingSoonPane: View {
    let symbol: String
    let label: String

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(.white.opacity(0.55))
            Text(label).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
