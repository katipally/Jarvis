import Contacts
import EventKit
import Foundation
import JKnowledge
import JMind
import JStore
import JWorlds

/// Schedules and runs world syncs: per-world timers + change notifications feed
/// a SERIAL queue (one sync at a time — GRDB has a single writer and the
/// extraction queue downstream is the real bottleneck anyway). Every sync is
/// bookkept as an ingest_run row for the Activity feed.
@MainActor
final class WorldSyncEngine {
    private let store: KnowledgeStore
    private weak var knowledge: KnowledgeService?
    /// Decision engine — new episodes from a sync become triggers there.
    weak var mind: ConsciousnessService?
    private let database: JarvisDatabase
    private let settings: SettingsStore
    private let scratch: URL

    struct Source {
        let kind: String // llm_text | structured
        let name: String
        let cadence: TimeInterval
        let needsFDA: Bool
        let make: @MainActor () -> WorldConnector
    }

    private var sources: [String: Source] = [:]
    private var timers: [String: Task<Void, Never>] = [:]
    private var queue: [String] = []
    private var pumping = false
    private var observers: [NSObjectProtocol] = []

    init(store: KnowledgeStore, knowledge: KnowledgeService, database: JarvisDatabase,
         settings: SettingsStore, supportDirectory: URL) {
        self.store = store
        self.knowledge = knowledge
        self.database = database
        self.settings = settings
        self.scratch = supportDirectory.appendingPathComponent("scratch", isDirectory: true)

        let scratch = self.scratch
        sources = [
            "calendar": Source(kind: "structured", name: "Calendar", cadence: 900, needsFDA: false) { CalendarWorld() },
            "contacts": Source(kind: "structured", name: "Contacts", cadence: 86400, needsFDA: false) { ContactsWorld() },
            "mail": Source(kind: "llm_text", name: "Mail", cadence: 300, needsFDA: true) { MailWorld() },
            "imessage": Source(kind: "llm_text", name: "iMessage", cadence: 300, needsFDA: true) {
                IMessageWorld(scratchDirectory: scratch)
            },
            "notes": Source(kind: "llm_text", name: "Notes", cadence: 900, needsFDA: true) {
                NotesWorld(scratchDirectory: scratch)
            },
            "browser": Source(kind: "llm_text", name: "Browsing", cadence: 1800, needsFDA: true) {
                BrowserWorld(scratchDirectory: scratch)
            },
            "screen": Source(kind: "llm_text", name: "Screen", cadence: 1800, needsFDA: false) {
                ScreenWorld(database: database)
            },
        ]
        // NOTE: the FolderWorld connector (watch md/txt folders → episodes) is
        // built and tested in JWorlds, but intentionally NOT registered here yet
        // — it needs a real folder-picker UI + settings-backed path list before
        // it's a user feature. Wire it when that UI ships, rather than leaving a
        // dead placeholder that watches nothing.
    }

    func start() async {
        for (id, source) in sources where id != "screen" {
            // screen/chat/meetings were registered by the bootstrap
            await store.ensureWorld(id: id, kind: source.kind, displayName: source.name, enabled: false)
        }
        await restartTimers()

        // Change-driven syncs on top of the timers.
        let ekObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.enqueue("calendar") }
        }
        let cnObserver = NotificationCenter.default.addObserver(
            forName: .CNContactStoreDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.enqueue("contacts") }
        }
        observers = [ekObserver, cnObserver]
    }

    private func restartTimers() async {
        for task in timers.values { task.cancel() }
        timers = [:]
        for world in await store.worlds() where world.enabled {
            guard let source = sources[world.id] else { continue }
            let id = world.id
            timers[id] = Task { [weak self] in
                while !Task.isCancelled {
                    self?.enqueue(id)
                    try? await Task.sleep(for: .seconds(source.cadence))
                }
            }
        }
    }

    /// Enable/disable a world. Enabling requests the needed system access
    /// (TCC prompt for Calendar/Contacts) and kicks an immediate sync.
    func setEnabled(_ id: String, _ enabled: Bool) async {
        if enabled {
            switch id {
            case "calendar":
                _ = try? await EKEventStore().requestFullAccessToEvents()
            case "contacts":
                _ = try? await CNContactStore().requestAccess(for: .contacts)
            default: break
            }
        }
        await store.setWorldEnabled(id: id, enabled: enabled)
        await restartTimers()
        if enabled { enqueue(id) }
    }

    func syncNow(_ id: String) { enqueue(id) }

    // MARK: - Serial queue

    private func enqueue(_ id: String) {
        guard !queue.contains(id) else { return }
        queue.append(id)
        pump()
    }

    private func pump() {
        guard !pumping, !queue.isEmpty else { return }
        pumping = true
        let id = queue.removeFirst()
        Task {
            await sync(id)
            pumping = false
            pump()
        }
    }

    private func sync(_ id: String) async {
        guard let source = sources[id],
              let world = await store.world(id: id), world.enabled else { return }

        let runID = await store.beginIngestRun(worldId: id)
        do {
            let connector: WorldConnector
            if id == "folders" {
                let paths = ((try? await settings.get("watched_folders", as: [String].self)) ?? nil) ?? []
                connector = FolderWorld(paths: paths)
            } else {
                connector = source.make()
            }
            let result = try await connector.sync(cursorJson: world.cursorJson)

            var episodesAdded = 0
            var titles: [String] = []
            for draft in result.episodes {
                // A real write failure throws out to the catch below — the
                // cursor must NOT advance past a batch that didn't land.
                if try await store.addEpisode(worldId: id, externalId: draft.externalId,
                                              occurredAt: draft.occurredAt, title: draft.title,
                                              content: draft.content) != nil {
                    episodesAdded += 1
                    if let title = draft.title { titles.append(title) }
                }
            }
            let counts = await store.applyStructured(result.ops, worldId: id)

            let empty = episodesAdded == 0 && counts.entities == 0 && counts.edges == 0
            await store.updateWorldSync(id: id, cursorJson: result.cursorJson,
                                        status: empty ? "empty" : "done")
            await store.endIngestRun(id: runID, status: empty ? "empty" : "done",
                                     episodes: episodesAdded, counts: counts)
            if episodesAdded > 0 {
                // New text episodes → kick the extraction queue + the decision
                // engine (redacted summary only; triage never sees raw bodies).
                Task { await knowledge?.drainPendingEpisodes() }
                mind?.post(Trigger(
                    source: id, dedupeKey: "sync:\(id):\(runID)",
                    gateSummary: "\(episodesAdded) new item(s) from \(source.name)"
                        + (titles.isEmpty ? "" : ": " + titles.prefix(3).joined(separator: "; ")),
                    content: titles.joined(separator: "\n")
                ))
            }
        } catch {
            await store.updateWorldSync(id: id, cursorJson: nil, status: "error",
                                        error: error.localizedDescription)
            await store.endIngestRun(id: runID, status: "error", episodes: 0,
                                     counts: IngestCounts(), error: error.localizedDescription)
        }
    }
}
