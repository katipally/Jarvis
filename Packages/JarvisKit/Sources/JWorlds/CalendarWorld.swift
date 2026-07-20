import EventKit
import Foundation
import JKnowledge

/// Calendar → deterministic graph (no LLM): events become event entities,
/// attendees become people, `attends`/`located_in` edges carry the times.
/// Cursor = fingerprint map over a −7d..+60d window (EventKit has no
/// changelog). Removed/changed events are additive-only v1 — the graph keeps
/// the old edge (it has valid_to anyway).
public struct CalendarWorld: WorldConnector {
    public let worldId = "calendar"

    public init() {}

    struct Cursor: Codable {
        var fingerprints: [String: String] = [:]
    }

    public func sync(cursorJson: String?) async throws -> WorldSyncResult {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw WorldError.accessDenied("Calendar")
        }
        let store = EKEventStore()
        let start = Date().addingTimeInterval(-7 * 86400)
        let end = Date().addingTimeInterval(60 * 86400)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)

        let old = WorldCursor.decode(cursorJson, as: Cursor.self) ?? Cursor()
        var fresh: [String: String] = [:]
        var byID: [String: EKEvent] = [:]
        for event in events {
            guard let id = event.eventIdentifier, let title = event.title,
                  !title.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let attendees = (event.attendees ?? []).compactMap(\.name).sorted().joined(separator: ",")
            fresh[id] = SnapshotDiff.hash([title, "\(event.startDate.timeIntervalSince1970)",
                                           "\(event.endDate.timeIntervalSince1970)",
                                           event.location ?? "", attendees])
            byID[id] = event
        }

        let (added, changed, _) = SnapshotDiff.diff(old: old.fingerprints, new: fresh)
        var result = WorldSyncResult(cursorJson: WorldCursor.encode(Cursor(fingerprints: fresh)))
        for id in added + changed {
            guard let event = byID[id] else { continue }
            result.ops.entities.append(EntityOp(name: event.title, type: .event))
            result.ops.edges.append(EdgeOp(subject: "Me", subjectType: .person, rel: "attends",
                                           object: event.title, objectType: .event,
                                           validFrom: event.startDate, validTo: event.endDate))
            for attendee in event.attendees ?? [] {
                guard let name = attendee.name, !name.isEmpty,
                      attendee.participantType == .person, !attendee.isCurrentUser else { continue }
                result.ops.entities.append(EntityOp(name: name, type: .person))
                result.ops.edges.append(EdgeOp(subject: name, subjectType: .person, rel: "attends",
                                               object: event.title, objectType: .event,
                                               validFrom: event.startDate, validTo: event.endDate))
            }
            if let location = event.location, !location.trimmingCharacters(in: .whitespaces).isEmpty {
                // First line only — full addresses make terrible entity names.
                let place = String(location.split(separator: "\n").first ?? "")
                if place.count < 60 {
                    result.ops.edges.append(EdgeOp(subject: event.title, subjectType: .event, rel: "located_in",
                                                   object: place, objectType: .place))
                }
            }
        }
        return result
    }
}
