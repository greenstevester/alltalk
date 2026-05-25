import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var controller: AllTalkController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: controller.isRecording ? "record.circle.fill" : "waveform")
                    .foregroundColor(controller.isRecording ? .red : .secondary)
                Text(controller.status).font(.headline)
                Spacer()
                Text("⌃⌥Space").font(.caption).foregroundColor(.secondary)
            }

            Divider()

            ScrollView {
                Text(popoverText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(controller.transcript.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)

            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(controller.transcript, forType: .string)
                }
                .disabled(controller.transcript.isEmpty)

                Spacer()

                Picker("", selection: $controller.outputMode) {
                    Text("Paste").tag(OutputMode.paste)
                    Text("Popover").tag(OutputMode.popover)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
        }
        .padding(12)
        .frame(width: 420, height: 320)
    }

    /// Contextual guidance so the user always knows what's happening.
    private var popoverText: String {
        if !controller.transcript.isEmpty { return controller.transcript }
        if controller.isRecording {
            return "Recording — speak now, then press ⌃⌥Space again to stop."
        }
        if controller.status != "Idle" { return controller.status }   // Starting model… / Transcribing…
        switch controller.outputMode {
        case .paste:
            return "Press ⌃⌥Space to dictate.\n\nText is typed at your cursor — click into a text field first, or switch to “Popover” below to see it here."
        case .popover:
            return "Press ⌃⌥Space to dictate.\n\nThe transcript will appear here."
        }
    }
}
