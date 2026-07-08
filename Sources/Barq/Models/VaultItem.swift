import Foundation

/// Who may read this variable's *value* over MCP / from AI agents.
enum VaultPolicy: String, Codable, CaseIterable, Identifiable {
    /// Agents can discover and read the value freely.
    case open
    /// Agents can discover it; reading the value pops a native approval prompt.
    case approval
    /// Agents can discover it and *use* it (Barq expands it inside commands),
    /// but the plaintext value is never returned to an agent.
    case secret

    var id: String { rawValue }

    var label: String {
        switch self {
        case .open: return "Open — agents can read"
        case .approval: return "Ask me first"
        case .secret: return "Secret — usable, never readable"
        }
    }

    var symbol: String {
        switch self {
        case .open: return "eye"
        case .approval: return "person.fill.questionmark"
        case .secret: return "lock.fill"
        }
    }
}

enum VaultScope: Codable, Hashable {
    case global
    case profile(UUID)

    var label: String {
        switch self {
        case .global: return "Global"
        case .profile: return "Profile-scoped"
        }
    }
}

/// A named variable in the Context Vault.
///
/// Metadata (name, description, policy, scope) lives in `vault.json`.
/// The value itself always lives in the macOS Keychain — never on disk in plaintext.
struct VaultItem: Codable, Identifiable, Hashable {
    var id = UUID()
    /// UPPER_SNAKE_CASE identifier, unique across the vault. Referenced in
    /// commands as `${BARQ:NAME}`.
    var name: String
    var summary: String = ""
    var policy: VaultPolicy = .approval
    var scope: VaultScope = .global
    var createdAt = Date()
    var updatedAt = Date()

    init(id: UUID = UUID(), name: String, summary: String = "", policy: VaultPolicy = .approval,
         scope: VaultScope = .global, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.name = name; self.summary = summary; self.policy = policy
        self.scope = scope; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, summary, policy, scope, createdAt, updatedAt
    }

    // Resilient: missing keys fall back to defaults so schema changes don't drop items.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? def }
        id = d(.id, UUID())
        name = d(.name, "")
        summary = d(.summary, "")
        policy = d(.policy, .approval)
        scope = d(.scope, .global)
        createdAt = d(.createdAt, Date())
        updatedAt = d(.updatedAt, Date())
    }

    var keychainKey: String { "vault.\(name)" }

    static let namePattern = "^[A-Z][A-Z0-9_]*$"

    static func isValidName(_ name: String) -> Bool {
        name.range(of: namePattern, options: .regularExpression) != nil
    }
}
