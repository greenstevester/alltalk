import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var controller: AllTalkController

    var body: some View {
        Form {
            Section("Server") {
                TextField("llama-server URL", text: $controller.serverURL)
                    .textFieldStyle(.roundedBorder)
                Text("Default: http://localhost:8080")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("CLI Binary") {
                HStack {
                    TextField("Path to `alltalk`", text: $controller.cliPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") { chooseCLI() }
                }
                Text("Built from the `cli/` Go module. Run `go build -o alltalk .` and point here.")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("Prompt") {
                TextEditor(text: $controller.prompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 80)
                Button("Reset to default") {
                    controller.prompt = AllTalkController.defaultPrompt
                }
            }

            Section("Output") {
                Picker("Mode", selection: $controller.outputMode) {
                    Text("Paste at cursor").tag(OutputMode.paste)
                    Text("Show in popover").tag(OutputMode.popover)
                }
                .pickerStyle(.radioGroup)
            }

            Section("Hotkey") {
                Text("⌃⌥Space  (hardcoded for now)")
                    .font(.system(.body, design: .monospaced))
            }
        }
        .padding(20)
        .frame(width: 480, height: 520)
    }

    private func chooseCLI() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            controller.cliPath = url.path
        }
    }
}
