import JMemory
import SwiftUI

/// Memory pane: the active-memory list (search, inline rename, forget) with a
/// toggle into the knowledge-graph explorer.
struct MemoriesPane: View {
    let store: MemoryStore
    var graphReader: GraphReader?

    private enum Mode { case list, graph }

    @State private var mode: Mode = .list
    @State private var query = ""
    @State private var items: [MemoryStore.MemoryItem]?
    @State private var editingID: String?
    @State private var draft: String = ""

    var body: some View {
        VStack(spacing: 8) {
            header

            switch mode {
            case .list: list
            case .graph:
                if let graphReader {
                    GraphView(reader: graphReader, memoryStore: store)
                } else {
                    JarvisEmptyState(symbol: "point.3.connected.trianglepath.dotted",
                                     title: "The graph isn't available")
                }
            }
        }
        .animation(.snappy, value: mode)
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .jarvisGraphDidChange)) { _ in
            Task { await reload() }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if mode == .list {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.jarvisCaption)
                        .foregroundStyle(Color.jarvisTextTertiary)
                    TextField("Search memories", text: $query)
                        .textFieldStyle(.plain)
                        .font(.jarvisCaption)
                        .foregroundStyle(Color.jarvisTextPrimary)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.jarvisCaption)
                                .foregroundStyle(Color.jarvisTextTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: JarvisRadius.control, style: .continuous).fill(Color.jarvisSurface))
            } else {
                Spacer(minLength: 0)
            }
            modeButton(.list, symbol: "list.bullet", label: "Memory list")
            modeButton(.graph, symbol: "point.3.connected.trianglepath.dotted", label: "Knowledge graph")
        }
        .padding(.horizontal, 2)
    }

    private func modeButton(_ target: Mode, symbol: String, label: String) -> some View {
        Button {
            withAnimation(.snappy) { mode = target }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(mode == target ? .white : Color.jarvisTextTertiary)
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: JarvisRadius.control - 1, style: .continuous)
                        .fill(mode == target ? Color.jarvisSurfaceActive : Color.jarvisSurface)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var list: some View {
        if let items {
            let visible = filtered(items)
            if items.isEmpty {
                JarvisEmptyState(
                    symbol: "brain",
                    title: "No memories yet",
                    message: "Jarvis remembers durable facts from your conversations automatically — or tell it \"remember that…\"."
                )
            } else if visible.isEmpty {
                JarvisEmptyState(symbol: "magnifyingglass", title: "No matches for \"\(query)\"")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(visible) { row($0) }
                    }
                    .padding(.bottom, 10)
                }
            }
        } else {
            JarvisLoadingState()
        }
    }

    private func filtered(_ items: [MemoryStore.MemoryItem]) -> [MemoryStore.MemoryItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter { $0.text.localizedCaseInsensitiveContains(q) || $0.kind.localizedCaseInsensitiveContains(q) }
    }

    private func row(_ item: MemoryStore.MemoryItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                kindBadge(item.kind)
                Spacer()
                Text(item.createdAt.formatted(.relative(presentation: .named)))
                    .font(.jarvisFootnote).monospacedDigit()
                    .foregroundStyle(Color.jarvisTextTertiary)
                Button { beginEdit(item) } label: { Image(systemName: "pencil") }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.5))
                    .accessibilityLabel("Edit memory")
                Button { forget(item) } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.5))
                    .accessibilityLabel("Forget memory")
            }
            .font(.system(size: 11))

            if editingID == item.id {
                HStack(spacing: 8) {
                    TextField("Memory", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.jarvisBody).foregroundStyle(.white)
                        .onSubmit { commitEdit(item) }
                    Button { commitEdit(item) } label: { Image(systemName: "checkmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Color.jarvisSuccess)
                        .accessibilityLabel("Save memory")
                }
            } else {
                Text(item.text)
                    .font(.jarvisBody).foregroundStyle(Color.jarvisTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: JarvisRadius.card, style: .continuous).fill(Color.jarvisSurface))
    }

    private func kindBadge(_ kind: String) -> some View {
        Text(kind.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(kindColor(kind))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(kindColor(kind).opacity(0.16)))
    }

    private func kindColor(_ kind: String) -> Color {
        switch kind {
        case "preference": .jarvisAccent
        case "event": .orange
        case "task": .jarvisWarning
        case "insight": .purple
        default: .teal // fact
        }
    }

    // MARK: - Actions

    private func reload() async { items = await store.list() }

    private func beginEdit(_ item: MemoryStore.MemoryItem) {
        draft = item.text
        editingID = item.id
    }

    private func commitEdit(_ item: MemoryStore.MemoryItem) {
        let text = draft
        editingID = nil
        Task { await store.update(id: item.id, text: text); await reload() }
    }

    private func forget(_ item: MemoryStore.MemoryItem) {
        if editingID == item.id { editingID = nil }
        Task { await store.archive(id: item.id); await reload() }
    }
}
