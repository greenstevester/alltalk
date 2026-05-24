import AVFoundation
import AppKit
import Combine
import Foundation
import UserNotifications

enum OutputMode: String {
    case paste
    case popover
}

@MainActor
final class AllTalkController: ObservableObject {
    // MARK: - Published UI state
    @Published private(set) var isRecording = false
    @Published private(set) var isStreaming = false
    @Published private(set) var transcript = ""
    @Published private(set) var status = "Idle"

    // MARK: - User settings (mirrored to UserDefaults)
    @Published var outputMode: OutputMode = .paste {
        didSet {
            UserDefaults.standard.set(outputMode.rawValue, forKey: "outputMode")
            onStateChange?()
        }
    }
    @Published var serverURL: String = UserDefaults.standard.string(forKey: "serverURL") ?? "http://localhost:8080" {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }
    @Published var prompt: String = UserDefaults.standard.string(forKey: "prompt") ?? defaultPrompt {
        didSet { UserDefaults.standard.set(prompt, forKey: "prompt") }
    }
    @Published var cliPath: String = UserDefaults.standard.string(forKey: "cliPath") ?? "/usr/local/bin/alltalk" {
        didSet { UserDefaults.standard.set(cliPath, forKey: "cliPath") }
    }

    var onStateChange: (() -> Void)?

    static let defaultPrompt = "Transcribe this audio verbatim. Output only the transcript, no commentary."

    // MARK: - Private state
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var task: Process?
    private var stdoutPipe: Pipe?
    private var readBuffer = ""

    init() {
        if let raw = UserDefaults.standard.string(forKey: "outputMode"),
           let mode = OutputMode(rawValue: raw) {
            outputMode = mode
        }
    }

    // MARK: - Recording lifecycle

    func toggleRecording() {
        Task { @MainActor in
            if isStreaming { return } // ignore hotkey mid-stream
            if isRecording {
                await stopAndTranscribe()
            } else {
                await startRecording()
            }
        }
    }

    private func startRecording() async {
        // Request mic permission lazily.
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else {
            notify(title: "Microphone Access Denied",
                   body: "Enable in System Settings → Privacy → Microphone.")
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alltalk-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.prepareToRecord()
            recorder?.record()
            recordingURL = url
            isRecording = true
            status = "Recording…"
            playSound("Tink")
            onStateChange?()
        } catch {
            notify(title: "Recording Failed", body: error.localizedDescription)
        }
    }

    private func stopAndTranscribe() async {
        recorder?.stop()
        recorder = nil
        isRecording = false
        playSound("Pop")

        guard let url = recordingURL else {
            status = "Idle"
            onStateChange?()
            return
        }
        defer { recordingURL = nil }

        // Sanity-check size.
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if size < 4_000 {
            notify(title: "Recording Too Short", body: "Try again.")
            try? FileManager.default.removeItem(at: url)
            status = "Idle"
            onStateChange?()
            return
        }

        await runCLI(audio: url)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - CLI streaming

    private func runCLI(audio: URL) async {
        let cli = cliPath
        guard FileManager.default.isExecutableFile(atPath: cli) else {
            notify(title: "alltalk CLI not found",
                   body: "Set the path in Settings (currently: \(cli)).")
            status = "Idle"
            onStateChange?()
            return
        }

        isStreaming = true
        transcript = ""
        readBuffer = ""
        status = "Transcribing…"
        onStateChange?()

        let task = Process()
        task.executableURL = URL(fileURLWithPath: cli)
        task.arguments = ["-f", audio.path, "-url", serverURL, "-p", prompt]

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        self.task = task
        self.stdoutPipe = outPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.handleChunk(chunk) }
        }

        do {
            try task.run()
        } catch {
            notify(title: "Failed to start CLI", body: error.localizedDescription)
            isStreaming = false
            status = "Idle"
            onStateChange?()
            return
        }

        // Wait off the main actor.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            task.terminationHandler = { _ in cont.resume() }
        }

        outPipe.fileHandleForReading.readabilityHandler = nil

        if task.terminationStatus != 0 {
            let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            notify(title: "AllTalk Error",
                   body: errText.isEmpty ? "exit \(task.terminationStatus)" : errText)
        } else {
            finishStream()
        }

        isStreaming = false
        status = "Idle"
        self.task = nil
        self.stdoutPipe = nil
        onStateChange?()
    }

    private func handleChunk(_ chunk: String) {
        transcript += chunk
        readBuffer += chunk

        // For paste mode, paste each whitespace-delimited word as it lands so
        // dictation feels live.
        if outputMode == .paste {
            while let spaceIdx = readBuffer.firstIndex(where: { $0.isWhitespace }) {
                let word = String(readBuffer[..<readBuffer.index(after: spaceIdx)])
                readBuffer.removeSubrange(..<readBuffer.index(after: spaceIdx))
                Clipboard.paste(word)
            }
        }
    }

    private func finishStream() {
        switch outputMode {
        case .paste:
            if !readBuffer.isEmpty {
                Clipboard.paste(readBuffer)
                readBuffer = ""
            }
        case .popover:
            notify(title: "Transcript Ready",
                   body: String(transcript.prefix(200)))
        }
    }

    // MARK: - Helpers

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func playSound(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }
}
