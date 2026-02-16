import Carbon
import Foundation

struct ParsedHotkey: Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
}

enum HotkeyParser {
    private static let keyMap: [String: UInt32] = [
        "space": 49,
        "return": 36,
        "enter": 76,
        "tab": 48,
        "escape": 53,
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4,
        "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35,
        "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7,
        "y": 16, "z": 6
    ]

    private static let modifierMap: [String: UInt32] = [
        "command": UInt32(cmdKey),
        "control": UInt32(controlKey),
        "option": UInt32(optionKey),
        "shift": UInt32(shiftKey)
    ]

    static func parse(_ hotkey: HotkeyConfig) throws -> ParsedHotkey {
        let keyLower = hotkey.key.lowercased()
        guard let keyCode = keyMap[keyLower] else {
            throw WalkieError.invalidHotkey("unknown key '\(hotkey.key)'")
        }
        let modifiers = try hotkey.modifiers.reduce(UInt32(0)) { partial, mod in
            let lower = mod.lowercased()
            guard let mapped = modifierMap[lower] else {
                throw WalkieError.invalidHotkey("unknown modifier '\(mod)'")
            }
            return partial | mapped
        }
        return ParsedHotkey(keyCode: keyCode, modifiers: modifiers)
    }
}

enum HotkeyPhase {
    case pressed
    case released
}

final class HotkeyManager {
    typealias Callback = @Sendable (WalkieMode, HotkeyPhase) -> Void

    private var hotkeyRefs: [EventHotKeyRef?] = [nil, nil]
    private var callback: Callback?
    private var eventHandler: EventHandlerRef?

    func register(config: WalkieConfig, callback: @escaping Callback) throws {
        unregisterAll()
        self.callback = callback

        let eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, eventRef, userData in
                guard let userData,
                      let eventRef else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handle(event: eventRef)
            },
            2,
            eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard status == noErr else {
            throw WalkieError.injectionBlocked("failed to install hotkey event handler")
        }

        try registerSingle(id: 1, mode: .dictation, parsed: HotkeyParser.parse(config.hotkeys.dictation), index: 0)
        try registerSingle(id: 2, mode: .agent, parsed: HotkeyParser.parse(config.hotkeys.agent), index: 1)
    }

    func unregisterAll() {
        for ref in hotkeyRefs {
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotkeyRefs = [nil, nil]
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func registerSingle(id: UInt32, mode: WalkieMode, parsed: ParsedHotkey, index: Int) throws {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x57544B59), id: id) // WTKY
        let status = RegisterEventHotKey(
            parsed.keyCode,
            parsed.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else {
            throw WalkieError.invalidHotkey("failed to register \(mode.rawValue) hotkey")
        }
        hotkeyRefs[index] = hotKeyRef
    }

    private func handle(event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }

        let kind = GetEventKind(event)
        let phase: HotkeyPhase = (kind == UInt32(kEventHotKeyPressed)) ? .pressed : .released
        let mode: WalkieMode
        switch hotKeyID.id {
        case 1: mode = .dictation
        case 2: mode = .agent
        default: return noErr
        }
        callback?(mode, phase)
        return noErr
    }
}
