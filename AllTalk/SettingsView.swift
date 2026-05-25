import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var controller: AllTalkController

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            modelServerTab
                .tabItem { Label("Model Server", systemImage: "server.rack") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 400)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Picker("Output mode", selection: $controller.outputMode) {
                Text("Paste at cursor").tag(OutputMode.paste)
                Text("Show in popover").tag(OutputMode.popover)
            }
            .pickerStyle(.segmented)

            Section("Prompt") {
                TextEditor(text: $controller.prompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 90)
                Button("Reset to default") {
                    controller.prompt = AllTalkController.defaultPrompt
                }
            }

            LabeledContent("Hotkey", value: "⌃⌥Space")
        }
        .formStyle(.grouped)
    }

    // MARK: - Model Server

    private var modelServerTab: some View {
        Form {
            Section {
                TextField("Server URL", text: $controller.serverURL)
            } footer: {
                Text("Where AllTalk reaches llama-server. Default: http://localhost:8899")
                    .foregroundStyle(.secondary)
            }

            Section("Paths") {
                pathRow("llama-server", binding: $controller.llamaServerPath,
                        prompt: "blank = auto-detect", directories: false)
                pathRow("Model folder", binding: $controller.modelFolder,
                        prompt: "~/dev/huggingface/models", directories: true)
                pathRow("alltalk CLI", binding: $controller.cliPath,
                        prompt: "/usr/local/bin/alltalk", directories: false)
            }
        }
        .formStyle(.grouped)
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

    @ViewBuilder
    private func pathRow(_ label: String, binding: Binding<String>,
                         prompt: String, directories: Bool) -> some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                TextField(prompt, text: binding)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)
                Button("Choose…") {
                    choosePath(directories: directories) { binding.wrappedValue = $0 }
                }
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
}
