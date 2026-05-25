import AppKit
import Carbon.HIToolbox
import SwiftUI
import UserNotifications

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AllTalkController()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var hotkey: GlobalHotkey?
    private var settingsWindow: NSWindow?

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
            DispatchQueue.main.async {
                guard let self else { return }
                self.rebuildMenu()
                // Surface what's happening: open the transcript popover when recording begins.
                if self.controller.isRecording { self.showPopover() }
            }
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
        menu.autoenablesItems = false   // we manage enabling; keeps the custom header view interactive

        // Tailscale-style header: app icon, name, server status, and an on/off switch.
        let header = NSMenuItem()
        header.view = makeServerHeader()
        menu.addItem(header)
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
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit AllTalk", action: #selector(quitApp), keyEquivalent: "q"))

        for item in menu.items { item.target = self }
        statusItem.menu = menu

        // Right-click → menu; left-click → popover.
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func toggleRecord() { controller.toggleRecording() }
    @objc private func toggleServer() { controller.toggleServer() }
    @objc private func setPasteMode() { controller.outputMode = .paste }
    @objc private func setNotifyMode() { controller.outputMode = .popover }
    @objc private func quitApp() { NSApp.terminate(nil) }

    private func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func serverSwitchToggled(_ sender: NSSwitch) {
        controller.toggleServer()
    }

    /// Tailscale-style header row: app icon, "AllTalk", the server status, and an on/off switch.
    private func makeServerHeader() -> NSView {
        let width: CGFloat = 260, height: CGFloat = 52
        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let icon = NSImageView(frame: NSRect(x: 14, y: (height - 30) / 2, width: 30, height: 30))
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        view.addSubview(icon)

        let title = NSTextField(labelWithString: "AllTalk")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.frame = NSRect(x: 54, y: 27, width: 150, height: 18)
        view.addSubview(title)

        let subtitle = NSTextField(labelWithString: controller.serverSubtitle)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.frame = NSRect(x: 54, y: 9, width: 150, height: 16)
        view.addSubview(subtitle)

        let toggle = NSSwitch(frame: NSRect(x: width - 58, y: (height - 22) / 2, width: 44, height: 22))
        toggle.state = controller.serverIsActive ? .on : .off
        toggle.target = self
        toggle.action = #selector(serverSwitchToggled(_:))
        view.addSubview(toggle)

        return view
    }
    @objc private func openSettings() {
        // Open our own AppKit-hosted window rather than the SwiftUI `Settings` scene:
        // the private `showSettingsWindow:` selector is unreliable for a menu-bar
        // (.accessory) app and silently no-ops on recent macOS.
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView().environmentObject(controller))
            let win = NSWindow(contentViewController: host)
            win.title = "AllTalk Settings"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.center()
            settingsWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
