import Foundation

struct AgentTurn: Sendable {
    enum Role: String, Sendable {
        case user
        case assistant
    }
    let role: Role
    let content: String
}

protocol LLMProvider: Sendable {
    func partnerConversation(transcribedRequest: String) async throws -> String
    func condensePrompt(transcribedRequest: String, partnerOutput: String) async throws -> String
    func collaborate(history: [AgentTurn]) async throws -> String
    func condenseConversation(initialRequest: String, history: [AgentTurn]) async throws -> String
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

    func collaborate(history: [AgentTurn]) async throws -> String {
        let latest = history.last(where: { $0.role == .user })?.content ?? ""
        return "Partner pass: refine this by adding explicit constraints, touched files, and test criteria.\nFocus item: \(latest)"
    }

    func condenseConversation(initialRequest: String, history: [AgentTurn]) async throws -> String {
        let conversation = history
            .map { "\($0.role.rawValue): \($0.content)" }
            .joined(separator: "\n")
        return """
        Goal:
        \(initialRequest)

        Conversation Context:
        \(conversation)

        Deliverable:
        Produce one concise coding prompt with constraints, repo assumptions, files if mentioned, and acceptance criteria.
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

    func collaborate(history: [AgentTurn]) async throws -> String {
        let instructions = "You are a concise engineering sparring partner inside a HUD. Build on user ideas, ask only critical clarifications, and provide actionable guidance in 4-8 bullet points."
        let transcript = history
            .suffix(16)
            .map { "\($0.role.rawValue): \($0.content)" }
            .joined(separator: "\n")
        return try await askOpenAI(input: transcript, instructions: instructions)
    }

    func condenseConversation(initialRequest: String, history: [AgentTurn]) async throws -> String {
        let instructions = "Generate one final prompt for a coding LLM in terminal TUI. Include goal, constraints, assumptions, file targets if present, and acceptance criteria. Avoid fluff."
        let transcript = history
            .map { "\($0.role.rawValue): \($0.content)" }
            .joined(separator: "\n")
        let input = "Initial request:\n\(initialRequest)\n\nConversation:\n\(transcript)"
        return try await askOpenAI(input: input, instructions: instructions)
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
