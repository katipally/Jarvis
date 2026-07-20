import AppKit
import JKnowledge
import JLocal
import JScreen
import JStore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let screenManager = NotchScreenManager()
    private var statusItem: NSStatusItem?
    private(set) var core: JarvisCore?
    private var chat: ChatStore?
    private var voice: VoiceController?
    private var pushToTalk: PushToTalkMonitor?
    private var knowledgeStore: KnowledgeStore?
    private var knowledge: KnowledgeService?
    private var worldSync: WorldSyncEngine?
    private var awareness: Awareness?
    private var notifications: NotificationService?
    private var sessions: SessionManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Jarvis", isDirectory: true)
        let cacheDir = appSupport.appendingPathComponent("cache", isDirectory: true)

        do {
            // Insurance for the destructive v12 fresh-start migration: keep a
            // one-time file copy of the pre-v12 database next to the live one.
            let dbURL = appSupport.appendingPathComponent("jarvis.sqlite")
            let backupURL = appSupport.appendingPathComponent("jarvis-pre-v12.sqlite")
            if FileManager.default.fileExists(atPath: dbURL.path),
               !FileManager.default.fileExists(atPath: backupURL.path) {
                try? FileManager.default.copyItem(at: dbURL, to: backupURL)
            }
            let database = try JarvisDatabase.open(directory: appSupport)
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            let core = JarvisCore(database: database, cacheDirectory: cacheDir)
            let sessions = SessionManager(database: database)
            let knowledgeStore = KnowledgeStore(database: database)

            // One shared on-device model + resolver + task store, used by
            // knowledge and proactivity (local-first, API optional).
            let localFirst = LocalFirst(local: LocalModel(), core: core)
            let taskStore = TaskStore(database: database)

            // Knowledge core: episodes → debounced on-device extraction → facts
            // + typed graph; retrieval injection; segment digest on close.
            let knowledge = KnowledgeService(core: core, sessions: sessions, store: knowledgeStore,
                                             local: localFirst, tasks: taskStore, database: database)
            let agent = AgentServices(database: database, supportDirectory: appSupport,
                                      knowledgeStore: knowledgeStore, knowledge: knowledge)
            let chat = ChatStore(core: core, sessions: sessions, agent: agent)
            let voice = VoiceController(chat: chat)
            let pushToTalk = PushToTalkMonitor(voice: voice)
            chat.memory = knowledge
            chat.graphReader = GraphReader(database: database)
            chat.localFirst = localFirst
            self.knowledgeStore = knowledgeStore
            self.knowledge = knowledge

            // World connectors: incremental syncs feeding the knowledge core.
            let worldSync = WorldSyncEngine(store: knowledgeStore, knowledge: knowledge,
                                            database: database, settings: core.settings,
                                            supportDirectory: appSupport)
            chat.worlds = worldSync
            self.worldSync = worldSync

            self.core = core
            self.chat = chat
            self.voice = voice
            self.pushToTalk = pushToTalk

            // Let "Ask Jarvis" (Siri / Spotlight / Shortcuts) reach the assistant.
            JarvisIntentBridge.shared.answer = { [weak chat] question in
                await chat?.oneShotAnswer(question) ?? "Jarvis isn't ready yet."
            }

            self.sessions = sessions
            core.onSessionGapChange = { minutes in
                Task { await sessions.setIdleGap(TimeInterval(minutes * 60)) }
            }
            Task {
                await sessions.setOnSegmentClose { segmentID in
                    // Segment close writes a title/summary digest; extraction
                    // runs continuously (turnCompleted) + at boot.
                    Task { @MainActor in await knowledge.digestSegment(segmentID) }
                }
                await sessions.recoverOrphanedSegments()
                await knowledge.bootSweep() // bootstrap + re-embed + resume the episode queue
                await worldSync.start() // after bootstrap so world rows exist
            }

            // The decision engine: heartbeat reflection + trigger pipeline +
            // staged delivery. Every verdict is logged.
            let notifications = NotificationService()
            notifications.onActivate = { NSApp.activate(ignoringOtherApps: true) }
            let awareness = Awareness(
                core: core, chat: chat, agent: agent,
                localFirst: localFirst, tasks: taskStore, notifications: notifications,
                knowledge: knowledge, database: database)
            self.awareness = awareness
            self.notifications = notifications
            agent.screenBuffer.onContextSwitch = { frame in
                Task { @MainActor in awareness.onContextSwitch(frame) }
            }
            worldSync.awareness = awareness

            screenManager.start(core: core, chat: chat, voice: voice)
            pushToTalk.start()
            Task {
                let policy = await ScreenCapturePolicy.load(from: core.settings)
                agent.screenBuffer.setPolicy(policy)
                agent.screenBuffer.start() // no-op until Screen Recording is granted
            }
            awareness.start()
            Task {
                let muted = ((try? await core.settings.get("proactive_muted", as: Bool.self)) ?? nil) ?? false
                if !muted { notifications.requestAuth() }
            }
            Task { await core.load() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Jarvis can't open its local store"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        setupStatusItem()
    }

    /// Close the live segment on quit WITHOUT blocking the main thread. The old
    /// code blocked on a DispatchSemaphore (up to 1s hang, and a slow write was
    /// silently dropped). Here the runloop keeps turning via `.terminateLater`
    /// while the close races a 2s cap; either way `recoverOrphanedSegments`
    /// reconciles it on next launch, so quit can never hang on a stuck write.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let sessions else { return .terminateNow }
        Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await sessions.closeCurrentSegment() }
                group.addTask { try? await Task.sleep(for: .seconds(2)) }
                await group.next()   // whichever finishes first wins
                group.cancelAll()
            }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        screenManager.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "sparkles",
            accessibilityDescription: "Jarvis"
        )

        let menu = NSMenu()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let versionItem = NSMenuItem(title: "Jarvis \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Jarvis", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu

        statusItem = item
    }
}
