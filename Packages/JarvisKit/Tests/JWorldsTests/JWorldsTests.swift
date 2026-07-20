import Foundation
import Testing
@testable import JWorlds

@Suite struct SnapshotDiffTests {
    @Test func diffDetectsAddedChangedRemoved() {
        let old = ["a": "1", "b": "2", "c": "3"]
        let new = ["a": "1", "b": "9", "d": "4"]
        let (added, changed, removed) = SnapshotDiff.diff(old: old, new: new)
        #expect(added == ["d"])
        #expect(changed == ["b"])
        #expect(removed == ["c"])
    }

    @Test func hashIsStableAndOrderSensitive() {
        #expect(SnapshotDiff.hash(["a", "b"]) == SnapshotDiff.hash(["a", "b"]))
        #expect(SnapshotDiff.hash(["a", "b"]) != SnapshotDiff.hash(["b", "a"]))
    }
}

@Suite struct CursorTests {
    struct C: Codable, Equatable { var lastRowid: Int64; var noted: [String] }

    @Test func roundTrips() {
        let cursor = C(lastRowid: 42, noted: ["x.com"])
        let json = WorldCursor.encode(cursor)
        #expect(WorldCursor.decode(json, as: C.self) == cursor)
        #expect(WorldCursor.decode(nil, as: C.self) == nil)
        #expect(WorldCursor.decode("not json", as: C.self) == nil)
    }
}

@Suite struct AppleEpochTests {
    @Test func epochConversions() {
        // 2001-01-01 + 1 day
        #expect(abs(AppleEpoch.date(fromSeconds: 86400).timeIntervalSince1970 - 978_393_600) < 1)
        #expect(abs(AppleEpoch.date(fromNanoseconds: 86_400_000_000_000).timeIntervalSince1970 - 978_393_600) < 1)
        // Chrome epoch: 1970-01-01 in µs-since-1601 is 11644473600e6
        #expect(abs(AppleEpoch.date(fromChromeMicroseconds: 11_644_473_600_000_000).timeIntervalSince1970) < 1)
    }
}

@Suite struct EmlxTests {
    static let simple = """
    Message-Id: <abc@example.com>
    From: Jane Doe <jane@example.com>
    Subject: Lunch on Friday
    Date: Fri, 17 Jul 2026 10:30:00 -0700
    Content-Type: text/plain

    Hey, are we still on for lunch at Tartine on Friday?
    """

    @Test func parsesSimpleMessage() {
        let raw = Self.simple.replacingOccurrences(of: "\n", with: "\r\n")
        let message = Emlx.parseRFC822(raw)
        #expect(message?.fromName == "Jane Doe")
        #expect(message?.fromEmail == "jane@example.com")
        #expect(message?.subject == "Lunch on Friday")
        #expect(message?.messageID == "<abc@example.com>")
        #expect(message?.body.contains("Tartine") == true)
        #expect(message?.isBulk == false)
        #expect(message?.date != nil)
    }

    @Test func parsesEmlxWrapper() {
        let inner = Self.simple
        let emlx = "\(inner.utf8.count)\n\(inner)<plist>ignored</plist>"
        let message = Emlx.parse(Data(emlx.utf8))
        #expect(message?.subject == "Lunch on Friday")
    }

    @Test func flagsBulkMail() {
        let bulk = """
        From: Store <deals@shop.com>
        Subject: SALE
        List-Unsubscribe: <mailto:u@shop.com>

        Big sale!
        """
        #expect(Emlx.parseRFC822(bulk)?.isBulk == true)
    }

    @Test func multipartPrefersTextPlain() {
        let multipart = """
        From: A <a@b.com>
        Content-Type: multipart/alternative; boundary="XYZ"

        --XYZ
        Content-Type: text/plain

        plain body here
        --XYZ
        Content-Type: text/html

        <p>html body</p>
        --XYZ--
        """
        #expect(Emlx.parseRFC822(multipart)?.body == "plain body here")
    }

    @Test func decodesQuotedPrintable() {
        #expect(Emlx.decodeQuotedPrintable("caf=C3=A9 =\ncontinued") == "café continued")
    }

    @Test func stripsHTML() {
        let html = "<html><style>p{color:red}</style><p>Hello &amp; welcome</p></html>"
        #expect(Emlx.stripHTML(html) == "Hello & welcome")
    }

    @Test func parsesBareAddress() {
        let (name, email) = Emlx.parseAddress("jane@example.com")
        #expect(name == nil)
        #expect(email == "jane@example.com")
    }
}

@Suite struct TypedstreamTests {
    @Test func recoversLongestPrintableRun() {
        // Simulated typedstream: class names + the actual message text.
        var data = Data()
        data.append(contentsOf: [0x04, 0x0B])
        data.append(Data("streamtyped".utf8))
        data.append(contentsOf: [0x81, 0xE8, 0x03])
        data.append(Data("NSMutableAttributedString".utf8))
        data.append(contentsOf: [0x00, 0x01])
        data.append(Data("Hey, running 10 minutes late for dinner tonight".utf8))
        data.append(contentsOf: [0x02, 0x86])
        data.append(Data("__kIMMessagePartAttributeName".utf8))

        let text = Typedstream.extractText(data)
        #expect(text == "Hey, running 10 minutes late for dinner tonight")
    }

    @Test func returnsNilForNoise() {
        let data = Data([0x00, 0x01, 0x02, 0x03])
        #expect(Typedstream.extractText(data) == nil)
    }
}

@Suite struct BrowserTests {
    @Test func countsDomainsWithStoplist() {
        var counts: [String: Int] = [:]
        BrowserWorld.count("https://www.swift.org/docs", into: &counts)
        BrowserWorld.count("https://swift.org/blog", into: &counts)
        BrowserWorld.count("https://www.google.com/search?q=x", into: &counts)
        #expect(counts["swift.org"] == 2)
        #expect(counts["google.com"] == nil)
    }
}
