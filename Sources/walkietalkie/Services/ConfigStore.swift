import AppKit
import Foundation

actor ConfigStore {
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    func load() throws -> WalkieConfig {
        let path = try configFilePath()
        if !fileManager.fileExists(atPath: path.path()) {
            try writeDefaultConfig(to: path)
            return .default
        }

        let data = try Data(contentsOf: path)
        let config = try decoder.decode(WalkieConfig.self, from: data)
        try validate(config)
        return config
    }

    func configURL() throws -> URL {
        try configFilePath()
    }

    func save(_ config: WalkieConfig) throws {
        try validate(config)
        let path = try configFilePath()
        let data = try encoder.encode(config)
        try data.write(to: path, options: .atomic)
    }

    func revealInFinder() throws {
        let path = try configFilePath()
        NSWorkspace.shared.activateFileViewerSelecting([path])
    }

    private func configFilePath() throws -> URL {
        guard let base = fileManager.homeDirectoryForCurrentUser as URL? else {
            throw WalkieError.injectionBlocked("Cannot resolve home directory")
        }
        let dir = base.appendingPathComponent(".config/walkietalkie", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    private func writeDefaultConfig(to path: URL) throws {
        let data = try encoder.encode(WalkieConfig.default)
        try data.write(to: path, options: .atomic)
    }

    private func validate(_ config: WalkieConfig) throws {
        _ = try HotkeyParser.parse(config.hotkeys.dictation)
        _ = try HotkeyParser.parse(config.hotkeys.agent)
        if config.injection.preInjectHUDMillis < 0 || config.injection.preInjectHUDMillis > 10_000 {
            throw WalkieError.injectionBlocked("injection.preInjectHUDMillis must be between 0 and 10000")
        }
    }
}
