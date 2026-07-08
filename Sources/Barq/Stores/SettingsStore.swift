import Foundation
import Combine

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case ollama
    case openrouter

    var id: String { rawValue }
    var label: String {
        switch self {
        case .ollama: return "Ollama (local)"
        case .openrouter: return "OpenRouter"
        }
    }
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    @Published var themeID: String {
        didSet { defaults.set(themeID, forKey: "themeID") }
    }
    @Published var fontName: String {
        didSet { defaults.set(fontName, forKey: "fontName") }
    }
    @Published var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: "fontSize") }
    }
    @Published var useMetalRenderer: Bool {
        didSet { defaults.set(useMetalRenderer, forKey: "useMetalRenderer") }
    }
    @Published var shellPath: String {
        didSet { defaults.set(shellPath, forKey: "shellPath") }
    }
    @Published var aiProvider: AIProvider {
        didSet { defaults.set(aiProvider.rawValue, forKey: "aiProvider") }
    }
    @Published var ollamaBaseURL: String {
        didSet { defaults.set(ollamaBaseURL, forKey: "ollamaBaseURL") }
    }
    @Published var ollamaModel: String {
        didSet { defaults.set(ollamaModel, forKey: "ollamaModel") }
    }
    @Published var openRouterModel: String {
        didSet { defaults.set(openRouterModel, forKey: "openRouterModel") }
    }
    @Published var mcpEnabled: Bool {
        didSet { defaults.set(mcpEnabled, forKey: "mcpEnabled") }
    }
    /// When on, dangerous agent commands require a native approval prompt.
    @Published var agentGuardrails: Bool {
        didSet { defaults.set(agentGuardrails, forKey: "agentGuardrails") }
    }

    /// OpenRouter API key lives in the Keychain, not UserDefaults.
    var openRouterKey: String? {
        get { Keychain.get("openrouter.apikey") }
        set {
            if let newValue, !newValue.isEmpty {
                Keychain.set(newValue, for: "openrouter.apikey")
            } else {
                Keychain.delete("openrouter.apikey")
            }
            objectWillChange.send()
        }
    }

    private init() {
        themeID = defaults.string(forKey: "themeID") ?? Themes.catppuccinMocha.id
        fontName = defaults.string(forKey: "fontName") ?? "Menlo"
        fontSize = defaults.object(forKey: "fontSize") as? Double ?? 13.0
        useMetalRenderer = defaults.object(forKey: "useMetalRenderer") as? Bool ?? false
        shellPath = defaults.string(forKey: "shellPath") ?? (ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        aiProvider = AIProvider(rawValue: defaults.string(forKey: "aiProvider") ?? "") ?? .ollama
        ollamaBaseURL = defaults.string(forKey: "ollamaBaseURL") ?? "http://127.0.0.1:11434"
        ollamaModel = defaults.string(forKey: "ollamaModel") ?? ""
        openRouterModel = defaults.string(forKey: "openRouterModel") ?? "anthropic/claude-sonnet-4.5"
        mcpEnabled = defaults.object(forKey: "mcpEnabled") as? Bool ?? true
        agentGuardrails = defaults.object(forKey: "agentGuardrails") as? Bool ?? true
    }

    var theme: BarqTheme { Themes.theme(id: themeID) }
}
