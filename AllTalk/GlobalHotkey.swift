import Carbon.HIToolbox

/// Minimal Carbon-based global hotkey. Carbon is "deprecated" but still the
/// only public API for system-wide hotkeys without Accessibility permissions.
final class GlobalHotkey {
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let handler: () -> Void
    private var ref: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private static var nextID: UInt32 = 1
    private static var handlers: [UInt32: () -> Void] = [:]

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.handler = handler
    }

    @discardableResult
    func register() -> Bool {
        let id = GlobalHotkey.nextID
        GlobalHotkey.nextID += 1
        GlobalHotkey.handlers[id] = handler

        var hotKeyID = EventHotKeyID(signature: OSType(0x414C544B), id: id) // 'ALTK'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return false }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            GlobalHotkey.handlers[hkID.id]?()
            return noErr
        }, 1, &eventType, nil, &eventHandler)
        return true
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
