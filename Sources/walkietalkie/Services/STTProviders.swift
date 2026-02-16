import Foundation

protocol STTProvider: Sendable {
    func transcribe(audioURL: URL) async throws -> String
}

struct MockSTTProvider: STTProvider {
    func transcribe(audioURL: URL) async throws -> String {
        return "[mock transcript] Captured audio at \(audioURL.lastPathComponent)."
    }
}

struct OpenAIWhisperSTTProvider: STTProvider {
    let apiKey: String
    let model: String

    func transcribe(audioURL: URL) async throws -> String {
        await EventLogger.shared.log("stt.request.begin", fields: [
            "provider": "openai",
            "model": model,
            "audio_path": audioURL.path
        ])

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioURL)
        var body = Data()

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "unknown response"
            await EventLogger.shared.log("stt.request.error", fields: [
                "provider": "openai",
                "status": (response as? HTTPURLResponse).map { "\($0.statusCode)" } ?? "unknown",
                "body": String(bodyText.prefix(350))
            ])
            throw WalkieError.injectionBlocked("STT request failed: \(bodyText)")
        }

        struct Payload: Decodable { let text: String }
        let text = try JSONDecoder().decode(Payload.self, from: data).text
        await EventLogger.shared.log("stt.request.ok", fields: [
            "provider": "openai",
            "status": "\(http.statusCode)",
            "text_chars": "\(text.count)"
        ])
        return text
    }
}

enum STTFactory {
    static func make(config: STTConfig) throws -> STTProvider {
        switch config.provider.lowercased() {
        case "mock":
            return MockSTTProvider()
        case "openai":
            guard let key = APIKeyResolver.resolveOpenAIKey(envVar: config.openAIAPIKeyEnv), !key.isEmpty else {
                throw WalkieError.missingAPIKey(config.openAIAPIKeyEnv)
            }
            return OpenAIWhisperSTTProvider(apiKey: key, model: config.openAIModel)
        default:
            throw WalkieError.injectionBlocked("Unknown STT provider '\(config.provider)'")
        }
    }
}
