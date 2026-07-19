import JStore
import SwiftUI

/// Activity pane for extraction-surfaced tasks. Suggested tasks await review
/// (accept → open, or dismiss); open tasks can be marked done. Matches the
/// RunsPane / DecisionsPane card style.
struct TasksPane: View {
    let store: TaskStore

    @State private var suggested: [TaskRow] = []
    @State private var open: [TaskRow] = []

    var body: some View {
        Group {
            if suggested.isEmpty && open.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if !suggested.isEmpty { section("Suggested", rows: suggested, suggested: true) }
                        if !open.isEmpty { section("Open", rows: open, suggested: false) }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        .task { await reload() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "checklist").font(.system(size: 22, weight: .light)).foregroundStyle(.white.opacity(0.55))
            Text("No tasks yet").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func section(_ header: String, rows: [TaskRow], suggested isSuggested: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header.uppercased())
                .font(.jarvisCaption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5)).tracking(0.5)
            ForEach(rows) { task in
                HStack(spacing: 10) {
                    Image(systemName: isSuggested ? "sparkles" : "circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(task.text)
                        .font(.jarvisRow)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if isSuggested {
                        iconButton("checkmark", tint: .jarvisSuccess) { set(task.id, .open) }
                        iconButton("xmark", tint: .jarvisError) { set(task.id, .dismissed) }
                    } else {
                        iconButton("checkmark.circle", tint: .jarvisSuccess) { set(task.id, .done) }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.jarvisSurface))
            }
        }
    }

    private func iconButton(_ symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }

    private func set(_ id: String, _ status: TaskRow.Status) {
        Task {
            await store.setTaskStatus(id, status)
            await reload()
        }
    }

    private func reload() async {
        suggested = await store.tasks(statuses: [.suggested])
        open = await store.tasks(statuses: [.open])
    }
}
