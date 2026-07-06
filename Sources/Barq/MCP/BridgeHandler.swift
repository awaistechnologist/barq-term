import Foundation
import AppKit

enum BridgeError: LocalizedError {
    case unknownMethod(String)
    case missingParam(String)
    case profileNotFound(String)
    case sessionNotFound(String)
    case aiNotAllowed(String)
    case transferFailed(String)

    var errorDescription: String? {
        switch self {
        case .unknownMethod(let method): return "Unknown method: \(method)"
        case .missingParam(let name): return "Missing required parameter: \(name)"
        case .profileNotFound(let name): return "No profile named '\(name)'. Use list_profiles to see available profiles."
        case .sessionNotFound(let id): return "No active session with id '\(id)'. Use list_sessions."
        case .aiNotAllowed(let name): return "Profile '\(name)' has AI access disabled. The user can enable it with the AI chip in the Barq sidebar."
        case .transferFailed(let message): return message
        }
    }
}

/// Implements every bridge method. This is the single enforcement point for
/// agent access: profile AI toggles and vault policies are checked here.
final class BridgeHandler {
    private let profiles: ProfileStore
    private let vault: VaultStore
    private let agentName = "MCP client"

    init(profiles: ProfileStore, vault: VaultStore) {
        self.profiles = profiles
        self.vault = vault
    }

    func handle(method: String, params: [String: Any]) async throws -> Any {
        switch method {
        case "ping":
            return ["ok": true, "app": "Barq"]

        // MARK: Profiles

        case "list_profiles":
            return await MainActor.run {
                profiles.profiles.map {
                    [
                        "name": $0.name,
                        "kind": $0.kind.rawValue,
                        "target": $0.target,
                        "tags": $0.tags.joined(separator: ","),
                        "ai_allowed": $0.aiAllowed ? "true" : "false"
                    ]
                }
            }

        case "add_profile":
            let name: String = try require(params, "name")
            let kind = ProfileKind(rawValue: params["kind"] as? String ?? "ssh") ?? .ssh
            var profile = ConnectionProfile()
            profile.name = name
            profile.kind = kind
            profile.host = params["host"] as? String ?? ""
            profile.port = params["port"] as? Int ?? 22
            profile.username = params["username"] as? String ?? ""
            profile.identityFile = params["identity_file"] as? String ?? ""
            if !profile.identityFile.isEmpty { profile.authType = .key }
            profile.serialDevice = params["serial_device"] as? String ?? ""
            profile.baudRate = params["baud_rate"] as? Int ?? 115200
            profile.tags = (params["tags"] as? String ?? "")
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            profile.aiAllowed = false // agents create profiles, users grant access
            let created = profile
            return await MainActor.run {
                profiles.upsert(created)
                return ["created": created.name, "ai_allowed": "false",
                        "note": "AI access is off by default. Ask the user to enable the AI chip on this profile in Barq."]
            }

        case "remove_profile":
            let name: String = try require(params, "name")
            let force = params["force"] as? Bool ?? false
            return try await MainActor.run {
                guard let profile = profiles.profile(named: name) else { throw BridgeError.profileNotFound(name) }
                let active = SessionManager.shared.sessions.filter { $0.profile.id == profile.id && $0.status == .connected }
                if !active.isEmpty && !force {
                    throw BridgeError.transferFailed("Profile '\(name)' has \(active.count) active session(s). Pass force=true to remove anyway.")
                }
                profiles.remove(id: profile.id)
                return ["removed": name]
            }

        // MARK: Sessions

        case "connect":
            let name: String = try require(params, "profile_name")
            return try await MainActor.run {
                guard let profile = profiles.profile(named: name) else { throw BridgeError.profileNotFound(name) }
                guard profile.aiAllowed else { throw BridgeError.aiNotAllowed(name) }
                let session = SessionManager.shared.open(profile: profile, origin: .agent)
                return ["session_id": session.id, "status": session.status.label, "target": profile.target]
            }

        case "list_sessions":
            return await MainActor.run { SessionManager.shared.listing() }

        case "get_status":
            let id: String = try require(params, "session_id")
            return try await MainActor.run {
                guard let session = SessionManager.shared.session(id: id) else { throw BridgeError.sessionNotFound(id) }
                return [
                    "session_id": session.id,
                    "status": session.status.label,
                    "profile": session.profile.name,
                    "cwd": session.currentDirectory ?? ""
                ]
            }

        case "run_command":
            let id: String = try require(params, "session_id")
            let rawCommand: String = try require(params, "command")
            let timeout = params["timeout"] as? Double ?? 30
            try await enforceGuardrails(rawCommand)
            // Vault expansion happens here — secrets are usable, never readable.
            let command = try await vault.expandVariables(in: rawCommand, agent: agentName)
            guard let session = await MainActor.run(body: { SessionManager.shared.session(id: id) }) else {
                throw BridgeError.sessionNotFound(id)
            }
            let result = await session.runCommand(command, timeout: timeout)
            return [
                "output": result.output,
                "exit_code": result.exitCode.map(String.init) ?? "unknown"
            ]

        case "run_on_tag":
            let tag: String = try require(params, "tag")
            let rawCommand: String = try require(params, "command")
            let timeout = params["timeout"] as? Double ?? 30
            try await enforceGuardrails(rawCommand)
            return try await runOnTag(tag: tag, rawCommand: rawCommand, timeout: timeout)

        case "send_input":
            let id: String = try require(params, "session_id")
            let text: String = try require(params, "text")
            let expanded = try await vault.expandVariables(in: text, agent: agentName)
            return try await MainActor.run {
                guard let session = SessionManager.shared.session(id: id) else { throw BridgeError.sessionNotFound(id) }
                session.send(expanded)
                return ["sent": true]
            }

        case "read_output":
            let id: String = try require(params, "session_id")
            let maxBytes = params["max_bytes"] as? Int ?? 8192
            return try await MainActor.run {
                guard let session = SessionManager.shared.session(id: id) else { throw BridgeError.sessionNotFound(id) }
                return ["output": session.readOutput(maxBytes: maxBytes)]
            }

        case "disconnect":
            let id: String = try require(params, "session_id")
            return await MainActor.run {
                SessionManager.shared.close(id: id)
                return ["closed": id]
            }

        case "list_serial_ports":
            return SerialBackend.availablePorts()

        // MARK: File transfer

        case "upload_file", "download_file":
            let name: String = try require(params, "profile_name")
            let localPath: String = try require(params, "local_path")
            let remotePath: String = try require(params, "remote_path")
            let upload = method == "upload_file"
            guard let profile = await MainActor.run(body: { profiles.profile(named: name) }) else {
                throw BridgeError.profileNotFound(name)
            }
            guard profile.aiAllowed else { throw BridgeError.aiNotAllowed(name) }
            let args = SSHCommandBuilder.scpArguments(
                for: profile, localPath: localPath, remotePath: remotePath, upload: upload
            )
            let result = try await runProcess("/usr/bin/scp", args: args, timeout: 120)
            if result.exitCode != 0 {
                throw BridgeError.transferFailed("scp failed (exit \(result.exitCode)): \(result.stderr)")
            }
            return ["transferred": true, "direction": upload ? "upload" : "download"]

        // MARK: Context Vault

        case "vault_list":
            return await MainActor.run { vault.discoveryListing() }

        case "vault_get":
            let name: String = try require(params, "name")
            let value = try await vault.agentRead(name: name, agent: agentName)
            return ["name": name, "value": value]

        case "vault_set":
            let name: String = try require(params, "name")
            let value: String = try require(params, "value")
            let summary = params["description"] as? String ?? ""
            let policy = VaultPolicy(rawValue: params["policy"] as? String ?? "open") ?? .open
            return try await MainActor.run {
                _ = try vault.set(name: name, value: value, summary: summary, policy: policy)
                return ["stored": name, "policy": policy.rawValue]
            }

        default:
            throw BridgeError.unknownMethod(method)
        }
    }

    private func require<T>(_ params: [String: Any], _ key: String) throws -> T {
        guard let value = params[key] as? T else { throw BridgeError.missingParam(key) }
        return value
    }

    /// Prompt for confirmation on destructive agent commands when guardrails
    /// are enabled. Throws (refusing the command) if the user denies.
    private func enforceGuardrails(_ command: String) async throws {
        guard await MainActor.run(body: { SettingsStore.shared.agentGuardrails }) else { return }
        guard case .dangerous(let reason) = CommandGuard.classify(command) else { return }
        let approved = await MainActor.run { () -> Bool in
            let alert = NSAlert()
            alert.messageText = "Allow agent to run a dangerous command?"
            alert.informativeText = "Agent \"\(agentName)\" wants to run:\n\n\(command)\n\nDetected: \(reason)."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Allow")
            alert.addButton(withTitle: "Deny")
            NSApp.activate(ignoringOtherApps: true)
            return alert.runModal() == .alertFirstButtonReturn
        }
        if !approved {
            throw BridgeError.transferFailed("Command denied by the user (guardrail: \(reason)).")
        }
    }

    /// Fleet op: open (or reuse) a session for every AI-allowed profile that
    /// carries `tag`, run the command on each, and aggregate the results.
    private func runOnTag(tag: String, rawCommand: String, timeout: Double) async throws -> Any {
        let upperTag = tag.uppercased()
        let matching = await MainActor.run {
            profiles.profiles.filter { $0.aiAllowed && $0.tags.contains(upperTag) }
        }
        guard !matching.isEmpty else {
            throw BridgeError.transferFailed("No AI-allowed profiles carry the tag '\(upperTag)'. Enable the AI chip on the relevant hosts first.")
        }
        var results: [[String: String]] = []
        for profile in matching {
            let command = try await vault.expandVariables(in: rawCommand, agent: agentName)
            let session = await MainActor.run { SessionManager.shared.open(profile: profile, origin: .agent) }
            // Give the connection a moment to establish.
            try? await Task.sleep(nanoseconds: 900_000_000)
            let result = await session.runCommand(command, timeout: timeout)
            results.append([
                "profile": profile.name,
                "target": profile.target,
                "exit_code": result.exitCode.map(String.init) ?? "unknown",
                "output": result.output
            ])
        }
        return ["tag": upperTag, "hosts": String(matching.count), "results": results]
    }

    private func runProcess(_ path: String, args: [String], timeout: TimeInterval) async throws -> (exitCode: Int32, stdout: String, stderr: String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err

            let timer = DispatchWorkItem { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)

            process.terminationHandler = { proc in
                timer.cancel()
                let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: (proc.terminationStatus, stdout, stderr))
            }
            do {
                try process.run()
            } catch {
                timer.cancel()
                continuation.resume(throwing: error)
            }
        }
    }
}
