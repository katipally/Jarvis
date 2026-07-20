import JStore
import SwiftUI

/// Tasks pane: live list of suggested (extraction-surfaced, awaiting review)
/// and open tasks. Add manually, edit inline, set a due date, mark done.
struct TasksPane: View {
    let store: TaskStore

    @State private var tasks: [TaskRow]?
    @State private var newText = ""
    @State private var editingID: String?
    @State private var draft = ""
    @FocusState private var addFocused: Bool

    private var suggested: [TaskRow] { (tasks ?? []).filter { $0.status == TaskRow.Status.suggested.rawValue } }
    private var open: [TaskRow] { (tasks ?? []).filter { $0.status == TaskRow.Status.open.rawValue } }

    var body: some View {
        VStack(spacing: 8) {
            addRow

            if let tasks {
                if tasks.isEmpty {
                    JarvisEmptyState(
                        symbol: "checklist",
                        title: "No tasks yet",
                        message: "Jarvis suggests tasks from your chats — or add one above."
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if !suggested.isEmpty { section("Suggested", rows: suggested, suggested: true) }
                            if !open.isEmpty { section("Open", rows: open, suggested: false) }
                        }
                        .padding(.bottom, 10)
                    }
                }
            } else {
                JarvisLoadingState()
            }
        }
        .animation(.snappy(duration: 0.25), value: tasks?.count)
        .task {
            do {
                for try await list in store.observeActiveTasks() { tasks = list }
            } catch {
                if tasks == nil { tasks = [] }
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.jarvisCaption)
                .foregroundStyle(Color.jarvisTextTertiary)
            TextField("Add a task", text: $newText)
                .textFieldStyle(.plain)
                .font(.jarvisCaption)
                .foregroundStyle(Color.jarvisTextPrimary)
                .focused($addFocused)
                .onSubmit(addTask)
            if !newText.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: addTask) {
                    Image(systemName: "arrow.turn.down.left")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add task")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: JarvisRadius.control, style: .continuous).fill(Color.jarvisSurface))
        .padding(.horizontal, 2)
    }

    private func addTask() {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        newText = ""
        Task { await store.addTask(text: text, source: .manual, sourceID: nil, status: .open) }
    }

    private func section(_ header: String, rows: [TaskRow], suggested isSuggested: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            JarvisSectionHeader(title: header)
            ForEach(rows) { task in
                row(task, isSuggested: isSuggested)
            }
        }
    }

    @ViewBuilder
    private func row(_ task: TaskRow, isSuggested: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: isSuggested ? "sparkles" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.jarvisTextTertiary)

                if editingID == task.id {
                    TextField("Task", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.jarvisRow)
                        .foregroundStyle(.white)
                        .onSubmit { commitEdit(task) }
                    iconButton("checkmark.circle.fill", tint: .jarvisSuccess, label: "Save task") { commitEdit(task) }
                } else {
                    Text(task.text)
                        .font(.jarvisRow)
                        .foregroundStyle(Color.jarvisTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if isSuggested {
                        iconButton("checkmark", tint: .jarvisSuccess, label: "Accept task") { set(task.id, .open) }
                        iconButton("xmark", tint: .jarvisError, label: "Dismiss task") { set(task.id, .dismissed) }
                    } else {
                        iconButton("checkmark.circle", tint: .jarvisSuccess, label: "Mark done") { set(task.id, .done) }
                    }
                }
            }

            if !isSuggested, editingID != task.id {
                HStack(spacing: 8) {
                    dueMenu(task)
                    Button { beginEdit(task) } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit task")
                    Button { set(task.id, .dismissed) } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete task")
                    Spacer(minLength: 0)
                }
                .padding(.leading, 22)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: JarvisRadius.card, style: .continuous).fill(Color.jarvisSurface))
    }

    /// Due chip + preset menu. Presets beat a DatePicker in a panel this size.
    private func dueMenu(_ task: TaskRow) -> some View {
        Menu {
            Button(Calendar.current.isDateInToday(todayAt(hour: 18)) ? "Today 6 PM" : "Tomorrow 6 PM") {
                setDue(task.id, todayAt(hour: 18))
            }
            Button("Tomorrow 9 AM") { setDue(task.id, tomorrowAt(hour: 9)) }
            Button("Next week") { setDue(task.id, nextWeek()) }
            if task.dueAt != nil {
                Divider()
                Button("Clear due date") { setDue(task.id, nil) }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "calendar")
                    .font(.system(size: 9))
                if let due = task.dueAt {
                    Text(dueLabel(due))
                        .font(.jarvisFootnote)
                }
            }
            .foregroundStyle(dueColor(task.dueAt))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(dueColor(task.dueAt).opacity(task.dueAt == nil ? 0 : 0.14)))
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Due date")
    }

    private func dueLabel(_ due: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(due) { return "Today \(due.formatted(date: .omitted, time: .shortened))" }
        if cal.isDateInTomorrow(due) { return "Tomorrow" }
        return due.formatted(.dateTime.month(.abbreviated).day())
    }

    private func dueColor(_ due: Date?) -> Color {
        guard let due else { return .white.opacity(0.45) }
        return due < .now ? .jarvisError : .jarvisWarning
    }

    /// Today at `hour`, rolling to tomorrow once that hour has passed — a due
    /// preset must never produce an instantly-overdue task.
    private func todayAt(hour: Int) -> Date {
        let cal = Calendar.current
        let candidate = cal.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return candidate > .now ? candidate : (cal.date(byAdding: .day, value: 1, to: candidate) ?? candidate)
    }

    private func tomorrowAt(hour: Int) -> Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private func nextWeek() -> Date {
        Calendar.current.date(byAdding: .day, value: 7, to: todayAt(hour: 9)) ?? .now
    }

    private func iconButton(_ symbol: String, tint: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Actions

    private func beginEdit(_ task: TaskRow) {
        draft = task.text
        editingID = task.id
    }

    private func commitEdit(_ task: TaskRow) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        editingID = nil
        guard !text.isEmpty, text != task.text else { return }
        Task { await store.setTaskText(task.id, text) }
    }

    private func set(_ id: String, _ status: TaskRow.Status) {
        Task { await store.setTaskStatus(id, status) }
    }

    private func setDue(_ id: String, _ due: Date?) {
        Task { await store.setTaskDue(id, due) }
    }
}
