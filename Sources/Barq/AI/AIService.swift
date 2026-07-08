import Foundation
import Combine

/// Session-aware AI orchestration: builds prompts with terminal context and
/// vault discovery info, and routes to the configured provider.
@MainActor
final class AIService: ObservableObject {
    static let shared = AIService()

    @Published var availableOllamaModels: [String] = []
    @Published var ollamaReachable = false

    private let settings = SettingsStore.shared

    private init() {}

    private func client() throws -> AIClient {
        switch settings.aiProvider {
        case .ollama:
            return OllamaClient(baseURL: settings.ollamaBaseURL, model: settings.ollamaModel)
        case .openrouter:
            guard let key = settings.openRouterKey, !key.isEmpty else { throw AIError.noAPIKey }
            return OpenRouterClient(apiKey: key, model: settings.openRouterModel)
        }
    }

    var providerLabel: String {
        switch settings.aiProvider {
        case .ollama: return settings.ollamaModel.isEmpty ? "Ollama" : "Ollama · \(settings.ollamaModel)"
        case .openrouter: return "OpenRouter · \(settings.openRouterModel)"
        }
    }

    /// Probe Ollama and auto-pick a model when none is set.
    func refreshOllama() async {
        let probe = OllamaClient(baseURL: settings.ollamaBaseURL, model: settings.ollamaModel)
        do {
            let models = try await probe.listModels()
            availableOllamaModels = models
            ollamaReachable = !models.isEmpty
            if settings.ollamaModel.isEmpty, let first = models.first {
                settings.ollamaModel = first
            }
        } catch {
            availableOllamaModels = []
            ollamaReachable = false
        }
    }

    private func environmentContext(session: TerminalSession?) -> String {
        var lines = ["OS: macOS (Apple Silicon), shell: \((SettingsStore.shared.shellPath as NSString).lastPathComponent)"]
        if let session {
            lines.append("Session kind: \(session.profile.kind.rawValue), target: \(session.profile.target)")
            if let cwd = session.resolvedWorkingDirectory {
                lines.append("Current directory: \(cwd)")
            }
            let tail = session.readOutput(maxBytes: 3000)
            if !tail.isEmpty {
                lines.append("Recent terminal output:\n---\n\(tail)\n---")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Natural language → a single shell command (⌘K).
    func generateCommand(instruction: String, session: TerminalSession?) async throws -> String {
        let system = """
        You translate natural-language requests into a single shell command.
        Rules:
        - Output ONLY the command. No backticks, no explanation, no markdown.
        - Prefer safe, non-destructive variants; add flags like -i where sensible.
        - If the request is impossible as one command, output the best single command that helps.
        Context:
        \(environmentContext(session: session))
        """
        let raw = try await client().complete(messages: [
            AIMessage(role: .system, content: system),
            AIMessage(role: .user, content: instruction)
        ])
        return Self.extractCommand(from: raw)
    }

    /// Explain the latest terminal output (errors especially).
    func explain(session: TerminalSession) async throws -> String {
        let system = """
        You are Barq's built-in terminal assistant. Explain what the recent terminal \
        output means, focusing on errors and their fixes. Be concise: a short diagnosis, \
        then the fix as a command if one exists.
        """
        return try await client().complete(messages: [
            AIMessage(role: .system, content: system),
            AIMessage(role: .user, content: environmentContext(session: session))
        ])
    }

    /// Free-form chat with terminal context.
    func chat(history: [AIMessage], session: TerminalSession?) async throws -> String {
        let system = """
        You are Barq's AI assistant, embedded in a macOS terminal (SSH/serial/telnet/local). \
        Help with commands, debugging, and device operations. When you propose a command, \
        put it alone on a line inside a ```sh code block so the user can run it with one click.
        Context:
        \(environmentContext(session: session))
        """
        return try await client().complete(messages: [AIMessage(role: .system, content: system)] + history)
    }

    /// Strip markdown fences/prefixes if the model added them anyway.
    nonisolated static func extractCommand(from raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            let lines = text.components(separatedBy: "\n")
            let body = lines.dropFirst().prefix { !$0.hasPrefix("```") }
            text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.hasPrefix("$ ") { text.removeFirst(2) }
        // A command should be one line; take the first non-empty one.
        return text.components(separatedBy: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? text
    }
}
