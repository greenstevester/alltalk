import XCTest

final class ServerDiscoveryTests: XCTestCase {

    func test_resolveBinary_prefersExecutableOverride() {
        let path = ServerDiscovery.resolveBinary(
            override: "/custom/llama-server",
            isExecutable: { $0 == "/custom/llama-server" }
        )
        XCTAssertEqual(path, "/custom/llama-server")
    }

    func test_resolveBinary_ignoresNonExecutableOverride_fallsBackToCandidate() {
        let path = ServerDiscovery.resolveBinary(
            override: "/custom/nope",
            isExecutable: { $0 == "/opt/homebrew/bin/llama-server" }
        )
        XCTAssertEqual(path, "/opt/homebrew/bin/llama-server")
    }

    func test_resolveBinary_nilWhenNothingExecutable() {
        let path = ServerDiscovery.resolveBinary(override: "", isExecutable: { _ in false })
        XCTAssertNil(path)
    }

    func test_resolveModel_successWhenBothFilesExist() {
        let result = ServerDiscovery.resolveModel(
            folder: "/models",
            fileExists: { _ in true }
        )
        switch result {
        case .success(let pair):
            XCTAssertEqual(pair.model, "/models/\(ServerDiscovery.modelFileName)")
            XCTAssertEqual(pair.mmproj, "/models/\(ServerDiscovery.mmprojFileName)")
        case .failure(let why):
            XCTFail("expected success, got \(why)")
        }
    }

    func test_resolveModel_failureListsMissingFiles() {
        let result = ServerDiscovery.resolveModel(
            folder: "/models",
            fileExists: { $0.hasSuffix(ServerDiscovery.modelFileName) } // only model present
        )
        switch result {
        case .success:
            XCTFail("expected failure")
        case .failure(let err):
            XCTAssertTrue(err.message.contains(ServerDiscovery.mmprojFileName), "should name the missing mmproj")
        }
    }

    func test_resolveModel_failureNamesBothWhenBothMissing() {
        let result = ServerDiscovery.resolveModel(folder: "/models", fileExists: { _ in false })
        switch result {
        case .success:
            XCTFail("expected failure")
        case .failure(let err):
            XCTAssertTrue(err.message.contains(ServerDiscovery.modelFileName), "should name the model")
            XCTAssertTrue(err.message.contains(ServerDiscovery.mmprojFileName), "should name the mmproj")
        }
    }

    func test_resolveModel_expandsTilde() {
        var seen: [String] = []
        _ = ServerDiscovery.resolveModel(folder: "~/models", fileExists: { seen.append($0); return true })
        XCTAssertFalse(seen.contains { $0.hasPrefix("~") }, "tilde should be expanded before checking")
    }
}
