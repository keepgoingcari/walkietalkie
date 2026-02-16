import Foundation

protocol LLMProvider: Sendable {
    func partnerConversation(transcribedRequest: String) async throws -> String
    func condensePrompt(transcribedRequest: String, partnerOutput: String) async throws -> String
}

struct MockLLMProvider: LLMProvider {
    func partnerConversation(transcribedRequest: String) async throws -> String {
        return """
        Partner analysis:
        - Interpreted coding intent from spoken request.
        - Identified likely constraints and defaults.
        - Filled in missing assumptions conservatively.
        """
    }

    func condensePrompt(transcribedRequest: String, partnerOutput: String) async throws -> String {
        return """
        Goal:
        \(transcribedRequest)

        Constraints:
        - Preserve existing behavior unless explicitly requested.
        - Prefer minimal, testable changes.

        Repo assumptions:
        - Infer project language and tooling from files.

        Acceptance criteria:
        - Implement requested behavior end-to-end.
        - Add/update tests for affected paths.
        - Summarize changed files and verification steps.

        Additional context from partner:
        \(partnerOutput)
        """
    }
}

struct OpenAILLMProvider: LLMProvider {
    let apiKey: String
    let model: String

    func partnerConversation(transcribedRequest: String) async throws -> String {
        let instructions = "You are an engineering partner. Explore the user request and infer missing details with minimal clarifying questions unless critical. Return concise bullet points only."
        return try await askOpenAI(input: transcribedRequest, instructions: instructions)
    }

    func condensePrompt(transcribedRequest: String, partnerOutput: String) async throws -> String {
        let instructions = "Convert the material into one concise prompt optimized for coding LLMs in terminal TUIs. Include: goal, constraints, repo assumptions, files if mentioned, acceptance criteria. Output plain text only."
        let composedInput = "User request:\n\(transcribedRequest)\n\nPartner notes:\n\(partnerOutput)"
        return try await askOpenAI(input: composedInput, instructions: instructions)
    }

    private func askOpenAI(input: String, instructions: String) async throws -> String {
        struct RequestBody: Encodable {
            let model: String
            let instructions: String
            let input: String
        }

        struct ResponseBody: Decodable {
            struct OutputItem: Decodable {
                struct Content: Decodable {
                    let type: String?
                    let text: String?
                }
                let content: [Content]?
            }
            let output: [OutputItem]?
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RequestBody(model: model, instructions: instructions, input: input))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw WalkieError.injectionBlocked("LLM request failed: \(body)")
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        let text = decoded.output?
            .flatMap { $0.content ?? [] }
            .compactMap { $0.text }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let text, !text.isEmpty else {
            throw WalkieError.injectionBlocked("LLM returned no text")
        }
        return text
    }
}

enum LLMFactory {
    static func make(config: LLMConfig) throws -> LLMProvider {
        switch config.provider.lowercased() {
        case "mock":
            return MockLLMProvider()
        case "openai":
            guard let key = APIKeyResolver.resolveOpenAIKey(envVar: config.openAIAPIKeyEnv), !key.isEmpty else {
                throw WalkieError.missingAPIKey(config.openAIAPIKeyEnv)
            }
            return OpenAILLMProvider(apiKey: key, model: config.model)
        default:
            throw WalkieError.injectionBlocked("Unknown LLM provider '\(config.provider)'")
        }
    }
}
