import Foundation

enum WalkieMode: String, Codable {
    case dictation
    case agent
}

struct HotkeyConfig: Codable, Sendable {
    var key: String
    var modifiers: [String]
}

struct InjectionConfig: Codable, Sendable {
    var injectAnywhere: Bool
    var allowlistBundleIDs: [String]
    var preInjectHUDMillis: Int
    var usePasteThenOptionalEnter: Bool
    var fallbackToKeystrokesOnFailure: Bool
}

struct ModeBehaviorConfig: Codable, Sendable {
    var autoEnter: Bool
}

struct STTConfig: Codable, Sendable {
    var provider: String
    var openAIAPIKeyEnv: String
    var openAIModel: String
}

struct LLMConfig: Codable, Sendable {
    var provider: String
    var openAIAPIKeyEnv: String
    var model: String
}

struct WalkieConfig: Codable, Sendable {
    var hotkeys: HotkeysConfig
    var injection: InjectionConfig
    var modeBehavior: ModeBehaviorsConfig
    var stt: STTConfig
    var llm: LLMConfig

    static let `default` = WalkieConfig(
        hotkeys: HotkeysConfig(
            dictation: HotkeyConfig(key: "space", modifiers: ["control", "option"]),
            agent: HotkeyConfig(key: "space", modifiers: ["control", "option", "command"])
        ),
        injection: InjectionConfig(
            injectAnywhere: true,
            allowlistBundleIDs: [],
            preInjectHUDMillis: 850,
            usePasteThenOptionalEnter: true,
            fallbackToKeystrokesOnFailure: true
        ),
        modeBehavior: ModeBehaviorsConfig(
            dictation: ModeBehaviorConfig(autoEnter: false),
            agent: ModeBehaviorConfig(autoEnter: false)
        ),
        stt: STTConfig(
            provider: "mock",
            openAIAPIKeyEnv: "OPENAI_API_KEY",
            openAIModel: "gpt-4o-mini-transcribe"
        ),
        llm: LLMConfig(
            provider: "mock",
            openAIAPIKeyEnv: "OPENAI_API_KEY",
            model: "gpt-4.1-mini"
        )
    )
}

struct HotkeysConfig: Codable, Sendable {
    var dictation: HotkeyConfig
    var agent: HotkeyConfig
}

struct ModeBehaviorsConfig: Codable, Sendable {
    var dictation: ModeBehaviorConfig
    var agent: ModeBehaviorConfig
}
