import Foundation

enum WalkieState: Equatable {
    case idle
    case listening(WalkieMode)
    case transcribing(WalkieMode)
    case agentConversation
    case condensing
    case injecting(String)
    case done
    case error(String)

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .listening(let mode): return "Listening (\(mode.rawValue))"
        case .transcribing(let mode): return "Transcribing (\(mode.rawValue))"
        case .agentConversation: return "Agent Conversation"
        case .condensing: return "Condensing"
        case .injecting(let app): return "Injecting into \(app)"
        case .done: return "Done"
        case .error(let err): return "Error: \(err)"
        }
    }
}
