import JMemory
import SwiftUI

/// Active-memory list with a kind badge, relative age, inline rename, and forget
/// (archive). Shown in the Activity view; matches the DecisionsPane card style.
struct MemoriesPane: View {
    let store: MemoryStore

    @State private var items: [MemoryStore.MemoryItem] = []
    @State private var editingID: String?
    @State private var draft: String = ""

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(items) { row($0) }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        .animation(.snappy, value: items.count)
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .jarvisGraphDidChange)) { _ in
            Task { await reload() }
        }
    }

    private func row(_ item: MemoryStore.MemoryItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                kindBadge(item.kind)
                Spacer()
                Text(item.createdAt.formatted(.relative(presentation: .named)))
                    .font(.jarvisFootnote).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.45))
                Button { beginEdit(item) } label: { Image(systemName: "pencil") }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.5))
                Button { forget(item) } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.5))
            }
            .font(.system(size: 11))

            if editingID == item.id {
                HStack(spacing: 8) {
                    TextField("", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.jarvisBody).foregroundStyle(.white)
                        .onSubmit { commitEdit(item) }
                    Button { commitEdit(item) } label: { Image(systemName: "checkmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Color.jarvisSuccess)
                }
            } else {
                Text(item.text)
                    .font(.jarvisBody).foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.jarvisSurface))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "brain")
                .font(.system(size: 22, weight: .light)).foregroundStyle(.white.opacity(0.55))
            Text("Things Jarvis remembers about you will appear here")
                .font(.jarvisCaption).foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
