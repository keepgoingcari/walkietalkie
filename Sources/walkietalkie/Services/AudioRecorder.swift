import AVFoundation
import Foundation

actor AudioRecorder {
    private var engine: AVAudioEngine?
    private var outputFile: AVAudioFile?
    private var outputURL: URL?
    private var startedAt: Date?

    func start() async throws {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else {
            throw WalkieError.missingMicrophonePermission
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("walkietalkie-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let file = try AVAudioFile(forWriting: tmpURL, settings: format.settings)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            do {
                try file.write(from: buffer)
            } catch {
                // Keep capture alive even on transient write failures.
            }
        }

        self.engine = engine
        self.outputFile = file
        self.outputURL = tmpURL
        self.startedAt = Date()

        try engine.start()
    }

    func stop() throws -> URL {
        guard let engine, let outputURL, let startedAt else {
            throw WalkieError.nothingRecorded
        }

        engine.stop()
        engine.inputNode.removeTap(onBus: 0)

        self.engine = nil
        self.outputFile = nil
        self.startedAt = nil
        self.outputURL = nil

        if Date().timeIntervalSince(startedAt) < 0.15 {
            throw WalkieError.nothingRecorded
        }
        return outputURL
    }

    func cancelAndDiscard() {
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        engine = nil
        outputFile = nil
        outputURL = nil
        startedAt = nil
    }
}
