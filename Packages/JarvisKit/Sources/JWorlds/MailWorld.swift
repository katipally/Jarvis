import Foundation
import JKnowledge

/// Apple Mail via the local store (~/Library/Mail/V*/…/*.emlx, needs Full Disk
/// Access). Cursor = last seen file mtime; only newer files are read. Each
/// message becomes one episode (LLM extraction); sender/recipients also map
/// deterministically to person entities. Bulk mail (List-Unsubscribe /
/// Precedence: bulk) is skipped — a junk-fact firewall.
public struct MailWorld: WorldConnector {
    public let worldId = "mail"
    let mailRoot: URL

    public init(mailRoot: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mail")) {
        self.mailRoot = mailRoot
    }

    struct Cursor: Codable {
        var lastMtime: Double = 0
    }

    /// First-enable backfill caps: last 30 days, newest 500 messages.
    static let backfillDays: Double = 30
    static let maxPerSync = 500

    public func sync(cursorJson: String?) async throws -> WorldSyncResult {
        guard FileManager.default.isReadableFile(atPath: mailRoot.path),
              (try? FileManager.default.contentsOfDirectory(atPath: mailRoot.path)) != nil else {
            throw WorldError.needsFullDiskAccess
        }
        let old = WorldCursor.decode(cursorJson, as: Cursor.self)
        let since = old?.lastMtime ?? (Date().timeIntervalSince1970 - Self.backfillDays * 86400)

        // Collect emlx files newer than the cursor. Directories whose own
        // mtime predates the cursor can't contain new direct children (a
        // message add touches its parent), so whole unchanged mailboxes are
        // skipped instead of stat-ing every file in the tree each poll.
        var found: [(url: URL, mtime: Double)] = []
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey]
        let enumerator = FileManager.default.enumerator(
            at: mailRoot, includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: keys)
            let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            if values?.isDirectory == true {
                // Small slack: copies can land with slightly older dir mtimes.
                if url.lastPathComponent == "Messages", mtime < since - 60 {
                    enumerator?.skipDescendants()
                }
                continue
            }
            guard url.pathExtension == "emlx", mtime > since else { continue }
            found.append((url, mtime))
        }
        // OLDEST first: the cursor may only advance over processed files, so a
        // >500 backlog is drained across syncs instead of silently skipped.
        found.sort { $0.mtime < $1.mtime }
        let batch = found.prefix(Self.maxPerSync)

        var result = WorldSyncResult()
        var newest = old?.lastMtime ?? since
        for (url, mtime) in batch {
            newest = max(newest, mtime)
            guard let data = try? Data(contentsOf: url),
                  let message = Emlx.parse(data) else { continue }
            guard !message.isBulk else { continue }

            let sender = message.fromName ?? message.fromEmail
            var content = "Email"
            if let sender { content += " from \(sender)" }
            if let subject = message.subject { content += "\nSubject: \(subject)" }
            content += "\n\n\(message.body.prefix(4000))"
            result.episodes.append(EpisodeDraft(
                externalId: message.messageID ?? "emlx:\(url.lastPathComponent):\(Int(mtime))",
                occurredAt: message.date ?? Date(timeIntervalSince1970: mtime),
                title: message.subject, content: content
            ))
            if let name = message.fromName, name.count < 60, !name.contains("@") {
                result.ops.entities.append(EntityOp(name: name, type: .person,
                                                    aliases: message.fromEmail.map { [$0] } ?? []))
                result.ops.edges.append(EdgeOp(subject: "Me", subjectType: .person, rel: "knows",
                                               object: name, objectType: .person))
            }
        }
        result.cursorJson = WorldCursor.encode(Cursor(lastMtime: newest))
        return result
    }
}

/// Minimal emlx/RFC822 reader: enough headers to attribute a message plus a
/// plain-text body. ponytail: no full MIME tree, no RFC2047 header decode —
/// upgrade if extraction quality shows it matters.
enum Emlx {
    struct Message {
        var messageID: String?
        var subject: String?
        var fromName: String?
        var fromEmail: String?
        var date: Date?
        var body: String
        var isBulk: Bool
    }

    static func parse(_ data: Data) -> Message? {
        // emlx = "<byte count>\n" + RFC822 message + XML plist suffix.
        guard let newline = data.firstIndex(of: 0x0A),
              let count = Int(String(decoding: data[..<newline], as: UTF8.self)
                  .trimmingCharacters(in: .whitespaces)) else { return nil }
        let start = data.index(after: newline)
        let end = min(data.count, start + count)
        guard start < end else { return nil }
        let raw = String(decoding: data[start..<end], as: UTF8.self)
        return parseRFC822(raw)
    }

    static func parseRFC822(_ raw: String) -> Message? {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        guard let split = normalized.range(of: "\n\n") else { return nil }
        let headerBlock = String(normalized[..<split.lowerBound])
        let rawBody = String(normalized[split.upperBound...])

        // Unfold continuation lines, then index headers case-insensitively.
        var headers: [String: String] = [:]
        var current: (name: String, value: String)?
        for line in headerBlock.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.first == " " || line.first == "\t" {
                current?.value += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let colon = line.firstIndex(of: ":") {
                if let current { headers[current.name] = current.value }
                current = (String(line[..<colon]).lowercased(),
                           String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
            }
        }
        if let current { headers[current.name] = current.value }

        let (fromName, fromEmail) = parseAddress(headers["from"] ?? "")
        let isBulk = headers["list-unsubscribe"] != nil
            || headers["precedence"]?.lowercased().contains("bulk") == true
            || headers["precedence"]?.lowercased().contains("list") == true

        return Message(
            messageID: headers["message-id"],
            subject: headers["subject"],
            fromName: fromName, fromEmail: fromEmail,
            date: parseDate(headers["date"] ?? ""),
            body: extractBody(rawBody, contentType: headers["content-type"] ?? "",
                              transferEncoding: headers["content-transfer-encoding"] ?? ""),
            isBulk: isBulk
        )
    }

    /// "Jane Doe <jane@x.com>" → (Jane Doe, jane@x.com); bare address → (nil, addr).
    static func parseAddress(_ value: String) -> (name: String?, email: String?) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return (nil, nil) }
        if let open = trimmed.lastIndex(of: "<"), let close = trimmed.lastIndex(of: ">"), open < close {
            let email = String(trimmed[trimmed.index(after: open)..<close])
            let name = String(trimmed[..<open]).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            return (name.isEmpty ? nil : name, email)
        }
        return (nil, trimmed.contains("@") ? trimmed : nil)
    }

    static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z"] {
            formatter.dateFormat = format
            // Strip a trailing "(PST)" style comment first.
            let clean = value.replacingOccurrences(of: #"\s*\(.*\)$"#, with: "", options: .regularExpression)
            if let date = formatter.date(from: clean) { return date }
        }
        return nil
    }

    /// Best-effort plain text: multipart → first text/plain part (fallback
    /// text/html stripped); quoted-printable decoded; base64 parts skipped.
    static func extractBody(_ body: String, contentType: String, transferEncoding: String) -> String {
        let type = contentType.lowercased()
        if type.contains("multipart"), let boundary = boundary(from: contentType) {
            let parts = body.components(separatedBy: "--" + boundary)
            var htmlFallback: String?
            for part in parts {
                guard let split = part.range(of: "\n\n") else { continue }
                let partHeaders = String(part[..<split.lowerBound]).lowercased()
                let partBody = String(part[split.upperBound...])
                guard !partHeaders.contains("base64") else { continue }
                let decoded = partHeaders.contains("quoted-printable") ? decodeQuotedPrintable(partBody) : partBody
                if partHeaders.contains("text/plain") {
                    return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if partHeaders.contains("text/html"), htmlFallback == nil {
                    htmlFallback = stripHTML(decoded)
                }
            }
            return htmlFallback ?? ""
        }
        let decoded = transferEncoding.lowercased().contains("quoted-printable")
            ? decodeQuotedPrintable(body) : body
        if type.contains("text/html") { return stripHTML(decoded) }
        return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func boundary(from contentType: String) -> String? {
        guard let range = contentType.range(of: #"boundary="?([^";\s]+)"?"#,
                                            options: [.regularExpression, .caseInsensitive]) else { return nil }
        let match = String(contentType[range])
        return match
            .replacingOccurrences(of: #"boundary="?"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    static func decodeQuotedPrintable(_ s: String) -> String {
        let unfolded = s.replacingOccurrences(of: "=\n", with: "")
        var bytes: [UInt8] = []
        bytes.reserveCapacity(unfolded.utf8.count)
        let input = Array(unfolded.utf8)
        var i = 0
        while i < input.count {
            if input[i] == UInt8(ascii: "="), i + 2 < input.count,
               let byte = UInt8(String(decoding: input[(i + 1)...(i + 2)], as: UTF8.self), radix: 16) {
                bytes.append(byte)
                i += 3
            } else {
                bytes.append(input[i])
                i += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func stripHTML(_ html: String) -> String {
        html
            .replacingOccurrences(of: #"<(style|script)[^>]*>[\s\S]*?</\1>"#, with: "",
                                  options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
