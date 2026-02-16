import Foundation

enum WalkieError: LocalizedError, Equatable {
    case invalidHotkey(String)
    case missingMicrophonePermission
    case failedToStartRecording
    case nothingRecorded
    case injectionBlocked(String)
    case canceled
    case missingAPIKey(String)
    case accessibilityPermissionDenied

    var errorDescription: String? {
        switch self {
        case .invalidHotkey(let msg):
            return "Invalid hotkey: \(msg)"
        case .missingMicrophonePermission:
            return "Microphone permission was not granted."
        case .failedToStartRecording:
            return "Failed to start recording."
        case .nothingRecorded:
            return "No audio captured."
        case .injectionBlocked(let msg):
            return "Injection blocked: \(msg)"
        case .canceled:
            return "Canceled"
        case .missingAPIKey(let env):
            return "Missing API key in env var \(env)."
        case .accessibilityPermissionDenied:
            return "Accessibility permission is required for text injection."
        }
    }
}
