import Foundation
import Testing
@testable import JLocal

@Test func localChunksSplitsLongInputOnLineBoundaries() {
    let short = "one line"
    #expect(localChunks(short) == [short])

    let long = (0..<2000).map { "line number \($0) with some words" }.joined(separator: "\n")
    let chunks = localChunks(long, maxChars: 6000)
    #expect(chunks.count > 1)
    // Reassembly loses nothing but the join newlines.
    #expect(chunks.joined().replacingOccurrences(of: "\n", with: "").count
            == long.replacingOccurrences(of: "\n", with: "").count)
    // No chunk grossly overshoots the cap (allow one line of overhang).
    for chunk in chunks { #expect(chunk.count < 6000 + 200) }
}

@Test func availabilityQueryDoesNotCrash() async {
    // On CI/hardware without Apple Intelligence this returns false; the point
    // is that querying availability is always safe and never throws.
    let model = LocalModel()
    _ = await model.isAvailable
    _ = await model.unavailableReason
}

@Test func generateThrowsUnavailableWhenModelOff() async {
    let model = LocalModel()
    guard await model.isAvailable == false else { return } // skip where AI is on
    await #expect(throws: LocalModelError.self) {
        _ = try await model.generate(NudgeGate.self, instructions: "decide", prompt: "hi")
    }
}
