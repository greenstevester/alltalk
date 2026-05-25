import XCTest
// No import needed: ServerState.swift is compiled into this bundle directly (Task 1).

final class ServerStateTests: XCTestCase {
    func test_menuLabel_perCase() {
        XCTAssertEqual(ServerState.stopped.menuLabel, "○ Model: Stopped")
        XCTAssertEqual(ServerState.starting.menuLabel, "◐ Model: Starting…")
        XCTAssertEqual(ServerState.ready.menuLabel, "● Model: Ready")
        XCTAssertEqual(ServerState.error("boom").menuLabel, "⚠ Model: boom")
    }

    func test_isActive_trueOnlyWhenStartingOrReady() {
        XCTAssertTrue(ServerState.starting.isActive)
        XCTAssertTrue(ServerState.ready.isActive)
        XCTAssertFalse(ServerState.stopped.isActive)
        XCTAssertFalse(ServerState.error("x").isActive)
    }

    func test_equatable() {
        XCTAssertEqual(ServerState.error("a"), ServerState.error("a"))
        XCTAssertNotEqual(ServerState.error("a"), ServerState.error("b"))
    }
}

final class TranscriptStreamingTests: XCTestCase {
    func test_drainsCompleteWords_leavingTrailingPartial() {
        var buf = "the quick brown"
        XCTAssertEqual(TranscriptStreaming.drainCompleteWords(from: &buf), ["the ", "quick "])
        XCTAssertEqual(buf, "brown")
    }

    func test_noCompleteWord_keepsBuffer() {
        var buf = "hello"
        XCTAssertTrue(TranscriptStreaming.drainCompleteWords(from: &buf).isEmpty)
        XCTAssertEqual(buf, "hello")
    }

    func test_trailingSpace_drainsAll() {
        var buf = "done "
        XCTAssertEqual(TranscriptStreaming.drainCompleteWords(from: &buf), ["done "])
        XCTAssertEqual(buf, "")
    }

    func test_accumulatesAcrossStreamingChunks() {
        var buf = ""
        var pasted: [String] = []
        for chunk in ["he", "llo ", "wor", "ld "] {
            buf += chunk
            pasted += TranscriptStreaming.drainCompleteWords(from: &buf)
        }
        XCTAssertEqual(pasted, ["hello ", "world "])
        XCTAssertEqual(buf, "")
    }

    func test_newlineIsWhitespace() {
        var buf = "line1\nline2"
        XCTAssertEqual(TranscriptStreaming.drainCompleteWords(from: &buf), ["line1\n"])
        XCTAssertEqual(buf, "line2")
    }
}
