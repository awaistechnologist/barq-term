import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            AISettings()
                .tabItem { Label("AI", systemImage: "sparkles") }
            MCPSettings()
                .tabItem { Label("MCP", systemImage: "point.3.connected.trianglepath.dotted") }
        }
        .frame(width: 560, height: 460)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.themeID) {
                    ForEach(Themes.all) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                TextField("Font", text: $settings.fontName)
                Slider(value: $settings.fontSize, in: 9...22, step: 1) {
                    Text("Font size: \(Int(settings.fontSize))")
                }
                Toggle("GPU rendering (Metal)", isOn: $settings.useMetalRenderer)
                Text("Theme and font changes apply to new terminals.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Section("Shell") {
                TextField("Shell path", text: $settings.shellPath)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .formStyle(.grouped)
    }
}

private struct AISettings: View {
    @ObservedObject var settings = SettingsStore.shared
    @ObservedObject var ai = AIService.shared
    @State private var keyField = ""

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Provider", selection: $settings.aiProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
            }

            if settings.aiProvider == .ollama {
                Section("Ollama — local, private, free") {
                    TextField("Base URL", text: $settings.ollamaBaseURL)
                        .font(.system(.body, design: .monospaced))
                    if ai.ollamaReachable {
                        Picker("Model", selection: $settings.ollamaModel) {
                            ForEach(ai.availableOllamaModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        Label("Connected — \(ai.availableOllamaModels.count) model(s) available", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 11))
                    } else {
                        Label("Ollama not reachable. Install from ollama.com and run `ollama serve`, then refresh.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.system(size: 11))
                    }
                    Button("Refresh models") {
                        Task { await ai.refreshOllama() }
                    }
                }
            } else {
                Section("OpenRouter — bring your own key") {
                    SecureField("API key (stored in Keychain)", text: $keyField)
                        .onSubmit { settings.openRouterKey = keyField }
                    Button("Save key") { settings.openRouterKey = keyField }
                        .disabled(keyField.isEmpty)
                    if settings.openRouterKey?.isEmpty == false {
                        Label("Key saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 11))
                    }
                    TextField("Model", text: $settings.openRouterModel)
                        .font(.system(.body, design: .monospaced))
                    Text("Any OpenRouter model id works, e.g. anthropic/claude-sonnet-4.5")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            keyField = settings.openRouterKey ?? ""
            Task { await ai.refreshOllama() }
        }
    }
}

private struct MCPSettings: View {
    @ObservedObject var settings = SettingsStore.shared
    @State private var copied = false
    @State private var registered: String?

    private var serverBinaryPath: String {
        // Same directory as the app binary (SwiftPM build or app bundle).
        let appPath = Bundle.main.executablePath ?? ""
        return (appPath as NSString).deletingLastPathComponent + "/barq-mcp"
    }

    private var configSnippet: String {
        """
        {
          "mcpServers": {
            "barq": {
              "command": "\(serverBinaryPath)"
            }
          }
        }
        """
    }

    var body: some View {
        Form {
            Section("MCP Server") {
                Toggle("Expose Barq to AI agents (MCP)", isOn: $settings.mcpEnabled)
                Text("AI agents (Claude Desktop, Claude Code, any MCP client) can list profiles, open sessions, run commands, transfer files, and use the Context Vault — always within the per-profile AI toggle and per-variable policies. Restart Barq after changing this.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Section("Register with Claude") {
                Text(configSnippet)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                HStack {
                    Button(copied ? "Copied!" : "Copy config") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(configSnippet, forType: .string)
                        copied = true
                    }
                    Button("Register in Claude Desktop") { registerClaudeDesktop() }
                    if let registered {
                        Text(registered)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Text("For Claude Code:  claude mcp add barq \(serverBinaryPath)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }

    private func registerClaudeDesktop() {
        let configURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Claude/claude_desktop_config.json")
        var config: [String: Any] = [:]
        if let data = try? Data(contentsOf: configURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = existing
        }
        var servers = config["mcpServers"] as? [String: Any] ?? [:]
        servers["barq"] = ["command": serverBinaryPath]
        config["mcpServers"] = servers
        do {
            try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: configURL, options: .atomic)
            registered = "Registered ✓ — restart Claude Desktop"
        } catch {
            registered = "Failed: \(error.localizedDescription)"
        }
    }
}
