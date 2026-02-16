import AppKit
import CoreGraphics
import Foundation

struct ClipboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]
}

struct TextInjector {
    func inject(text: String, pressEnter: Bool, fallbackToTyping: Bool) throws {
        try AccessibilityService.ensureTrusted(promptIfNeeded: true)

        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard(pasteboard)

        defer {
            restorePasteboard(snapshot, to: pasteboard)
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        do {
            try sendPasteShortcut()
            if pressEnter {
                try sendReturnKey()
            }
        } catch {
            guard fallbackToTyping else {
                throw error
            }
            try type(text: text)
            if pressEnter {
                try sendReturnKey()
            }
        }
    }

    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> ClipboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]] = pasteboard.pasteboardItems?.map { item in
            var payload: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    payload[type] = data
                }
            }
            return payload
        } ?? []
        return ClipboardSnapshot(items: items)
    }

    private func restorePasteboard(_ snapshot: ClipboardSnapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        for item in snapshot.items {
            let pbItem = NSPasteboardItem()
            for (type, data) in item {
                pbItem.setData(data, forType: type)
            }
            pasteboard.writeObjects([pbItem])
        }
    }

    private func sendPasteShortcut() throws {
        try sendKeyCombo(keyCode: 9, command: true) // V
    }

    private func sendReturnKey() throws {
        try sendKeyCombo(keyCode: 36, command: false)
    }

    private func sendKeyCombo(keyCode: CGKeyCode, command: Bool) throws {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw WalkieError.injectionBlocked("No event source. Accessibility permission likely missing.")
        }

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            throw WalkieError.injectionBlocked("Failed creating keyboard events")
        }

        if command {
            down.flags = .maskCommand
            up.flags = .maskCommand
        }

        down.post(tap: .cghidEventTap)
        usleep(25_000)
        up.post(tap: .cghidEventTap)
    }

    private func type(text: String) throws {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw WalkieError.injectionBlocked("No event source for typed fallback")
        }

        for scalar in text.unicodeScalars {
            var value = UInt16(scalar.value)
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else {
                throw WalkieError.injectionBlocked("Failed creating typed fallback events")
            }
            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &value)
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &value)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
