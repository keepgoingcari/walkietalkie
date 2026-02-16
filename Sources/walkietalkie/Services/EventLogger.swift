import AppKit
import Foundation

actor EventLogger {
    static let shared = EventLogger()

    private let fileManager = FileManager.default
    private let dateFormatter: ISO8601DateFormatter

    init() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.dateFormatter = formatter
    }

    func log(_ event: String, fields: [String: String] = [:]) {
        let timestamp = dateFormatter.string(from: Date())
        let merged = fields
            .map { "\($0.key)=\($0.value.replacingOccurrences(of: "\n", with: "\\n"))" }
            .sorted()
            .joined(separator: " ")
        let line = merged.isEmpty ? "[\(timestamp)] \(event)\n" : "[\(timestamp)] \(event) \(merged)\n"

        do {
            let url = try logFileURL()
            if !fileManager.fileExists(atPath: url.path()) {
                try Data().write(to: url)
            }
            if let data = line.data(using: .utf8),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            }
        } catch {
            // Avoid surfacing logger failures into runtime flow.
        }
    }

    func revealInFinder() throws {
        let url = try logFileURL()
        if !fileManager.fileExists(atPath: url.path()) {
            try Data().write(to: url)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func logURL() throws -> URL {
        try logFileURL()
    }

    private func logFileURL() throws -> URL {
        let base = fileManager.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent(".config/walkietalkie/logs", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("events.log")
    }
}
