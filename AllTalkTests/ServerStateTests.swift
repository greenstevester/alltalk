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
