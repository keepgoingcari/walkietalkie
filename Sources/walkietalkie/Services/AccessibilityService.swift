import ApplicationServices
import AppKit
import Foundation

enum AccessibilityService {
    static func isTrusted(promptIfNeeded: Bool) -> Bool {
        if promptIfNeeded {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    static func ensureTrusted(promptIfNeeded: Bool) throws {
        guard isTrusted(promptIfNeeded: promptIfNeeded) else {
            throw WalkieError.accessibilityPermissionDenied
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
