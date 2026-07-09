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
    @State private var recommendation: ModelRecommendation?
    @State private var installing = false
    @State private var installProgress = ""
    private var installed: [String] { ai.availableOllamaModels }

    private func install(_ model: String) {
        installing = true
        installProgress = "Starting…"
        OllamaSetup.pull(model, progress: { installProgress = $0 }) { ok, msg in
            installing = false
            installProgress = msg
            if ok {
                settings.ollamaModel = model
                Task { await ai.refreshOllama() }
            }
        }
    }

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
                Section("Recommended for this Mac") {
                    if let rec = recommendation {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rec.model).font(.system(.body, design: .monospaced)).bold()
                            Text(rec.reason).font(.system(size: 11)).foregroundStyle(.secondary)
                            Text("Source: \(rec.source)").font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                        if installed.contains(where: { $0.hasPrefix(rec.model) }) {
                            Label("Installed — selected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green).font(.system(size: 11))
                        } else if installing {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(installProgress).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                            }
                        } else {
                            Button("Download & Use \(rec.model)") { install(rec.model) }
                        }
                    } else {
                        Button {
                            Task { recommendation = await ModelAdvisor.recommend() }
                        } label: {
                            Label("Suggest the best model for this Mac", systemImage: "wand.and.stars")
                        }
                        Text("\(ModelAdvisor.physicalRAMGB) GB detected. Uses llm-checker if installed, otherwise Barq's built-in advisor.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
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
    @State private var codeRegistered: String?

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
            Section("Guardrails") {
                Toggle("Confirm dangerous agent commands", isOn: $settings.agentGuardrails)
                Text("When on, an agent running a destructive command (rm -rf, mkfs, force push, database drops, pipe-to-shell, power changes…) triggers a native approval prompt before it executes.")
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
                HStack {
                    Button("Register in Claude Code") { registerClaudeCode() }
                    if let codeRegistered {
                        Text(codeRegistered)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Claude Code equivalent:  claude mcp add barq \(serverBinaryPath) -s user")
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

    /// Register with Claude Code by invoking its CLI, which edits ~/.claude.json
    /// safely (that file holds a lot of state — we don't hand-edit it).
    private func registerClaudeCode() {
        codeRegistered = "Registering…"
        let path = serverBinaryPath
        DispatchQueue.global(qos: .userInitiated).async {
            let result: String
            if let claude = locateClaudeCLI() {
                // Re-add cleanly so an existing entry is refreshed to this path.
                run(claude, ["mcp", "remove", "barq", "-s", "user"])
                let (status, output) = run(claude, ["mcp", "add", "barq", path, "-s", "user"])
                result = status == 0
                    ? "Registered ✓ — restart Claude Code (or /mcp)"
                    : "Failed: \(output.isEmpty ? "claude mcp add exited \(status)" : output)"
            } else {
                result = "Couldn't find the `claude` CLI — copy the command below into a terminal."
            }
            DispatchQueue.main.async { codeRegistered = result }
        }
    }
}

/// Locate the `claude` CLI from a GUI app (which has a minimal PATH).
private func locateClaudeCLI() -> String? {
    let fm = FileManager.default
    let candidates = [
        "\(NSHomeDirectory())/.claude/local/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "\(NSHomeDirectory())/.local/bin/claude",
    ]
    for candidate in candidates where fm.isExecutableFile(atPath: candidate) { return candidate }
    // Fall back to a login shell so user PATH customizations are honored.
    let (status, output) = run("/bin/zsh", ["-lc", "command -v claude"])
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    return (status == 0 && fm.isExecutableFile(atPath: trimmed)) ? trimmed : nil
}

@discardableResult
private func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    } catch {
        return (-1, error.localizedDescription)
    }
}
