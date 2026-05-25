import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var controller: AllTalkController

    private struct CheckResult { let ok: Bool; let message: String }
    @State private var serverCheck: CheckResult?
    @State private var modelCheck: CheckResult?
    @State private var cliCheck: CheckResult?

    var body: some View {
        TabView {
            setupTab.tabItem { Label("Setup Sanity Check", systemImage: "checkmark.seal") }
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            advancedTab.tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 580, height: 480)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section {
                Picker("Output mode", selection: $controller.outputMode) {
                    Text("Insert at cursor").tag(OutputMode.paste)
                    Text("Show in popover").tag(OutputMode.popover)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Choose your text output mode when dictating:")
            } footer: {
                Text("“Insert at cursor” places the transcript where your cursor currently sits — so click into a text field first. “Show in popover” pops up an AllTalk window where all your text is captured for you (to copy from if you choose).")
            }

            Section {
                LabeledContent("Hotkey", value: "⌃⌥Space")
            } footer: {
                Text("Hold Control + Option + Space to start recording; press again to stop. Hardcoded for now.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Advanced (system prompt)

    /// A named example instruction the user can start from. The prompt text is sent to
    /// the model with every recording, so it changes what the model *does* with speech.
    private struct PromptPreset: Identifiable {
        var id: String { name }
        let name: String
        let detail: String
        let prompt: String
    }

    private static let promptPresets: [PromptPreset] = [
        PromptPreset(
            name: "Transcribe verbatim",
            detail: "Word-for-word — no tidying, no commentary. Exactly what you said. (Default.)",
            prompt: "Transcribe this audio verbatim. Output only the transcript, no commentary."),
        PromptPreset(
            name: "Clean up",
            detail: "Transcribes, then drops filler words (“um”, “uh”), false starts and obvious slips.",
            prompt: "Transcribe this audio, removing filler words, false starts and obvious grammar mistakes. Output only the cleaned-up text, no commentary."),
        PromptPreset(
            name: "Translate to English",
            detail: "Speak in any language; get clean English back.",
            prompt: "Translate the speech in this audio into English. Output only the translation, no commentary."),
        PromptPreset(
            name: "Answer the question",
            detail: "Treats what you say as a question and answers it concisely.",
            prompt: "Answer the question asked in this audio. Be concise. Output only the answer."),
        PromptPreset(
            name: "Bullet summary",
            detail: "Condenses what you said into a few short bullet points.",
            prompt: "Summarise the speech in this audio as concise bullet points. Output only the bullets."),
    ]

    private static let customPresetTag = "Custom"

    /// Which preset (if any) the current prompt text matches; otherwise “Custom”.
    private var selectedPresetName: String {
        Self.promptPresets.first { $0.prompt == controller.prompt }?.name ?? Self.customPresetTag
    }

    private var presetBinding: Binding<String> {
        Binding(
            get: { selectedPresetName },
            set: { name in
                if let preset = Self.promptPresets.first(where: { $0.name == name }) {
                    controller.prompt = preset.prompt   // selecting “Custom” is a no-op
                }
            })
    }

    private var advancedTab: some View {
        Form {
            Section {
                Picker("Example", selection: presetBinding) {
                    ForEach(Self.promptPresets) { Text($0.name).tag($0.name) }
                    Divider()
                    Text("Custom").tag(Self.customPresetTag)
                }
                if let detail = Self.promptPresets.first(where: { $0.name == selectedPresetName })?.detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }

                TextEditor(text: $controller.prompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 90)
                Button("Reset to default") { controller.prompt = AllTalkController.defaultPrompt }
            } header: {
                Text("System prompt")
            } footer: {
                Text("This instruction is sent to the model with every recording — it changes what the model does with your speech, not just how it’s written down. Pick an example to start from, then edit it freely.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Setup Sanity Check

    private var setupTab: some View {
        Form {
            Section {
                LabeledContent("Server URL") {
                    HStack(spacing: 6) {
                        PlainTextField(text: $controller.serverURL, placeholder: "http://localhost:8899")
                            .frame(maxWidth: .infinity)
                        Button("Test") { testServer() }
                    }
                }
                resultRow(serverCheck)
            } header: {
                Text("Model server")
            } footer: {
                Text("AllTalk starts llama-server for you on your first dictation. “Test” checks it’s reachable right now (it won’t be until you’ve recorded once, or started it from the menu).")
            }

            Section {
                pathRow("llama-server", binding: $controller.llamaServerPath, prompt: "blank = auto-detect")

                LabeledContent("Model folder") {
                    HStack(spacing: 6) {
                        TextField("~/dev/huggingface/models", text: $controller.modelFolder)
                            .textFieldStyle(.roundedBorder)
                        Button("Choose…") { choosePath(directories: true) { controller.modelFolder = $0 } }
                        Button("Verify") { verifyModel() }
                    }
                }
                resultRow(modelCheck)

                LabeledContent("alltalk CLI") {
                    HStack(spacing: 6) {
                        TextField("/usr/local/bin/alltalk", text: $controller.cliPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Choose…") { choosePath(directories: false) { controller.cliPath = $0 } }
                        Button("Test") { testCLI() }
                    }
                }
                resultRow(cliCheck)
            } header: {
                Text("Paths")
            } footer: {
                Text("“Verify” confirms both model files are in the folder; “Test” checks the alltalk CLI is installed and runnable.")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func resultRow(_ result: CheckResult?) -> some View {
        if let result {
            Label(result.message, systemImage: result.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.ok ? Color.green : Color.red)
                .font(.callout)
                .textSelection(.enabled)
        }
    }

    // MARK: - Checks

    private func verifyModel() {
        let fm = FileManager.default
        switch ServerDiscovery.resolveModel(folder: controller.modelFolder, fileExists: { fm.fileExists(atPath: $0) }) {
        case .success:
            modelCheck = CheckResult(ok: true, message: "Both model files found.")
        case .failure(let error):
            modelCheck = CheckResult(ok: false, message: error.message)
        }
    }

    private func testCLI() {
        let path = controller.cliPath
        cliCheck = FileManager.default.isExecutableFile(atPath: path)
            ? CheckResult(ok: true, message: "Found and runnable at \(path).")
            : CheckResult(ok: false, message: "Not found or not executable at \(path). Build it: cd cli && go build -o alltalk . && sudo install alltalk /usr/local/bin/")
    }

    private func testServer() {
        serverCheck = CheckResult(ok: true, message: "Checking…")
        let urlString = controller.serverURL
        Task {
            let reachable = await Self.serverIsReady(urlString)
            await MainActor.run {
                serverCheck = reachable
                    ? CheckResult(ok: true, message: "Server is up and a model is loaded.")
                    : CheckResult(ok: false, message: "Not reachable. It starts automatically when you dictate, or pick “Start Model Server” from the menu, then test again.")
            }
        }
    }

    private static func serverIsReady(_ urlString: String) async -> Bool {
        let base = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = base.hasSuffix("/") ? base + "v1/models" : base + "/v1/models"
        guard let url = URL(string: endpoint),
              let (data, resp) = try? await URLSession.shared.data(from: url),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [Any], !models.isEmpty
        else { return false }
        return true
    }

    @ViewBuilder
    private func pathRow(_ label: String, binding: Binding<String>, prompt: String) -> some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                TextField(prompt, text: binding).textFieldStyle(.roundedBorder)
                Button("Choose…") { choosePath(directories: false) { binding.wrappedValue = $0 } }
            }
        }
    }

    private func choosePath(directories: Bool, assign: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !directories
        panel.canChooseDirectories = directories
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { assign(url.path) }
    }

    // MARK: - About

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "Version \(v)"
    }

    private var aboutTab: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
            Text("AllTalk").font(.title2).fontWeight(.semibold)
            Text(appVersion).font(.subheadline).foregroundStyle(.secondary)
            Text("Push-to-talk dictation that runs entirely on your own machine.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Link("github.com/greenstevester/alltalk",
                 destination: URL(string: "https://github.com/greenstevester/alltalk")!)
                .padding(.top, 4)
            Text("MIT License · © 2026 Steve Greensill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// A plain editable text field whose contents are never rendered as a clickable
/// link. SwiftUI's `TextField` on recent macOS auto-detects a typed URL and draws
/// a blue "smart link" copy beside the editable text; a bare NSTextField doesn't.
private struct PlainTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.stringValue = text
        field.placeholderString = placeholder
        field.bezelStyle = .roundedBezel
        field.isBordered = true
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingHead
        field.allowsEditingTextAttributes = false   // plain text only — no link styling
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)   // fill width like a SwiftUI TextField
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
