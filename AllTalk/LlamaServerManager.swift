import Combine
import Foundation

/// Owns the local llama-server child process: lazy start, health polling, adoption
/// of an already-running server, PID-file crash recovery, and clean teardown of
/// ONLY the server we started.
@MainActor
final class LlamaServerManager: ObservableObject {
    @Published private(set) var state: ServerState = .stopped

    /// Friendly one-liner for the menu header.
    var subtitle: String {
        switch state {
        case .stopped:        return "Model server stopped"
        case .starting:       return "Starting server…"
        case .stopping:       return "Stopping server…"
        case .ready:          return "Model server running"
        case .error(let why): return why
        }
    }

    /// Fired on every state change so the AppKit menu can rebuild.
    var onStateChange: (() -> Void)?

    private let port = 8899
    private var process: Process?
    private var weStartedIt = false
    private var adoptedPid: Int32?
    private var healthTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?

    private var binaryOverride: String { UserDefaults.standard.string(forKey: "llamaServerPath") ?? "" }
    private var modelFolder: String { UserDefaults.standard.string(forKey: "modelFolder") ?? "~/dev/huggingface/models" }

    private var baseURL: URL { URL(string: "http://localhost:\(port)")! }

    private lazy var pidFileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AllTalk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("server.pid")
    }()

    init() { adoptOrphanIfAny() }

    private func setState(_ s: ServerState) { state = s; onStateChange?() }

    // MARK: - Public API

    /// Ensure a server is running. Idempotent: no-op while starting/ready.
    func ensureRunning() {
        if state.isActive { return }
        setState(.starting)
        startTask = Task { [weak self] in await self?.probeThenStart() }
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
            if case .stopped = state { return state } // user stopped the server while we waited
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return state
    }

    /// Terminate the server, but only if we started/adopted it.
    func stopIfOwned() {
        startTask?.cancel(); startTask = nil
        healthTask?.cancel(); healthTask = nil
        guard weStartedIt else {
            // Adopted (someone else's) server — leave it running, just forget it.
            process = nil; adoptedPid = nil
            setState(.stopped)
            return
        }
        setState(.stopping)
        let pid = process?.processIdentifier ?? adoptedPid
        if let p = process, p.isRunning { p.terminate() }   // SIGTERM
        else if let pid { kill(pid, SIGTERM) }
        process = nil; weStartedIt = false; adoptedPid = nil
        try? FileManager.default.removeItem(at: pidFileURL)
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [weak self] in
            if let pid, kill(pid, 0) == 0 { kill(pid, SIGKILL) }
            DispatchQueue.main.async { self?.setState(.stopped) }
        }
    }

    /// Re-verify the server's real state (called when the menu opens) so the header
    /// reflects reality, not just our last belief — picks up a crashed or
    /// externally-started server.
    func refresh() {
        switch state { case .starting, .stopping: return; default: break }
        Task { [weak self] in
            guard let self else { return }
            let up = await self.isCompatibleServerAnswering()
            switch self.state {
            case .starting, .stopping:
                return
            default:
                if up, !self.state.isActive {
                    self.weStartedIt = false
                    self.setState(.ready)
                } else if !up, case .ready = self.state {
                    self.process = nil; self.weStartedIt = false; self.adoptedPid = nil
                    self.setState(.stopped)
                }
            }
        }
    }

    // MARK: - Internals

    private func probeThenStart() async {
        if await isCompatibleServerAnswering() {
            guard case .starting = state else { return } // user stopped while we probed
            weStartedIt = false       // someone else's server — never kill it
            setState(.ready)
            return
        }
        guard case .starting = state else { return }
        if await portAnsweredButIncompatible() {
            guard case .starting = state else { return }
            setState(.error("port \(port) is in use by another process"))
            return
        }
        guard case .starting = state else { return }
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
        case .failure(let err):  setState(.error(err.message)); return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = ["-m", model, "--mmproj", mmproj, "--port", "\(port)"]
        // Discard the server's (very verbose) output: we monitor it via /health, not
        // stdout, and an undrained Pipe would fill its ~64 KB buffer and deadlock the child.
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
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
        healthTask?.cancel(); healthTask = nil // so its 60s timeout can't overwrite this crash message
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
