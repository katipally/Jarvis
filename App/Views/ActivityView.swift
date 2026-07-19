import JAgent
import JMemory
import JStore
import SwiftUI

struct ActivityView: View {
    let agent: AgentServices
    var graphReader: GraphReader?
    @State private var segment = 0

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $segment) {
                Text("Runs").tag(0)
                Text("Graph").tag(1)
                Text("Artifacts").tag(2)
                Text("Decisions").tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 380)
            .padding(.top, 10)

            switch segment {
            case 0: RunsPane(runStore: agent.runStore)
            case 1:
                if let graphReader { GraphView(reader: graphReader) }
                else { ComingSoonPane(symbol: "point.3.connected.trianglepath.dotted", label: "Knowledge graph") }
            case 3: DecisionsPane(approvalStore: agent.approvalStore)
            default: ComingSoonPane(symbol: "shippingbox", label: "Artifacts")
            }
        }
    }
}

private struct RunsPane: View {
    let runStore: RunStore
    @State private var runs: [RunStore.RunSummary] = []

    var body: some View {
        Group {
            if runs.isEmpty {
                ComingSoonPane(symbol: "play.circle", label: "No agent runs yet")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(runs) { run in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    statusDot(run.status)
                                    Text(run.kind.capitalized)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.85))
                                    Spacer()
                                    Text(run.startedAt.formatted(date: .omitted, time: .shortened))
                                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                                }
                                ForEach(run.toolCalls) { call in
                                    HStack(spacing: 6) {
                                        Image(systemName: call.state == "error" ? "exclamationmark.triangle" : "gearshape")
                                            .font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                                        Text(call.name).font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
                                        Spacer()
                                        Text(call.state).font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
                                    }
                                }
                            }
                            .padding(13)
                            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.05)))
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        .task { runs = await runStore.recentRuns() }
    }

    private func statusDot(_ status: String) -> some View {
        Circle()
            .fill(status == "done" ? Color.green : status == "error" ? Color.red : Color.yellow)
            .frame(width: 7, height: 7)
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
                    LazyVStack(alignment: .leading, spacing: 9) {
                        ForEach(events) { event in
                            HStack(spacing: 10) {
                                Image(systemName: event.allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(event.allowed ? Color(red: 0.4, green: 0.85, blue: 0.5) : Color(red: 1.0, green: 0.5, blue: 0.5))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(event.summary ?? event.toolName)
                                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                                    Text("\(event.allowed ? "allowed" : "denied") · \(event.decidedBy)")
                                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                                }
                                Spacer()
                                Text(event.createdAt.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
                            }
                            .padding(13)
                            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.05)))
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
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(.white.opacity(0.3))
            Text(label).font(.system(size: 12)).foregroundStyle(.white.opacity(0.35))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
