import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut (PRD C5). Uses Carbon's `RegisterEventHotKey`,
/// which works in the sandbox and needs no Accessibility permission: the system
/// delivers only this key combination to the app, nothing else that is typed.
@MainActor
final class GlobalHotKey {
    struct Combo: Equatable {
        var keyCode: UInt32
        var modifiers: UInt32
        /// As shown in menus, e.g. "⌥⌘S".
        var symbol: String

        /// ⌥⌘S, "Save".
        static let quickCapture = Combo(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey | cmdKey), symbol: "⌥⌘S")
    }

    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false
    private static let signature: OSType = "NXMK".utf8.reduce(0) { $0 << 8 | OSType($1) }

    private var reference: EventHotKeyRef?
    private let id: UInt32

    /// Registers the combo; returns nil if another app already owns it.
    init?(_ combo: Combo, action: @escaping () -> Void) {
        Self.installHandlerIfNeeded()
        id = Self.nextID
        Self.nextID += 1
        var registered: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode, combo.modifiers, EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &registered
        )
        guard status == noErr, let registered else { return nil }
        reference = registered
        Self.actions[id] = action
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        Self.actions[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // A C callback: it can't capture anything, so it looks the action up by ID.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr else { return status }
            let id = hotKeyID.id
            Task { @MainActor in GlobalHotKey.actions[id]?() }
            return noErr
        }, 1, &eventType, nil, nil)
    }
}
