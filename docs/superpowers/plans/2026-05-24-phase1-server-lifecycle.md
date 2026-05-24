# Phase 1 — App-managed `llama-server` lifecycle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make AllTalk start the local `llama-server` itself (lazy, on first dictation), show its status in the menu with a Stop/Start toggle, and tear down only the server it started when you quit.

**Architecture:** A new `@MainActor` `LlamaServerManager` owns the server as a child `Process`, publishes a `ServerState`, polls `/health`, adopts an already-running server (without later killing it), and persists its PID for crash-orphan cleanup. Pure logic (state labels, binary/model discovery) is split into AppKit-free files so it is unit-testable. `AllTalkController` triggers the manager at record-start and waits for `ready` before transcribing; `AppDelegate` renders status + a toggle in the menu and tears down on quit.

**Tech Stack:** Swift 5 / AppKit / SwiftUI / Foundation `Process` + `URLSession`; XCTest for the pure-logic unit tests. Spec: `docs/superpowers/specs/2026-05-24-phase1-server-lifecycle-design.md`.

> **Commit convention:** every commit in this plan should end its message with the trailer
> `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` (omitted from the example commands below for brevity).

---

## File structure

**New (app target — AppKit-free pure logic, also compiled into the test target):**
- `AllTalk/ServerState.swift` — `enum ServerState` + menu label / active helpers.
- `AllTalk/ServerDiscovery.swift` — pure functions to resolve the `llama-server` binary and model files (dependency-injected filesystem checks).

**New (app target — AppKit/Foundation):**
- `AllTalk/LlamaServerManager.swift` — process lifecycle, health polling, PID file, adoption, teardown.

**New (test target):**
- `AllTalkTests/ServerStateTests.swift`
- `AllTalkTests/ServerDiscoveryTests.swift`

**Modified:**
- `AllTalk/AllTalkController.swift` — own a `LlamaServerManager`; `ensureRunning()` at record-start; `waitUntilReady()` before `runCLI`; expose server status + toggle for the menu.
- `AllTalk/AppDelegate.swift` — menu status line + Stop/Start toggle; `applicationWillTerminate` teardown.
- `AllTalk/SettingsView.swift` — add `llamaServerPath` + `modelFolder` fields.
- `AllTalk.xcodeproj/project.pbxproj` — add the `AllTalkTests` unit-test target + new file references.
- `AllTalk.xcodeproj/xcshareddata/xcschemes/AllTalk.xcscheme` — register the test bundle in `<Testables>`.

---

## Task 1: Add the `AllTalkTests` unit-test target

The project's `project.pbxproj` is hand-written. We add a host-less unit-test bundle that compiles the two pure-logic files **directly** (no `TEST_HOST`, no `@testable import`), so tests run without launching the app.

**Files:**
- Create: `AllTalk/ServerState.swift` (empty stub for now)
- Create: `AllTalk/ServerDiscovery.swift` (empty stub for now)
- Create: `AllTalkTests/ServerStateTests.swift` (smoke test)
- Modify: `AllTalk.xcodeproj/project.pbxproj`
- Modify: `AllTalk.xcodeproj/xcshareddata/xcschemes/AllTalk.xcscheme`

- [ ] **Step 1: Create the stub source files**

`AllTalk/ServerState.swift`:
```swift
import Foundation
// Implemented in Task 2.
```

`AllTalk/ServerDiscovery.swift`:
```swift
import Foundation
// Implemented in Task 3.
```

`AllTalkTests/ServerStateTests.swift`:
```swift
import XCTest

final class ServerStateTests: XCTestCase {
    func test_harness_runs() {
        XCTAssertTrue(true)
    }
}
```

`AllTalkTests/ServerDiscoveryTests.swift` (stub now; filled in Task 3 — created here so the
Task-1 pbxproj reference resolves and the bundle builds):
```swift
import XCTest

final class ServerDiscoveryTests: XCTestCase {}
```

> The test bundle compiles `ServerState.swift` and `ServerDiscovery.swift` **directly**
> (no `TEST_HOST`, no `@testable import`). If `xcodebuild test` ever complains that the
> bundle needs a host, set `TEST_HOST`/`BUNDLE_LOADER` to the app product and add
> `@testable import AllTalk` to the test files — but the host-less path is preferred here.

- [ ] **Step 2: Add the two logic files to the app target**

In `project.pbxproj`, add to the **PBXFileReference** section:
```
		AA02000011 /* ServerState.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ServerState.swift; sourceTree = "<group>"; };
		AA02000012 /* ServerDiscovery.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ServerDiscovery.swift; sourceTree = "<group>"; };
```
Add to **PBXBuildFile** (app target compiles them):
```
		AA01000011 /* ServerState.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA02000011 /* ServerState.swift */; };
		AA01000012 /* ServerDiscovery.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA02000012 /* ServerDiscovery.swift */; };
```
Add the two file refs to the `AllTalk` PBXGroup (`AA04000002`) children list, and add the two build files to the app's PBXSourcesBuildPhase (`AA06000001`) `files` list.

- [ ] **Step 3: Add the test target objects**

Add to **PBXBuildFile**:
```
		BB01000001 /* ServerStateTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB02000001 /* ServerStateTests.swift */; };
		BB01000002 /* ServerDiscoveryTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB02000002 /* ServerDiscoveryTests.swift */; };
		BB01000003 /* ServerState.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA02000011 /* ServerState.swift */; };
		BB01000004 /* ServerDiscovery.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA02000012 /* ServerDiscovery.swift */; };
```
Add to **PBXFileReference**:
```
		BB02000001 /* ServerStateTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ServerStateTests.swift; sourceTree = "<group>"; };
		BB02000002 /* ServerDiscoveryTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ServerDiscoveryTests.swift; sourceTree = "<group>"; };
		BB02000010 /* AllTalkTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = AllTalkTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
```
Add a **PBXGroup** for the test sources and add it to the main group (`AA04000001`) children, and add the `.xctest` to the Products group (`AA04000003`) children:
```
		BB04000001 /* AllTalkTests */ = {
			isa = PBXGroup;
			children = (
				BB02000001 /* ServerStateTests.swift */,
				BB02000002 /* ServerDiscoveryTests.swift */,
			);
			path = AllTalkTests;
			sourceTree = "<group>";
		};
```
Add the **PBXSourcesBuildPhase**, **PBXNativeTarget**, **XCConfigurationList**, and two **XCBuildConfiguration** objects:
```
		BB06000001 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				BB01000001 /* ServerStateTests.swift in Sources */,
				BB01000002 /* ServerDiscoveryTests.swift in Sources */,
				BB01000003 /* ServerState.swift in Sources */,
				BB01000004 /* ServerDiscovery.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		BB05000001 /* AllTalkTests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = BB08000001 /* Build configuration list for PBXNativeTarget "AllTalkTests" */;
			buildPhases = (
				BB06000001 /* Sources */,
			);
			buildRules = ();
			dependencies = ();
			name = AllTalkTests;
			productName = AllTalkTests;
			productReference = BB02000010 /* AllTalkTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		};
		BB10000001 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				MACOSX_DEPLOYMENT_TARGET = 13.0;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.greenstevester.alltalk.tests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = macosx;
				SWIFT_EMIT_LOC_STRINGS = NO;
				SWIFT_VERSION = 5.0;
			};
			name = Debug;
		};
		BB10000002 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				MACOSX_DEPLOYMENT_TARGET = 13.0;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.greenstevester.alltalk.tests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = macosx;
				SWIFT_EMIT_LOC_STRINGS = NO;
				SWIFT_VERSION = 5.0;
			};
			name = Release;
		};
		BB08000001 /* Build configuration list for PBXNativeTarget "AllTalkTests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				BB10000001 /* Debug */,
				BB10000002 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
```
Finally, add `BB05000001 /* AllTalkTests */` to the **PBXProject** `targets` list (`AA09000001`).

- [ ] **Step 4: Register the test bundle in the scheme**

In `AllTalk.xcscheme`, replace the empty `<Testables></Testables>` inside `<TestAction>` with:
```xml
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "BB05000001"
               BuildableName = "AllTalkTests.xctest"
               BlueprintName = "AllTalkTests"
               ReferencedContainer = "container:AllTalk.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
```

- [ ] **Step 5: Verify the app still builds and tests run**

Run:
```bash
cd /Users/stevengreensill/dev/git-repos/github/ai/alltalk
xcodebuild -project AllTalk.xcodeproj -scheme AllTalk -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
xcodebuild -project AllTalk.xcodeproj -scheme AllTalk -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "Test Suite.*passed|Test Suite.*failed|** TEST"
```
Expected: `** BUILD SUCCEEDED **`, and the test run reports `Test Suite 'ServerStateTests' passed` (1 test).

- [ ] **Step 6: Commit**
```bash
git add AllTalk/ServerState.swift AllTalk/ServerDiscovery.swift AllTalkTests/ServerStateTests.swift AllTalk.xcodeproj
git commit -m "test: add AllTalkTests unit-test target (host-less logic bundle)"
```

---

## Task 2: `ServerState` (TDD)

**Files:**
- Test: `AllTalkTests/ServerStateTests.swift`
- Implement: `AllTalk/ServerState.swift`

- [ ] **Step 1: Write the failing tests**

Replace `AllTalkTests/ServerStateTests.swift` with:
```swift
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
```

- [ ] **Step 2: Run tests, verify they fail**

Run:
```bash
xcodebuild -project AllTalk.xcodeproj -scheme AllTalk -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "error:|Compiling"
```
Expected: compile failure — `ServerState` has no members `menuLabel` / `isActive` (it's an empty stub).

- [ ] **Step 3: Implement `ServerState`**

Replace `AllTalk/ServerState.swift` with:
```swift
import Foundation

/// Lifecycle state of the local llama-server, published by `LlamaServerManager`.
/// Pure value type (no AppKit) so it is unit-testable in isolation.
enum ServerState: Equatable {
    case stopped
    case starting
    case ready
    case error(String)

    /// Label for the disabled status line at the top of the menu.
    var menuLabel: String {
        switch self {
        case .stopped:          return "○ Model: Stopped"
        case .starting:         return "◐ Model: Starting…"
        case .ready:            return "● Model: Ready"
        case .error(let why):   return "⚠ Model: \(why)"
        }
    }

    /// True while a server is up or coming up — drives the menu toggle wording.
    var isActive: Bool {
        switch self {
        case .starting, .ready: return true
        case .stopped, .error:  return false
        }
    }
}
```

- [ ] **Step 4: Run tests, verify they pass**

Run:
```bash
xcodebuild -project AllTalk.xcodeproj -scheme AllTalk -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "Test Suite 'ServerStateTests'|passed|failed"
```
Expected: `Test Suite 'ServerStateTests' passed` (3 tests).

- [ ] **Step 5: Commit**
```bash
git add AllTalk/ServerState.swift AllTalkTests/ServerStateTests.swift
git commit -m "feat: add ServerState enum with menu label + isActive"
```

---

## Task 3: `ServerDiscovery` (TDD)

**Files:**
- Test: `AllTalkTests/ServerDiscoveryTests.swift` (replace the Task-1 stub)
- Implement: `AllTalk/ServerDiscovery.swift`

- [ ] **Step 1: Write the failing tests**

Replace the Task-1 stub `AllTalkTests/ServerDiscoveryTests.swift` with:
```swift
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
        case .failure(let why):
            XCTAssertTrue(why.contains(ServerDiscovery.mmprojFileName), "should name the missing mmproj")
        }
    }

    func test_resolveModel_expandsTilde() {
        var seen: [String] = []
        _ = ServerDiscovery.resolveModel(folder: "~/models", fileExists: { seen.append($0); return true })
        XCTAssertFalse(seen.contains { $0.hasPrefix("~") }, "tilde should be expanded before checking")
    }
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run:
```bash
xcodebuild -project AllTalk.xcodeproj -scheme AllTalk -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "error:|Compiling"
```
Expected: compile failure — `ServerDiscovery` has no such members (empty stub).
> If `xcodebuild test` does not pick up the new file, confirm `ServerDiscoveryTests.swift`
> was added to the `BB06000001` Sources phase in `project.pbxproj` (Task 1 added the
> file refs; the build-file entries `BB01000002` must be present).

- [ ] **Step 3: Implement `ServerDiscovery`**

Replace `AllTalk/ServerDiscovery.swift` with:
```swift
import Foundation

/// Pure, dependency-injected helpers for locating the llama-server binary and the
/// model files. No AppKit and no real filesystem access (the caller injects the
/// checks), which makes these unit-testable.
enum ServerDiscovery {
    /// Filenames expected inside the configured model folder.
    static let modelFileName  = "Voxtral-Mini-3B-2507-Q4_K_M.gguf"
    static let mmprojFileName = "mmproj-Voxtral-Mini-3B-2507-Q8_0.gguf"

    /// Candidate locations for the llama-server binary, in priority order.
    static let binaryCandidates = [
        "/opt/homebrew/bin/llama-server",
        "/usr/local/bin/llama-server",
    ]

    /// Resolve the llama-server binary path.
    /// `override` (a Settings value) wins when non-empty and executable; otherwise the
    /// first executable candidate is returned, else `nil`.
    static func resolveBinary(override: String,
                              isExecutable: (String) -> Bool) -> String? {
        if !override.isEmpty, isExecutable(override) { return override }
        return binaryCandidates.first(where: isExecutable)
    }

    /// Resolve the model + mmproj file paths inside `folder` (tilde-expanded).
    /// `.success` only when both exist; `.failure(reason)` names the missing file(s).
    static func resolveModel(folder: String,
                             fileExists: (String) -> Bool)
        -> Result<(model: String, mmproj: String), String> {
        let expanded = (folder as NSString).expandingTildeInPath
        let model  = (expanded as NSString).appendingPathComponent(modelFileName)
        let mmproj = (expanded as NSString).appendingPathComponent(mmprojFileName)
        var missing: [String] = []
        if !fileExists(model)  { missing.append(modelFileName) }
        if !fileExists(mmproj) { missing.append(mmprojFileName) }
        guard missing.isEmpty else {
            return .failure("model not found in \(folder) — missing \(missing.joined(separator: ", "))")
        }
        return .success((model, mmproj))
    }
}
```

- [ ] **Step 4: Run tests, verify they pass**

Run:
```bash
xcodebuild -project AllTalk.xcodeproj -scheme AllTalk -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "Test Suite 'ServerDiscoveryTests'|passed|failed"
```
Expected: `Test Suite 'ServerDiscoveryTests' passed` (6 tests).

- [ ] **Step 5: Commit**
```bash
git add AllTalk/ServerDiscovery.swift AllTalkTests/ServerDiscoveryTests.swift
git commit -m "feat: add ServerDiscovery (binary + model resolution)"
```

---

## Task 4: `LlamaServerManager`

AppKit/Foundation; integration-verified manually (Task 8). It reuses the tested
`ServerState` + `ServerDiscovery`.

**Files:**
- Create: `AllTalk/LlamaServerManager.swift`
- Modify: `AllTalk.xcodeproj/project.pbxproj` (add to app target only)

- [ ] **Step 1: Add the file to the app target**

In `project.pbxproj` add a PBXFileReference + PBXBuildFile (mirroring `AA0200001x`),
add the ref to the `AllTalk` group (`AA04000002`), and the build file to the app
Sources phase (`AA06000001`):
```
		AA02000013 /* LlamaServerManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LlamaServerManager.swift; sourceTree = "<group>"; };
		AA01000013 /* LlamaServerManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA02000013 /* LlamaServerManager.swift */; };
```

- [ ] **Step 2: Implement `LlamaServerManager`**

Create `AllTalk/LlamaServerManager.swift`:
```swift
import Combine
import Foundation

/// Owns the local llama-server child process: lazy start, health polling, adoption
/// of an already-running server, PID-file crash recovery, and clean teardown of
/// ONLY the server we started.
@MainActor
final class LlamaServerManager: ObservableObject {
    @Published private(set) var state: ServerState = .stopped

    /// Fired on every state change so the AppKit menu can rebuild.
    var onStateChange: (() -> Void)?

    private let port = 8899
    private var process: Process?
    private var weStartedIt = false
    private var adoptedPid: Int32?
    private var healthTask: Task<Void, Never>?

    private var binaryOverride: String { UserDefaults.standard.string(forKey: "llamaServerPath") ?? "" }
    private var modelFolder: String { UserDefaults.standard.string(forKey: "modelFolder") ?? "~/dev/huggingface/models" }

    private var baseURL: URL { URL(string: "http://localhost:\(port)")! }

    private var pidFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AllTalk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("server.pid")
    }

    init() { adoptOrphanIfAny() }

    private func setState(_ s: ServerState) { state = s; onStateChange?() }

    // MARK: - Public API

    /// Ensure a server is running. Idempotent: no-op while starting/ready.
    func ensureRunning() {
        if state.isActive { return }
        setState(.starting)
        Task { await probeThenStart() }
    }

    /// Menu toggle: stop if active, start otherwise.
    func toggle() { state.isActive ? stopIfOwned() : ensureRunning() }

    /// Block (cooperatively) until `.ready` or `.error`, or until timeout. Returns the
    /// terminal state observed. Used by the controller before transcribing.
    func waitUntilReady(timeout: TimeInterval = 60) async -> ServerState {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if case .ready = state { return state }
            if case .error = state { return state }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return state
    }

    /// Terminate the server, but only if we started/adopted it.
    func stopIfOwned() {
        healthTask?.cancel(); healthTask = nil
        if weStartedIt {
            if let p = process, p.isRunning {
                let pid = p.processIdentifier
                p.terminate() // SIGTERM
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
                }
            } else if let pid = adoptedPid, kill(pid, 0) == 0 {
                kill(pid, SIGTERM)
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
                }
            }
            try? FileManager.default.removeItem(at: pidFileURL)
        }
        process = nil; weStartedIt = false; adoptedPid = nil
        setState(.stopped)
    }

    // MARK: - Internals

    private func probeThenStart() async {
        if await isCompatibleServerAnswering() {
            weStartedIt = false       // someone else's server — never kill it
            setState(.ready)
            return
        }
        if await portAnsweredButIncompatible() {
            setState(.error("port \(port) is in use by another process"))
            return
        }
        startProcess()
    }

    /// GET /v1/models → 200 with a non-empty `models` list = a compatible llama.cpp server.
    private func isCompatibleServerAnswering() async -> Bool {
        guard let (data, resp) = try? await URLSession.shared.data(from: baseURL.appendingPathComponent("v1/models")),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [Any], !models.isEmpty
        else { return false }
        return true
    }

    /// Distinguish "nothing listening" (connection refused) from "wrong service".
    private func portAnsweredButIncompatible() async -> Bool {
        guard let (_, resp) = try? await URLSession.shared.data(from: baseURL.appendingPathComponent("health"))
        else { return false }
        return (resp as? HTTPURLResponse) != nil
    }

    private func startProcess() {
        let fm = FileManager.default
        guard let binary = ServerDiscovery.resolveBinary(
            override: binaryOverride, isExecutable: { fm.isExecutableFile(atPath: $0) }
        ) else {
            setState(.error("llama-server not found — `brew install llama.cpp` or set its path in Settings"))
            return
        }
        let model: String, mmproj: String
        switch ServerDiscovery.resolveModel(folder: modelFolder, fileExists: { fm.fileExists(atPath: $0) }) {
        case .success(let pair): (model, mmproj) = (pair.model, pair.mmproj)
        case .failure(let why):  setState(.error(why)); return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = ["-m", model, "--mmproj", mmproj, "--port", "\(port)"]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in self?.handleProcessExit(proc) }
        }
        do { try p.run() }
        catch { setState(.error("failed to launch llama-server: \(error.localizedDescription)")); return }

        process = p
        weStartedIt = true
        try? "\(p.processIdentifier) \(port)".write(to: pidFileURL, atomically: true, encoding: .utf8)
        pollHealth()
    }

    private func handleProcessExit(_ proc: Process) {
        guard weStartedIt, proc === process else { return }
        process = nil
        let msg = (state == .ready) ? "model server exited unexpectedly" : "model server exited during startup"
        setState(.error(msg))
        weStartedIt = false
    }

    private func pollHealth() {
        healthTask?.cancel()
        healthTask = Task { [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(60)
            while !Task.isCancelled, Date() < deadline {
                if await self.isHealthy() {
                    await MainActor.run { self.setState(.ready) }
                    return
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            if !Task.isCancelled {
                await MainActor.run { self.setState(.error("model didn't become ready within 60s")) }
            }
        }
    }

    private func isHealthy() async -> Bool {
        guard let (data, resp) = try? await URLSession.shared.data(from: baseURL.appendingPathComponent("health")),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["status"] as? String) == "ok"
        else { return false }
        return true
    }

    /// On launch, if our PID file names a live process, re-adopt it as owned so the
    /// next Stop/Quit cleans it up — rather than stranding a crash orphan.
    private func adoptOrphanIfAny() {
        guard let raw = try? String(contentsOf: pidFileURL, encoding: .utf8),
              let pid = raw.split(separator: " ").first.flatMap({ Int32($0) }) else { return }
        if kill(pid, 0) == 0 {
            adoptedPid = pid
            weStartedIt = true
            setState(.starting)
            pollHealth() // confirm it's actually serving -> ready or error
        } else {
            try? FileManager.default.removeItem(at: pidFileURL)
        }
    }
}
```

- [ ] **Step 3: Build the app**

Run:
```bash
xcodebuild -project AllTalk.xcodeproj -scheme AllTalk -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**
```bash
git add AllTalk/LlamaServerManager.swift AllTalk.xcodeproj
git commit -m "feat: add LlamaServerManager (process lifecycle + health + adoption)"
```

---

## Task 5: Wire the manager into `AllTalkController`

**Files:**
- Modify: `AllTalk/AllTalkController.swift`

- [ ] **Step 1: Own a `LlamaServerManager` and forward its state changes**

In `AllTalkController`, add a stored property and wire it up in `init()`:
```swift
    let serverManager = LlamaServerManager()
```
At the end of the existing `init()` body add:
```swift
        serverManager.onStateChange = { [weak self] in self?.onStateChange?() }
```
Add settings + menu-facing accessors to the class:
```swift
    @Published var llamaServerPath: String = UserDefaults.standard.string(forKey: "llamaServerPath") ?? "" {
        didSet { UserDefaults.standard.set(llamaServerPath, forKey: "llamaServerPath") }
    }
    @Published var modelFolder: String = UserDefaults.standard.string(forKey: "modelFolder") ?? "~/dev/huggingface/models" {
        didSet { UserDefaults.standard.set(modelFolder, forKey: "modelFolder") }
    }

    var serverStatusLabel: String { serverManager.state.menuLabel }
    var serverIsActive: Bool { serverManager.state.isActive }
    func toggleServer() { serverManager.toggle() }
    func stopServer() { serverManager.stopIfOwned() }
```

- [ ] **Step 2: Start the server lazily at record-start**

In `startRecording()`, immediately after `recorder?.record()` succeeds (inside the `do` block, after `status = "Recording…"`), add:
```swift
            serverManager.ensureRunning() // lazy start; load overlaps with speaking
```

- [ ] **Step 3: Wait for `ready` before transcribing**

In `stopAndTranscribe()`, after the recording size check passes and **before** `await runCLI(audio: url)`, insert:
```swift
        status = "Starting model…"
        onStateChange?()
        let serverState = await serverManager.waitUntilReady()
        guard case .ready = serverState else {
            let reason: String
            if case .error(let why) = serverState { reason = why } else { reason = "model server not ready" }
            notify(title: "Model Not Ready", body: reason)
            try? FileManager.default.removeItem(at: url)
            status = "Idle"
            onStateChange?()
            return
        }
```

- [ ] **Step 4: Build the app**

Run:
```bash
xcodebuild -project AllTalk.xcodeproj -scheme AllTalk -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**
```bash
git add AllTalk/AllTalkController.swift
git commit -m "feat: lazy-start the model server at record-start; await ready before transcribing"
```

---

## Task 6: Menu status line + Stop/Start toggle + teardown on quit

**Files:**
- Modify: `AllTalk/AppDelegate.swift`

- [ ] **Step 1: Add the status line and toggle to `rebuildMenu()`**

At the top of `rebuildMenu()`, right after `let menu = NSMenu()`, insert a disabled status line:
```swift
        let statusLine = NSMenuItem(title: controller.serverStatusLabel, action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
```
Then, in the existing block that adds "Show Transcript…" / "Settings…", add the server toggle just before "Settings…":
```swift
        let serverItem = NSMenuItem(
            title: controller.serverIsActive ? "Stop Model Server" : "Start Model Server",
            action: #selector(toggleServer), keyEquivalent: "")
        menu.addItem(serverItem)
```

- [ ] **Step 2: Add the toggle action**

Add to `AppDelegate`:
```swift
    @objc private func toggleServer() { controller.toggleServer() }
```

- [ ] **Step 3: Tear down on quit**

Add to `AppDelegate`:
```swift
    func applicationWillTerminate(_ notification: Notification) {
        controller.stopServer()
    }
```
> `Quit AllTalk` uses `NSApplication.terminate(_:)`, which calls
> `applicationWillTerminate` — so `stopServer()` (i.e. `stopIfOwned()`) runs on quit.

- [ ] **Step 4: Build the app**

Run:
```bash
xcodebuild -project AllTalk.xcodeproj -scheme AllTalk -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**
```bash
git add AllTalk/AppDelegate.swift
git commit -m "feat: menu server status + Stop/Start toggle; stop owned server on quit"
```

---

## Task 7: Settings fields for binary path + model folder

**Files:**
- Modify: `AllTalk/SettingsView.swift`

- [ ] **Step 1: Add the two fields**

In `SettingsView.body`, add a new `Section` (place it after the existing "Server" section):
```swift
            Section("Model Server") {
                HStack {
                    TextField("llama-server path (blank = auto-detect)", text: $controller.llamaServerPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") { choosePath(into: { controller.llamaServerPath = $0 }, directories: false) }
                }
                HStack {
                    TextField("Model folder", text: $controller.modelFolder)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") { choosePath(into: { controller.modelFolder = $0 }, directories: true) }
                }
                Text("Looks for \(ServerDiscovery.modelFileName) and \(ServerDiscovery.mmprojFileName) in this folder.")
                    .font(.caption).foregroundColor(.secondary)
            }
```

- [ ] **Step 2: Generalise the existing file picker**

Replace the existing `chooseCLI()` method with a reusable picker:
```swift
    private func choosePath(into assign: @escaping (String) -> Void, directories: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !directories
        panel.canChooseDirectories = directories
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { assign(url.path) }
    }
```
Update the existing CLI "Choose…" button to call `choosePath(into: { controller.cliPath = $0 }, directories: false)`.

- [ ] **Step 3: Build the app**

Run:
```bash
xcodebuild -project AllTalk.xcodeproj -scheme AllTalk -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**
```bash
git add AllTalk/SettingsView.swift
git commit -m "feat: Settings fields for llama-server path and model folder"
```

---

## Task 8: Manual end-to-end verification (spec success criteria)

**Files:** none (verification only).

Prereqs: `llama-server` installed (`brew install llama.cpp`) and the two model files
present in `~/dev/huggingface/models` (per the README quick start).

- [ ] **Step 1: Build + launch (ad-hoc signed)**
```bash
xcodebuild -project AllTalk.xcodeproj -scheme AllTalk -configuration Debug \
  -derivedDataPath /tmp/alltalk-build CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" build
open /tmp/alltalk-build/Build/Products/Debug/AllTalk.app
```

- [ ] **Step 2: Criterion 1 — lazy start.** With no server running (`pgrep -f llama-server` empty), press ⌃⌥Space and speak. The menu status goes `◐ Starting…` → `● Ready`; the transcript appears. Confirm a server now runs: `pgrep -f llama-server`.

- [ ] **Step 3: Criterion 2 — clean quit.** Menu → Quit AllTalk. Verify nothing is left:
```bash
pgrep -f llama-server || echo "clean: no orphan ✓"
```

- [ ] **Step 4: Criterion 3 — adoption.** Start a server yourself:
```bash
llama-server -m ~/dev/huggingface/models/Voxtral-Mini-3B-2507-Q4_K_M.gguf \
  --mmproj ~/dev/huggingface/models/mmproj-Voxtral-Mini-3B-2507-Q8_0.gguf --port 8899 &
```
Launch the app; the status should show `● Ready` without spawning a second server (`pgrep -f llama-server` shows one PID). Quit the app, then confirm **your** server is still alive (`pgrep -f llama-server` still shows it). Kill it manually when done.

- [ ] **Step 5: Criterion 4 — menu Stop/Start.** With an app-owned server running, Menu → "Stop Model Server": status → `○ Stopped`, item flips to "Start Model Server", `pgrep` empty. Click "Start Model Server": status returns to `● Ready`.

- [ ] **Step 6: Criterion 5 — missing dependency.** Temporarily point Settings → Model folder at an empty directory; press ⌃⌥Space. Status shows `⚠ Model: model not found …`, a notification appears, and the app does not crash. Restore the folder afterward.

- [ ] **Step 7: Run the unit suite once more**
```bash
xcodebuild -project AllTalk.xcodeproj -scheme AllTalk -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "Test Suite 'All tests'|passed|failed"
```
Expected: all tests pass (ServerStateTests + ServerDiscoveryTests).

- [ ] **Step 8: Update docs**

Update `README.md` "Using it" and "Deliberately kept simple", and `CLAUDE.md`, to reflect
that the app now manages the server (no manual `llama-server` start needed in normal use;
the manual command remains as a fallback / for remote setups). Commit:
```bash
git add README.md CLAUDE.md
git commit -m "docs: note app-managed model server (Phase 1)"
```

---

## Done criteria

All five spec success criteria pass (Task 8), the unit suite is green, and the app
builds clean. Phase 1 is independently shippable; Phase 2 (model auto-download) builds
on the `modelFolder` setting and the `error` states introduced here.
