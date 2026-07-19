import EventKit
import Foundation
import JAgent

/// Bridges to Apple apps: Calendar/Reminders via EventKit, Mail/Notes via
/// AppleScript. All mutating tools are external-effect (approval-gated); each
/// prompts for its TCC permission on first use.
enum BridgeTools {
    static func registry() -> [ToolSpec] {
        [addEvent(), listEvents(), addReminder(), listReminders(), sendMail(), createNote()]
    }

    // MARK: - Calendar

    private static func addEvent() -> ToolSpec {
        ToolSpec(
            name: "calendar_add_event",
            description: "Add an event to the default calendar. Dates are ISO8601 or 'yyyy-MM-dd HH:mm'.",
            parameters: obj([("title", "Event title"), ("start", "Start date/time"), ("end", "End (optional, defaults +1h)"), ("notes", "Notes (optional)")], required: ["title", "start"]),
            tier: .externalEffect,
            summarize: { "Add calendar event “\(str($0, "title") ?? "")”" }
        ) { input, _ in
            guard let title = str(input, "title"), let startRaw = str(input, "start"), let start = parseDate(startRaw) else {
                return ToolOutput("Missing title or unparseable start date.", isError: true)
            }
            let store = EKEventStore()
            guard (try? await store.requestFullAccessToEvents()) == true else {
                return ToolOutput("Calendar access denied — grant it in System Settings › Privacy & Security › Calendars.", isError: true)
            }
            let event = EKEvent(eventStore: store)
            event.title = title
            event.startDate = start
            event.endDate = str(input, "end").flatMap(parseDate) ?? start.addingTimeInterval(3600)
            event.notes = str(input, "notes")
            event.calendar = store.defaultCalendarForNewEvents
            do {
                try store.save(event, span: .thisEvent)
                return ToolOutput("Added “\(title)” on \(event.startDate.formatted(date: .abbreviated, time: .shortened)).")
            } catch {
                return ToolOutput("Failed to save event: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private static func listEvents() -> ToolSpec {
        ToolSpec(
            name: "calendar_list",
            description: "List upcoming calendar events for the next N days (default 7).",
            parameters: obj([("days", "Number of days ahead (optional)")], required: []),
            tier: .readOnly
        ) { input, _ in
            let store = EKEventStore()
            guard (try? await store.requestFullAccessToEvents()) == true else {
                return ToolOutput("Calendar access denied.", isError: true)
            }
            let days = int(input, "days") ?? 7
            let end = Date().addingTimeInterval(TimeInterval(days) * 86400)
            let predicate = store.predicateForEvents(withStart: Date(), end: end, calendars: nil)
            let events = store.events(matching: predicate).prefix(40)
            if events.isEmpty { return ToolOutput("No events in the next \(days) days.") }
            let lines = events.map { "\($0.startDate.formatted(date: .abbreviated, time: .shortened)) — \($0.title ?? "(untitled)")" }
            return ToolOutput(lines.joined(separator: "\n"))
        }
    }

    // MARK: - Reminders

    private static func addReminder() -> ToolSpec {
        ToolSpec(
            name: "reminders_add",
            description: "Add a reminder with an optional due date/time.",
            parameters: obj([("title", "Reminder text"), ("due", "Due date/time (optional)")], required: ["title"]),
            tier: .externalEffect,
            summarize: { "Add reminder “\(str($0, "title") ?? "")”" }
        ) { input, _ in
            guard let title = str(input, "title") else { return ToolOutput("Missing 'title'.", isError: true) }
            let store = EKEventStore()
            guard (try? await store.requestFullAccessToReminders()) == true else {
                return ToolOutput("Reminders access denied — grant it in System Settings › Privacy & Security › Reminders.", isError: true)
            }
            let reminder = EKReminder(eventStore: store)
            reminder.title = title
            reminder.calendar = store.defaultCalendarForNewReminders()
            if let due = str(input, "due").flatMap(parseDate) {
                reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            }
            do {
                try store.save(reminder, commit: true)
                return ToolOutput("Added reminder “\(title)”.")
            } catch {
                return ToolOutput("Failed to save reminder: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private static func listReminders() -> ToolSpec {
        ToolSpec(
            name: "reminders_list",
            description: "List incomplete reminders.",
            parameters: obj([], required: []),
            tier: .readOnly
        ) { _, _ in
            let store = EKEventStore()
            guard (try? await store.requestFullAccessToReminders()) == true else {
                return ToolOutput("Reminders access denied.", isError: true)
            }
            let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            // Map to Sendable strings inside the completion to avoid sending EKReminder.
            let titles: [String] = await withCheckedContinuation { cont in
                store.fetchReminders(matching: predicate) { reminders in
                    cont.resume(returning: (reminders ?? []).prefix(40).map { $0.title ?? "(untitled)" })
                }
            }
            if titles.isEmpty { return ToolOutput("No incomplete reminders.") }
            return ToolOutput(titles.map { "• \($0)" }.joined(separator: "\n"))
        }
    }

    // MARK: - Mail / Notes (AppleScript)

    private static func sendMail() -> ToolSpec {
        ToolSpec(
            name: "mail_send",
            description: "Send an email via Mail.app.",
            parameters: obj([("to", "Recipient email"), ("subject", "Subject"), ("body", "Message body")], required: ["to", "subject", "body"]),
            tier: .externalEffect,
            summarize: { "Send email to \(str($0, "to") ?? "") — “\(str($0, "subject") ?? "")”" }
        ) { input, _ in
            guard let to = str(input, "to"), let subject = str(input, "subject"), let body = str(input, "body") else {
                return ToolOutput("Missing 'to', 'subject', or 'body'.", isError: true)
            }
            let script = """
            tell application "Mail"
                set newMessage to make new outgoing message with properties {subject:"\(escape(subject))", content:"\(escape(body))", visible:false}
                tell newMessage to make new to recipient at end of to recipients with properties {address:"\(escape(to))"}
                send newMessage
            end tell
            """
            return await runAppleScript(script, success: "Sent email to \(to).")
        }
    }

    private static func createNote() -> ToolSpec {
        ToolSpec(
            name: "notes_create",
            description: "Create a note in Notes.app.",
            parameters: obj([("title", "Note title (optional)"), ("body", "Note body")], required: ["body"]),
            tier: .externalEffect,
            summarize: { "Create note “\(str($0, "title") ?? (str($0, "body") ?? "").prefix(30).description)”" }
        ) { input, _ in
            guard let body = str(input, "body") else { return ToolOutput("Missing 'body'.", isError: true) }
            let title = str(input, "title") ?? ""
            let html = title.isEmpty ? escape(body) : "<div><b>\(escape(title))</b></div>\(escape(body))"
            let script = """
            tell application "Notes" to make new note at folder "Notes" with properties {body:"\(html)"}
            """
            return await runAppleScript(script, success: "Created note.")
        }
    }

    // MARK: - Helpers

    private static func runAppleScript(_ source: String, success: String) async -> ToolOutput {
        await MainActor.run {
            var error: NSDictionary?
            let script = NSAppleScript(source: source)
            _ = script?.executeAndReturnError(&error)
            if let error, let message = error["NSAppleScriptErrorMessage"] as? String {
                return ToolOutput("AppleScript failed: \(message) (you may need to allow Automation in System Settings › Privacy & Security › Automation).", isError: true)
            }
            return ToolOutput(success)
        }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func parseDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = format
            if let d = df.date(from: s) { return d }
        }
        return nil
    }
}
