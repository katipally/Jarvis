import AppKit
import JLocal
import JMemory
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
    private var memoryStore: MemoryStore?
    private var memoryService: MemoryService?
    private var proactivity: ProactivityService?
    private var notifications: NotificationService?
    private var meetings: MeetingService?
    private var sessions: SessionManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Jarvis", isDirectory: true)
        let cacheDir = appSupport.appendingPathComponent("cache", isDirectory: true)

        do {
            let database = try JarvisDatabase.open(directory: appSupport)
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            let core = JarvisCore(database: database, cacheDirectory: cacheDir)
            let sessions = SessionManager(database: database)
            let memoryStore = MemoryStore(database: database)

            // One shared on-device model + resolver + task store, used by memory,
            // proactivity, and meetings (decision D3: local-first, API optional).
            let localFirst = LocalFirst(local: LocalModel(), core: core)
            let taskStore = TaskStore(database: database)

            // Memory: debounced extraction (turn-driven + boot sweep), segment
            // digest on close, retrieval injection. Extraction runs on-device.
            // Built before AgentServices so the `remember` tool grows the
            // knowledge graph too, not just the plain memory rows.
            let memoryService = MemoryService(core: core, sessions: sessions, store: memoryStore,
                                              local: localFirst, tasks: taskStore, database: database)
            let agent = AgentServices(database: database, supportDirectory: appSupport,
                                      memoryStore: memoryStore, memoryService: memoryService)
            let chat = ChatStore(core: core, sessions: sessions, agent: agent)
            let voice = VoiceController(chat: chat)
            let pushToTalk = PushToTalkMonitor(voice: voice)
            chat.memory = memoryService
            chat.graphReader = GraphReader(database: database)
            self.memoryStore = memoryStore
            self.memoryService = memoryService

            self.core = core
            self.chat = chat
            self.voice = voice
            self.pushToTalk = pushToTalk

            self.sessions = sessions
            core.onSessionGapChange = { minutes in
                Task { await sessions.setIdleGap(TimeInterval(minutes * 60)) }
            }
            Task {
                await sessions.setOnSegmentClose { segmentID in
                    // Segment close writes a title/summary digest; durable-memory
                    // extraction runs continuously (turnCompleted) + at boot.
                    Task { @MainActor in await memoryService.digestSegment(segmentID) }
                }
                await sessions.recoverOrphanedSegments()
                await memoryService.bootSweep() // re-embed missing vectors + resume pending extraction
            }

            // Proactivity v2: real notifications + tasks + commitments + briefs.
            let notifications = NotificationService()
            notifications.onActivate = { NSApp.activate(ignoringOtherApps: true) }
            let proactivity = ProactivityService(
                core: core, chat: chat, agent: agent,
                localFirst: localFirst, tasks: taskStore, notifications: notifications,
                memory: memoryService)
            self.proactivity = proactivity
            self.notifications = notifications
            agent.screenBuffer.onContextSwitch = { frame in
                Task { @MainActor in proactivity.onContextSwitch(frame) }
            }

            // Meeting transcription (opt-in): conferencing-gated capture → summary.
            let meetings = MeetingService(
                database: database, localFirst: localFirst, taskStore: taskStore,
                settings: core.settings,
                receiveProactive: { body in chat.receiveProactive(body) },
                ingestFact: { fact in
                    // Meeting key facts are model-generated, so they clear the
                    // same durability gate as extraction (explicit `remember`
                    // commands don't — a direct user instruction always wins).
                    guard MemoryValidator.isDurable(fact) else { return }
                    await memoryService.remember(fact)
                })
            self.meetings = meetings

            screenManager.start(core: core, chat: chat, voice: voice, meetings: meetings)
            pushToTalk.start()
            Task {
                let policy = await ScreenCapturePolicy.load(from: core.settings)
                agent.screenBuffer.setPolicy(policy)
                agent.screenBuffer.start() // no-op until Screen Recording is granted
            }
            proactivity.start()
            meetings.start()
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

    func applicationWillTerminate(_ notification: Notification) {
        screenManager.stop()
        // Best-effort: mark the live segment closed so history is truthful.
        // Extraction for it runs on next launch via recoverOrphanedSegments.
        if let sessions {
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached {
                await sessions.closeCurrentSegment()
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 1)
        }
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
