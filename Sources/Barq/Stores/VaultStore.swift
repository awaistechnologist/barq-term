import Foundation
import AppKit
import Combine

enum VaultError: LocalizedError {
    case invalidName(String)
    case notFound(String)
    case denied(String)
    case secretValue(String)
    case keychainFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidName(let name):
            return "Invalid vault variable name '\(name)'. Use UPPER_SNAKE_CASE (e.g. STAGING_IP)."
        case .notFound(let name):
            return "Vault variable '\(name)' does not exist."
        case .denied(let name):
            return "Access to vault variable '\(name)' was denied by the user."
        case .secretValue(let name):
            return "Vault variable '\(name)' is a secret. Its value can be used inside commands via ${BARQ:\(name)} but is never returned in plaintext."
        case .keychainFailed(let name):
            return "Failed to store vault variable '\(name)' in the macOS Keychain."
        }
    }
}

/// The Context Vault: named variables (endpoints, IPs, tokens, device facts)
/// that are discoverable across the system — including by other AI agents over
/// MCP — with per-variable read policies. Values live in the macOS Keychain.
final class VaultStore: ObservableObject {
    @Published private(set) var items: [VaultItem] = []

    private let fileURL: URL

    /// Records every agent access for the audit trail.
    @Published private(set) var auditLog: [VaultAuditEntry] = []

    init(fileURL: URL = AppPaths.vaultFile) {
        self.fileURL = fileURL
        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else { return }
        do {
            items = try JSONDecoder().decode([VaultItem].self, from: data)
        } catch {
            StoreBackup.backup(fileURL)
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func item(named name: String) -> VaultItem? {
        items.first { $0.name == name }
    }

    @discardableResult
    func set(name: String, value: String, summary: String, policy: VaultPolicy, scope: VaultScope = .global) throws -> VaultItem {
        guard VaultItem.isValidName(name) else { throw VaultError.invalidName(name) }
        // Surface Keychain failures instead of silently "storing" nothing.
        guard Keychain.set(value, for: "vault.\(name)") else { throw VaultError.keychainFailed(name) }
        if var existing = item(named: name) {
            existing.summary = summary
            existing.policy = policy
            existing.scope = scope
            existing.updatedAt = Date()
            items = items.map { $0.name == name ? existing : $0 }
            save()
            return existing
        }
        let item = VaultItem(name: name, summary: summary, policy: policy, scope: scope)
        items.append(item)
        save()
        return item
    }

    func remove(name: String) {
        Keychain.delete("vault.\(name)")
        items.removeAll { $0.name == name }
        save()
    }

    /// Direct value read for the app UI (owner access, no policy check).
    func value(of name: String) -> String? {
        Keychain.get("vault.\(name)")
    }

    // MARK: Agent-facing access (policy enforced)

    /// Value read on behalf of an AI agent. Enforces the item's policy;
    /// `.approval` items block on a native prompt.
    /// `@MainActor` so reads of `items`/Keychain never race the UI (which
    /// mutates the store on the main thread).
    @MainActor
    func agentRead(name: String, agent: String) async throws -> String {
        guard let item = item(named: name) else { throw VaultError.notFound(name) }
        switch item.policy {
        case .open:
            audit(name: name, agent: agent, action: "read", allowed: true)
            guard let value = value(of: name) else { throw VaultError.notFound(name) }
            return value
        case .secret:
            audit(name: name, agent: agent, action: "read", allowed: false)
            throw VaultError.secretValue(name)
        case .approval:
            let approved = await requestApproval(item: item, agent: agent)
            audit(name: name, agent: agent, action: "read", allowed: approved)
            guard approved else { throw VaultError.denied(name) }
            guard let value = value(of: name) else { throw VaultError.notFound(name) }
            return value
        }
    }

    /// Expand `${BARQ:NAME}` references inside a command string on behalf of an
    /// agent. Secrets ARE expanded (that is the whole point — usable, not
    /// readable); approval items prompt; unknown names throw.
    @MainActor
    func expandVariables(in command: String, agent: String) async throws -> String {
        var result = command
        let regex = try NSRegularExpression(pattern: #"\$\{BARQ:([A-Z][A-Z0-9_]*)\}"#)
        let matches = regex.matches(in: command, range: NSRange(command.startIndex..., in: command))
        var names = Set<String>()
        for match in matches {
            if let range = Range(match.range(at: 1), in: command) {
                names.insert(String(command[range]))
            }
        }
        for name in names {
            guard let item = item(named: name) else { throw VaultError.notFound(name) }
            if item.policy == .approval {
                let approved = await requestApproval(item: item, agent: agent, forUse: true)
                audit(name: name, agent: agent, action: "use", allowed: approved)
                guard approved else { throw VaultError.denied(name) }
            } else {
                audit(name: name, agent: agent, action: "use", allowed: true)
            }
            guard let value = value(of: name) else { throw VaultError.notFound(name) }
            result = result.replacingOccurrences(of: "${BARQ:\(name)}", with: value)
        }
        return result
    }

    /// Redact every `secret`-policy value from a string before it is returned
    /// to an agent over the bridge. This is the defense-in-depth backstop for
    /// the "secrets are usable but never readable" guarantee: even if a secret
    /// is echoed by the remote shell or printed by the command itself, it is
    /// scrubbed from `run_command` / `read_output` / `run_on_tag` output.
    @MainActor
    func redactSecrets(in text: String) -> String {
        var result = text
        for item in items where item.policy == .secret {
            guard let value = value(of: item.name), value.count >= 3 else { continue }
            result = result.replacingOccurrences(of: value, with: "‹redacted:\(item.name)›")
        }
        return result
    }

    /// Record a guardrail decision (dangerous agent command allowed/denied) in
    /// the same audit trail as vault access.
    func logGuardrail(agent: String, command: String, reason: String, allowed: Bool) {
        audit(name: "cmd:\(reason)", agent: agent, action: allowed ? "allow-dangerous" : "deny-dangerous", allowed: allowed)
    }

    @MainActor
    private func approvalAlert(item: VaultItem, agent: String, forUse: Bool) -> Bool {
        let alert = NSAlert()
        alert.messageText = forUse
            ? "Allow agent to use \(item.name)?"
            : "Allow agent to read \(item.name)?"
        alert.informativeText = """
        Agent "\(agent)" wants to \(forUse ? "use" : "read") the vault variable \(item.name)\
        \(item.summary.isEmpty ? "" : " (\(item.summary))").
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: forUse ? "Allow Use" : "Allow Read")
        alert.addButton(withTitle: "Deny")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func requestApproval(item: VaultItem, agent: String, forUse: Bool = false) async -> Bool {
        await MainActor.run { approvalAlert(item: item, agent: agent, forUse: forUse) }
    }

    private func audit(name: String, agent: String, action: String, allowed: Bool) {
        let entry = VaultAuditEntry(date: Date(), agent: agent, variable: name, action: action, allowed: allowed)
        appendAuditLine(entry)
        DispatchQueue.main.async {
            self.auditLog.append(entry)
            if self.auditLog.count > 500 { self.auditLog.removeFirst(self.auditLog.count - 500) }
        }
    }

    /// Append-only on-disk audit trail so agent access survives restarts and the
    /// in-memory 500-entry cap can't erase forensic history.
    private func appendAuditLine(_ entry: VaultAuditEntry) {
        let iso = ISO8601DateFormatter().string(from: entry.date)
        let line = "\(iso)\t\(entry.agent)\t\(entry.action)\t\(entry.variable)\t\(entry.allowed ? "allowed" : "denied")\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = auditFileURL
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    private var auditFileURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("vault-audit.log")
    }

    /// Agent-facing discovery listing: names, descriptions and policies —
    /// never values.
    func discoveryListing() -> [[String: String]] {
        items.map {
            [
                "name": $0.name,
                "description": $0.summary,
                "policy": $0.policy.rawValue,
                "usage": "${BARQ:\($0.name)}"
            ]
        }
    }
}

struct VaultAuditEntry: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let agent: String
    let variable: String
    let action: String
    let allowed: Bool
}
