import AppKit
import JMemory
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
            let agent = AgentServices(database: database, supportDirectory: appSupport)
            let chat = ChatStore(core: core, sessions: sessions, agent: agent)
            let voice = VoiceController(chat: chat)
            let pushToTalk = PushToTalkMonitor(voice: voice)

            // Memory: extraction on segment close + retrieval injection.
            let memoryStore = MemoryStore(database: database)
            let memoryService = MemoryService(core: core, sessions: sessions, store: memoryStore)
            chat.memory = memoryService
            chat.graphReader = GraphReader(database: database)
            self.memoryStore = memoryStore
            self.memoryService = memoryService

            self.core = core
            self.chat = chat
            self.voice = voice
            self.pushToTalk = pushToTalk

            Task {
                await sessions.setOnSegmentClose { segmentID in
                    Task { @MainActor in await memoryService.extract(segmentID: segmentID) }
                }
            }

            // Proactivity: context-switch nudges + heartbeat + cron.
            let proactivity = ProactivityService(core: core, chat: chat, agent: agent)
            self.proactivity = proactivity
            agent.screenBuffer.onContextSwitch = { frame in
                Task { @MainActor in proactivity.onContextSwitch(frame) }
            }

            screenManager.start(core: core, chat: chat, voice: voice)
            pushToTalk.start()
            agent.screenBuffer.start() // no-op until Screen Recording is granted
            proactivity.start()
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
