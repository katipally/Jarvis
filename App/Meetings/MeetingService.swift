import AppKit
import Foundation
import JLocal
import JSpeech
import JStore
import Observation
import UserNotifications

/// Opt-in meeting transcription. Watches for a native conferencing app becoming
/// frontmost; when meetings are enabled it auto-starts on-device capture +
/// transcription, streams attributed segments to the DB and the live card, then
/// on stop summarizes the transcript (title/overview, action items → tasks, key
/// facts → memory) and delivers the summary to chat + a notification.
///
/// Isolation is the whole point: everything is gated on the `meetings_enabled`
/// setting (default false), and every failure is contained so the rest of the
/// app is never blocked. Observable state (`isActive`, `activeAppName`, `lines`)
/// drives the HomeView card and the NotchView pill.
@MainActor
@Observable
final class MeetingService {
    /// SettingsStore key (default false). Also referenced by the SettingsView toggle.
    nonisolated static let settingKey = "meetings_enabled"

    // MARK: - Observable UI state

    private(set) var isActive = false
    private(set) var activeAppName = ""
    private(set) var lines: [MeetingLine] = []

    // MARK: - Dependencies

    private let database: JarvisDatabase
    private let localFirst: LocalFirst
    private let taskStore: TaskStore
    private let settings: SettingsStore
    private let receiveProactive: @MainActor (String) -> Void
    private let ingestFact: (String) async -> Void

    // MARK: - Runtime

    private var activationObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var transcriber: MeetingTranscriber?
    private var pump: Task<Void, Never>?
    private var starting = false
    private var meeting: MeetingRow?
    private var meetingBundleID: String?
    private var transcript: [(source: MeetingAudioSource, text: String)] = []

    init(
        database: JarvisDatabase,
        localFirst: LocalFirst,
        taskStore: TaskStore,
        settings: SettingsStore,
        receiveProactive: @escaping @MainActor (String) -> Void,
        ingestFact: @escaping (String) async -> Void
    ) {
        self.database = database
        self.localFirst = localFirst
        self.taskStore = taskStore
        self.settings = settings
        self.receiveProactive = receiveProactive
        self.ingestFact = ingestFact
    }

    // MARK: - Lifecycle

    /// Begin observing app activation/termination. Cheap and always safe — it
    /// does nothing until a conferencing app appears AND meetings are enabled.
    func start() {
        let center = NSWorkspace.shared.notificationCenter
        activationObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            let name = app?.localizedName
            Task { @MainActor in self?.appActivated(bundleID: bundleID, name: name) }
        }
        terminationObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor in self?.appTerminated(bundleID: bundleID) }
        }
    }

    /// User-initiated stop (the card's Stop button).
    func stopMeeting() {
        Task { await endMeeting() }
    }

    // MARK: - App detection

    private func appActivated(bundleID: String?, name: String?) {
        guard !isActive, !starting,
              let bundleID, ConferencingApps.isConferencingApp(bundleID: bundleID) else { return }
        let appName = ConferencingApps.displayName(bundleID: bundleID, fallback: name ?? "Meeting")
        Task { await beginMeeting(bundleID: bundleID, appName: appName) }
    }

    private func appTerminated(bundleID: String?) {
        guard isActive, let bundleID, bundleID == meetingBundleID else { return }
        Task { await endMeeting() }
    }

    // MARK: - Start / stop

    private func beginMeeting(bundleID: String, appName: String) async {
        guard !starting, transcriber == nil else { return }
        starting = true
        defer { starting = false }

        let enabled = (try? await settings.get(Self.settingKey, as: Bool.self)) ?? false
        guard enabled else { return }

        let row = MeetingRow(startedAt: .now, appBundleId: bundleID)
        _ = try? await database.writer.write { db in try row.insert(db) }

        let transcriber = MeetingTranscriber()
        let events: AsyncStream<MeetingUtterance>
        do {
            events = try await transcriber.start()
        } catch {
            // Capture couldn't start (e.g. mic denied) — close out the empty row.
            await markSkipped(meetingID: row.id, endedAt: .now)
            return
        }

        self.meeting = row
        self.meetingBundleID = bundleID
        self.transcriber = transcriber
        self.transcript = []
        self.lines = []
        self.activeAppName = appName
        self.isActive = true

        pump = Task { [weak self] in
            for await utterance in events {
                await self?.appendUtterance(utterance, meetingID: row.id)
            }
        }
    }

    private func appendUtterance(_ utterance: MeetingUtterance, meetingID: String) async {
        let source: MeetingSegmentRow.Source = utterance.source == .mic ? .mic : .system
        let segment = MeetingSegmentRow(meetingId: meetingID, ts: utterance.ts, source: source, text: utterance.text)
        _ = try? await database.writer.write { db in try segment.insert(db) }

        transcript.append((utterance.source, utterance.text))
        lines.append(MeetingLine(id: segment.id, isYou: utterance.source == .mic, text: utterance.text))
        // Keep the in-memory buffer bounded; the card only shows the tail anyway.
        if lines.count > 40 { lines.removeFirst(lines.count - 40) }
    }

    private func endMeeting() async {
        guard let transcriber, let meeting else { return }
        // Claim ownership synchronously, before any await, so a second concurrent
        // call hits the guard and returns instead of double-finalizing the meeting.
        self.transcriber = nil
        self.meeting = nil
        meetingBundleID = nil
        isActive = false
        pump?.cancel()
        pump = nil

        let captured = transcript
        let appName = activeAppName
        transcript = []
        lines = []

        await transcriber.stop()
        await finalize(meeting: meeting, endedAt: .now, transcript: captured, appName: appName)
    }

    // MARK: - Finalization

    private func finalize(
        meeting: MeetingRow,
        endedAt: Date,
        transcript: [(source: MeetingAudioSource, text: String)],
        appName: String
    ) async {
        let text = transcript
            .map { "\($0.source == .mic ? "You" : "Them"): \($0.text)" }
            .joined(separator: "\n")

        guard text.count > 40 else {
            await markSkipped(meetingID: meeting.id, endedAt: endedAt)
            return
        }

        let instructions = """
        You summarize a meeting transcript. Lines prefixed "You:" are the user; \
        lines prefixed "Them:" are everyone else. Be accurate and concise; do not invent details.
        """
        let prompt = "Summarize this \(appName) meeting.\n\n\(text)"
        let summary = await localFirst.generate(MeetingSummary.self, instructions: instructions, prompt: prompt, maxTokens: 1200)

        let status: MeetingRow.SummaryStatus = summary == nil ? .skipped : .done
        _ = try? await database.writer.write { db in
            try db.execute(
                sql: "UPDATE meeting SET ended_at = ?, title = ?, overview = ?, summary_status = ? WHERE id = ?",
                arguments: [endedAt, summary?.title, summary?.overview, status.rawValue, meeting.id]
            )
        }

        guard let summary else { return }

        for item in summary.actionItems where !item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await taskStore.addTask(text: item, source: .meeting, sourceID: meeting.id)
        }
        for fact in summary.keyFacts where !fact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await ingestFact(fact)
        }

        let headline = summary.title.isEmpty ? "Meeting summary" : summary.title
        var body = "📝 \(headline)\n\(summary.overview)"
        if !summary.actionItems.isEmpty {
            body += "\n\nAction items:\n" + summary.actionItems.map { "• \($0)" }.joined(separator: "\n")
        }
        receiveProactive(body)
        Self.postNotification(title: headline, body: summary.overview)
    }

    private func markSkipped(meetingID: String, endedAt: Date) async {
        _ = try? await database.writer.write { db in
            try db.execute(
                sql: "UPDATE meeting SET ended_at = ?, summary_status = ? WHERE id = ?",
                arguments: [endedAt, MeetingRow.SummaryStatus.skipped.rawValue, meetingID]
            )
        }
    }

    /// Best-effort local notification. `nonisolated` + a `@Sendable` completion
    /// keeps the UserNotifications callback (a private queue) off the main actor,
    /// avoiding the SIGTRAP that a @MainActor closure on a private queue triggers.
    private nonisolated static func postNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { @Sendable granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }
    }
}
