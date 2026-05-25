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

            // Editable + selectable transcript, with contextual help shown as a placeholder.
            ZStack(alignment: .topLeading) {
                TextEditor(text: $controller.transcript)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(4)
                if controller.transcript.isEmpty {
                    Text(emptyHelp)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .allowsHitTesting(false)   // clicks pass through to the editor
                }
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

                Button("Clear") { controller.clearTranscript() }
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

    /// Placeholder guidance shown when the transcript is empty.
    private var emptyHelp: String {
        if controller.isRecording {
            return "Recording — speak now, then press ⌃⌥Space again to stop."
        }
        if controller.status != "Idle" { return controller.status }   // Starting model… / Transcribing…
        switch controller.outputMode {
        case .paste:
            return "Press ⌃⌥Space to dictate.\n\nText is typed at your cursor — click into a text field first, or switch to “Popover” to keep it here. You can edit or Clear whatever lands below."
        case .popover:
            return "Press ⌃⌥Space to dictate.\n\nThe transcript appears here, where you can edit it, Copy it, or Clear it."
        }
    }
}
