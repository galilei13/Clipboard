import AppKit
import Carbon

public struct Shortcut: Codable, Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var label: String
    public static let initial = Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey), label: "⌘ ⇧ V")
    public static func from(_ event: NSEvent) -> Shortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) || flags.contains(.control),
              ![54,55,56,57,58,59,60,61,62,63].contains(event.keyCode),
              let character = event.charactersIgnoringModifiers, !character.isEmpty else { return nil }
        // Keep common editing and application commands available to other apps.
        if flags == .command && ["c","v","x","a","q","w","z","s","f"].contains(character.lowercased()) { return nil }
        var modifiers: UInt32 = 0; var labels: [String] = []
        if flags.contains(.control) { modifiers |= UInt32(controlKey); labels.append("⌃") }
        if flags.contains(.option) { modifiers |= UInt32(optionKey); labels.append("⌥") }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey); labels.append("⌘") }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey); labels.append("⇧") }
        let named: [UInt16: String] = [36:"Return",49:"Space",48:"Tab",51:"Delete",123:"←",124:"→",125:"↓",126:"↑"]
        labels.append(named[event.keyCode] ?? character.uppercased())
        return Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, label: labels.joined(separator: " "))
    }
}

public final class HotKeyManager {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var current: Shortcut?
    private var nextID: UInt32 = 0
    public var onPress: (() -> Void)?

    public init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
            owner.onPress?()
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    public func register(_ shortcut: Shortcut) throws {
        if current == shortcut { return }
        nextID += 1
        var candidate: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x434C4950, id: nextID)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &candidate)
        guard status == noErr, let candidate else {
            throw NSError(domain: "Clipboard", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "That shortcut is unavailable. Choose a different combination; your previous shortcut is unchanged."])
        }
        if let ref { UnregisterEventHotKey(ref) }
        ref = candidate; current = shortcut
    }
    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}

public enum ClipboardKeyboard {
    public static func modifiers(for event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection([.command, .control, .option, .shift])
    }
    public static func itemNumber(for event: NSEvent) -> Int? {
        // Physical number keys also work with Persian and other input sources.
        let keys: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
        return keys[event.keyCode]
    }
}
