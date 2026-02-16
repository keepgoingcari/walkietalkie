import AVFoundation
import Foundation

enum WalkieCLI {
    static func run(arguments: [String]) -> Int32 {
        guard let command = arguments.first else {
            printHelp()
            return 0
        }

        do {
            switch command {
            case "setup":
                try setupWizard()
                return 0
            case "doctor":
                try doctor()
                return 0
            case "logs":
                try logs(arguments: Array(arguments.dropFirst()))
                return 0
            case "help", "--help", "-h":
                printHelp()
                return 0
            default:
                print("Unknown command: \(command)\n")
                printHelp()
                return 2
            }
        } catch {
            print("Error: \(error.localizedDescription)")
            return 1
        }
    }

    private static func setupWizard() throws {
        let current = (try? loadConfig()) ?? WalkieConfig.default
        var next = current

        print("walkietalkie setup")
        print("----------------")

        let useOpenAI = askBool(prompt: "Use OpenAI for STT + agent?", defaultValue: true)
        if useOpenAI {
            next.stt.provider = "openai"
            next.llm.provider = "openai"

            let keyPrompt = "Enter OpenAI API key (leave blank to keep existing keychain/env):"
            let key = askString(prompt: keyPrompt, defaultValue: "")
            if !key.isEmpty {
                try KeychainStore.set(key, account: APIKeyResolver.openAIAccount)
                print("Saved API key in macOS Keychain.")
            }
        } else {
            next.stt.provider = "mock"
            next.llm.provider = "mock"
        }

        print("\nHotkeys format: modifier+modifier+key (example: control+option+space)")
        let dictationDefault = stringify(next.hotkeys.dictation)
        let dictationString = askString(prompt: "Dictation hotkey", defaultValue: dictationDefault)
        next.hotkeys.dictation = try parseHotkey(from: dictationString)

        let agentDefault = stringify(next.hotkeys.agent)
        let agentString = askString(prompt: "Agent hotkey", defaultValue: agentDefault)
        next.hotkeys.agent = try parseHotkey(from: agentString)

        next.modeBehavior.dictation.autoEnter = askBool(prompt: "Dictation auto-press Enter after paste?", defaultValue: next.modeBehavior.dictation.autoEnter)
        next.modeBehavior.agent.autoEnter = askBool(prompt: "Agent mode auto-press Enter after paste?", defaultValue: next.modeBehavior.agent.autoEnter)

        let injectAnywhere = askBool(prompt: "Allow injection in any focused app?", defaultValue: next.injection.injectAnywhere)
        next.injection.injectAnywhere = injectAnywhere
        if !injectAnywhere {
            let existing = next.injection.allowlistBundleIDs.joined(separator: ",")
            let raw = askString(prompt: "Allowlist bundle IDs (comma-separated)", defaultValue: existing)
            next.injection.allowlistBundleIDs = raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        try saveConfig(next)

        print("\nSetup complete.")
        print("Config: \(try configURL().path)")
        print("Next: run 'walkietalkie' with no arguments to launch menu bar app.")
    }

    private static func doctor() throws {
        let config = try loadConfig()

        print("walkietalkie doctor")
        print("-------------------")
        print("Config path: \(try configURL().path)")
        print("Logs path:   \(try logsURL().path)")
        print("STT provider: \(config.stt.provider)")
        print("LLM provider: \(config.llm.provider)")
        print("Accessibility trusted: \(AccessibilityService.isTrusted(promptIfNeeded: false))")

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        print("Microphone status: \(micStatusDescription(micStatus))")

        let hasKeychainKey = !(KeychainStore.get(account: APIKeyResolver.openAIAccount) ?? "").isEmpty
        let hasEnvKey = !(ProcessInfo.processInfo.environment[config.stt.openAIAPIKeyEnv] ?? "").isEmpty
        print("OpenAI key (keychain): \(hasKeychainKey)")
        print("OpenAI key (env \(config.stt.openAIAPIKeyEnv)): \(hasEnvKey)")

        print("Dictation hotkey: \(stringify(config.hotkeys.dictation))")
        print("Agent hotkey: \(stringify(config.hotkeys.agent))")
    }

    private static func logs(arguments: [String]) throws {
        let url = try logsURL()

        let tailLines: Int
        if arguments.count >= 2, arguments[0] == "--tail" {
            tailLines = Int(arguments[1]) ?? 80
        } else {
            tailLines = 80
        }

        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        let start = max(0, lines.count - tailLines)
        let subset = lines[start...]
        print(subset.joined(separator: "\n"))
    }

    private static func configURL() throws -> URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent(".config/walkietalkie", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    private static func logsURL() throws -> URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent(".config/walkietalkie/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("events.log")
        if !FileManager.default.fileExists(atPath: file.path) {
            try Data().write(to: file)
        }
        return file
    }

    private static func loadConfig() throws -> WalkieConfig {
        let url = try configURL()
        if !FileManager.default.fileExists(atPath: url.path) {
            try saveConfig(.default)
            return .default
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(WalkieConfig.self, from: data)
    }

    private static func saveConfig(_ config: WalkieConfig) throws {
        _ = try HotkeyParser.parse(config.hotkeys.dictation)
        _ = try HotkeyParser.parse(config.hotkeys.agent)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configURL(), options: .atomic)
    }

    private static func parseHotkey(from input: String) throws -> HotkeyConfig {
        let parts = input
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard let key = parts.last else {
            throw WalkieError.invalidHotkey("empty hotkey")
        }

        let modifiers = Array(parts.dropLast())
        let hotkey = HotkeyConfig(key: key, modifiers: modifiers)
        _ = try HotkeyParser.parse(hotkey)
        return hotkey
    }

    private static func stringify(_ hotkey: HotkeyConfig) -> String {
        (hotkey.modifiers + [hotkey.key]).joined(separator: "+")
    }

    private static func askString(prompt: String, defaultValue: String) -> String {
        let renderedDefault = defaultValue.isEmpty ? "" : " [\(defaultValue)]"
        print("\(prompt)\(renderedDefault): ", terminator: "")
        fflush(stdout)
        guard let line = readLine(), !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultValue
        }
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func askBool(prompt: String, defaultValue: Bool) -> Bool {
        let defaultMarker = defaultValue ? "Y/n" : "y/N"
        print("\(prompt) (\(defaultMarker)): ", terminator: "")
        fflush(stdout)
        guard let line = readLine() else { return defaultValue }
        let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty { return defaultValue }
        if ["y", "yes", "true", "1"].contains(normalized) { return true }
        if ["n", "no", "false", "0"].contains(normalized) { return false }
        return defaultValue
    }

    private static func micStatusDescription(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        @unknown default: return "unknown"
        }
    }

    private static func printHelp() {
        print("""
        walkietalkie commands:
          walkietalkie setup            Run onboarding wizard
          walkietalkie doctor           Show config + permission diagnostics
          walkietalkie logs [--tail N]  Print recent interaction logs
          walkietalkie                  Launch menu bar app
        """)
    }
}
