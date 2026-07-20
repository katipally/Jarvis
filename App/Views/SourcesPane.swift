import JStore
import SwiftUI

/// Data sources: per-world enable toggles, sync status, and the Full Disk
/// Access call-to-action for the sources that need it. Lives in Activity →
/// Sources (the consciousness feed's control surface).
struct SourcesPane: View {
    let knowledge: KnowledgeService
    let engine: WorldSyncEngine

    @State private var worlds: [WorldRow] = []
    @State private var fdaGranted = FullDiskAccess.granted

    /// Sources the user can toggle (chat/meetings are always-on internals).
    private static let toggleable = ["calendar", "contacts", "mail", "imessage", "notes", "browser", "screen"]
    private static let fdaWorlds: Set<String> = ["mail", "imessage", "notes", "browser"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !fdaGranted {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(Color.jarvisWarning)
                    Text("Mail, iMessage, Notes and browsing need Full Disk Access.")
                        .font(.jarvisCaption).foregroundStyle(Color.jarvisTextSecondary)
                    Spacer()
                    Button("Open System Settings") { FullDiskAccess.openSettings() }
                        .buttonStyle(.plain).font(.jarvisCaption)
                        .foregroundStyle(Color.jarvisAccent)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: JarvisRadius.control, style: .continuous)
                    .fill(Color.jarvisSurface))
            }

            ForEach(rows) { world in
                sourceRow(world)
            }
        }
        .padding(.horizontal, 16)
        .task { await reload() }
    }

    private var rows: [WorldRow] {
        Self.toggleable.compactMap { id in worlds.first { $0.id == id } }
    }

    private func sourceRow(_ world: WorldRow) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(world.displayName)
                    .font(.jarvisBody).foregroundStyle(Color.jarvisTextPrimary)
                Text(statusLine(world))
                    .font(.jarvisFootnote).foregroundStyle(
                        world.lastStatus == "error" ? Color.jarvisWarning : Color.jarvisTextTertiary)
            }
            Spacer()
            if world.enabled {
                Button("Sync now") {
                    engine.syncNow(world.id)
                    Task { try? await Task.sleep(for: .seconds(2)); await reload() }
                }
                .buttonStyle(.plain).font(.jarvisFootnote)
                .foregroundStyle(Color.jarvisAccent)
            }
            Toggle("", isOn: Binding(
                get: { world.enabled },
                set: { on in
                    Task {
                        await engine.setEnabled(world.id, on)
                        await reload()
                    }
                }
            ))
            .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            .disabled(Self.fdaWorlds.contains(world.id) && !fdaGranted && !world.enabled)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: JarvisRadius.card, style: .continuous).fill(Color.jarvisSurface))
    }

    private func statusLine(_ world: WorldRow) -> String {
        if let error = world.lastError, world.lastStatus == "error" { return error }
        guard world.enabled else { return "Off" }
        guard let last = world.lastSyncAt else { return "Waiting for first sync" }
        return "Synced \(last.formatted(.relative(presentation: .named)))"
    }

    private func reload() async {
        fdaGranted = FullDiskAccess.granted
        worlds = await knowledge.store.worlds()
    }
}
