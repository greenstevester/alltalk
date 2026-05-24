import AppKit
import Carbon.HIToolbox

enum Clipboard {
    /// Copy text to the pasteboard and synthesise ⌘V into whatever app is
    /// frontmost. Requires Accessibility permission to send synthetic events.
    static func paste(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        sendCmdV()
    }

    private static func sendCmdV() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vCode = CGKeyCode(kVK_ANSI_V)

        let down = CGEvent(keyboardEventSource: src, virtualKey: vCode, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: vCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand

        let loc = CGEventTapLocation.cghidEventTap
        down?.post(tap: loc)
        up?.post(tap: loc)
    }
}
