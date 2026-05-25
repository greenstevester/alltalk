import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var controller: AllTalkController

    private struct CheckResult { let ok: Bool; let message: String }
    @State private var serverCheck: CheckResult?
    @State private var modelCheck: CheckResult?
    @State private var cliCheck: CheckResult?

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            setupTab.tabItem { Label("Setup Sanity Check", systemImage: "checkmark.seal") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 580, height: 480)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section {
                Picker("Output mode", selection: $controller.outputMode) {
                    Text("Paste at cursor").tag(OutputMode.paste)
                    Text("Show in popover").tag(OutputMode.popover)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("When you dictate")
            } footer: {
                Text("Where the transcript goes. “Paste at cursor” types it into whatever app is focused, so click into a text field first. “Show in popover” collects it in AllTalk’s own window for you to copy.")
            }

            Section {
                TextEditor(text: $controller.prompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80)
                Button("Reset to default") { controller.prompt = AllTalkController.defaultPrompt }
            } header: {
                Text("Prompt")
            } footer: {
                Text("Sent to the model with every recording. The default transcribes word-for-word. Change it for translation or Q&A — e.g. “Translate this to French.” or “Answer the question in this audio.”")
            }

            Section {
                LabeledContent("Hotkey", value: "⌃⌥Space")
            } footer: {
                Text("Hold Control + Option + Space to start recording; press again to stop. Hardcoded for now.")
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
                        TextField("http://localhost:8899", text: $controller.serverURL)
                            .textFieldStyle(.roundedBorder)
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
