import Foundation

struct AIMessage: Codable, Hashable {
    enum Role: String, Codable {
        case system, user, assistant
    }
    var role: Role
    var content: String
}

enum AIError: LocalizedError {
    case noProvider
    case noModel
    case noAPIKey
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noProvider: return "No AI provider configured. Open Settings → AI."
        case .noModel: return "No model selected. Pick a model in Settings → AI (is Ollama running? `ollama serve`)."
        case .noAPIKey: return "OpenRouter API key missing. Add it in Settings → AI."
        case .http(let code, let body): return "AI request failed (HTTP \(code)): \(body.prefix(300))"
        case .badResponse: return "Unexpected response from the AI provider."
        }
    }
}

protocol AIClient {
    func complete(messages: [AIMessage]) async throws -> String
    func listModels() async throws -> [String]
}

// MARK: - Ollama (local-first default)

struct OllamaClient: AIClient {
    let baseURL: String
    let model: String

    func complete(messages: [AIMessage]) async throws -> String {
        guard !model.isEmpty else { throw AIError.noModel }
        guard let url = URL(string: "\(baseURL)/api/chat") else { throw AIError.badResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.badResponse }
        guard http.statusCode == 200 else {
            throw AIError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = object["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw AIError.badResponse }
        return content
    }

    func listModels() async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        let (data, _) = try await URLSession.shared.data(for: request)
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let models = object["models"] as? [[String: Any]]
        else { return [] }
        return models.compactMap { $0["name"] as? String }
    }
}

// MARK: - OpenRouter (bring-your-own-key)

struct OpenRouterClient: AIClient {
    let apiKey: String
    let model: String

    func complete(messages: [AIMessage]) async throws -> String {
        guard !apiKey.isEmpty else { throw AIError.noAPIKey }
        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else { throw AIError.badResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://github.com/barq-terminal/barq", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Barq Terminal", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 120
        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.badResponse }
        guard http.statusCode == 200 else {
            throw AIError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = object["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw AIError.badResponse }
        return content
    }

    func listModels() async throws -> [String] {
        // Curated defaults; OpenRouter's full catalog is huge.
        [
            "anthropic/claude-sonnet-4.5",
            "anthropic/claude-opus-4.1",
            "anthropic/claude-haiku-4.5",
            "openai/gpt-4o",
            "google/gemini-2.5-pro",
            "meta-llama/llama-4-maverick"
        ]
    }
}
