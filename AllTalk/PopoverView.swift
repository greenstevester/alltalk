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
                Text(controller.transcript.isEmpty
                     ? "Press ⌃⌥Space (or use the menu) to start recording."
                     : controller.transcript)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(.body, design: .monospaced))
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
}
