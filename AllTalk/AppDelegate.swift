import AppKit
import Carbon.HIToolbox
import SwiftUI
import UserNotifications

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AllTalkController()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var hotkey: GlobalHotkey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu bar only, no Dock icon

        // Status bar item.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "AllTalk")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        rebuildMenu()

        // Popover for transcript display / settings access.
        popover = NSPopover()
        popover.contentSize = NSSize(width: 420, height: 320)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView().environmentObject(controller)
        )

        // Global hotkey: ⌃⌥Space by default.
        hotkey = GlobalHotkey(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.controller.toggleRecording()
        }
        if hotkey?.register() != true {
            NSLog("AllTalk: failed to register global hotkey ⌃⌥Space")
        }

        // Refresh menu when state changes (recording started/stopped, etc.)
        controller.onStateChange = { [weak self] in
            DispatchQueue.main.async { self?.rebuildMenu() }
        }

        // Ask for notification permission once.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stopServer() // tear down the server we started (no-op for an adopted one)
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        // Model-server status line (non-clickable; action == nil keeps it greyed).
        let statusLine = NSMenuItem(title: controller.serverStatusLabel, action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        let recordingTitle = controller.isRecording ? "■ Stop Recording" : "● Start Recording  ⌃⌥Space"
        menu.addItem(NSMenuItem(title: recordingTitle, action: #selector(toggleRecord), keyEquivalent: ""))

        menu.addItem(.separator())

        // Output mode toggles.
        let pasteItem = NSMenuItem(title: "Paste at Cursor", action: #selector(setPasteMode), keyEquivalent: "")
        pasteItem.state = controller.outputMode == .paste ? .on : .off
        menu.addItem(pasteItem)

        let notifyItem = NSMenuItem(title: "Show in Popover", action: #selector(setNotifyMode), keyEquivalent: "")
        notifyItem.state = controller.outputMode == .popover ? .on : .off
        menu.addItem(notifyItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Show Transcript…", action: #selector(togglePopover(_:)), keyEquivalent: ""))
        let serverTitle = controller.serverIsActive ? "Stop Model Server" : "Start Model Server"
        menu.addItem(NSMenuItem(title: serverTitle, action: #selector(toggleServer), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit AllTalk", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        for item in menu.items { item.target = self }
        statusItem.menu = menu

        // Right-click → menu; left-click → popover.
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func toggleRecord() { controller.toggleRecording() }
    @objc private func toggleServer() { controller.toggleServer() }
    @objc private func setPasteMode() { controller.outputMode = .paste }
    @objc private func setNotifyMode() { controller.outputMode = .popover }
    @objc private func openSettings() {
        if #available(macOS 14, *) {
            NSApp.activate()
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
