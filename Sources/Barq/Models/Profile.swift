import Foundation

enum ProfileKind: String, Codable, CaseIterable, Identifiable {
    case local
    case ssh
    case serial
    case telnet

    var id: String { rawValue }

    var label: String {
        switch self {
        case .local: return "Local Shell"
        case .ssh: return "SSH"
        case .serial: return "Serial"
        case .telnet: return "Telnet"
        }
    }

    var symbol: String {
        switch self {
        case .local: return "terminal"
        case .ssh: return "network"
        case .serial: return "cable.connector"
        case .telnet: return "point.3.connected.trianglepath.dotted"
        }
    }
}

enum AuthType: String, Codable, CaseIterable, Identifiable {
    case agent
    case password
    case key
    case keyText  // pasted private key, stored in the Keychain

    var id: String { rawValue }

    var label: String {
        switch self {
        case .agent: return "SSH Agent / Ask"
        case .password: return "Password"
        case .key: return "Identity File"
        case .keyText: return "Paste Private Key"
        }
    }
}

enum ForwardKind: String, Codable, CaseIterable, Identifiable {
    case local     // -L
    case remote    // -R
    case dynamic   // -D (SOCKS5)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .local: return "Local (-L)"
        case .remote: return "Remote (-R)"
        case .dynamic: return "Dynamic SOCKS5 (-D)"
        }
    }
}

struct PortForward: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: ForwardKind = .local
    var bindAddress: String = "127.0.0.1"
    var listenPort: Int = 8080
    var targetHost: String = ""
    var targetPort: Int = 80
    var enabled: Bool = true
    /// For dynamic (SOCKS5) rules: how the "Launch Chrome" button filters hosts.
    var filterMode: ProxyFilterMode = .all
    var filterHosts: [String] = []

    init(id: UUID = UUID(), kind: ForwardKind = .local, bindAddress: String = "127.0.0.1",
         listenPort: Int = 8080, targetHost: String = "", targetPort: Int = 80,
         enabled: Bool = true, filterMode: ProxyFilterMode = .all, filterHosts: [String] = []) {
        self.id = id; self.kind = kind; self.bindAddress = bindAddress
        self.listenPort = listenPort; self.targetHost = targetHost; self.targetPort = targetPort
        self.enabled = enabled; self.filterMode = filterMode; self.filterHosts = filterHosts
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, bindAddress, listenPort, targetHost, targetPort, enabled, filterMode, filterHosts
    }

    // Resilient: missing keys (older saved data) fall back to defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? def }
        id = d(.id, UUID())
        kind = d(.kind, .local)
        bindAddress = d(.bindAddress, "127.0.0.1")
        listenPort = d(.listenPort, 8080)
        targetHost = d(.targetHost, "")
        targetPort = d(.targetPort, 80)
        enabled = d(.enabled, true)
        filterMode = d(.filterMode, .all)
        filterHosts = d(.filterHosts, [])
    }

    /// The ssh CLI argument for this rule, e.g. `-L 127.0.0.1:8080:host:80`
    var sshArguments: [String] {
        switch kind {
        case .local:
            return ["-L", "\(bindAddress):\(listenPort):\(targetHost):\(targetPort)"]
        case .remote:
            return ["-R", "\(bindAddress):\(listenPort):\(targetHost):\(targetPort)"]
        case .dynamic:
            return ["-D", "\(bindAddress):\(listenPort)"]
        }
    }
}

struct JumpHost: Codable, Hashable {
    var enabled: Bool = false
    var host: String = ""
    var port: Int = 22
    var username: String = ""
    var identityFile: String = ""

    init() {}
    init(enabled: Bool, host: String, port: Int, username: String, identityFile: String) {
        self.enabled = enabled; self.host = host; self.port = port
        self.username = username; self.identityFile = identityFile
    }

    enum CodingKeys: String, CodingKey { case enabled, host, port, username, identityFile }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? def }
        enabled = d(.enabled, false)
        host = d(.host, "")
        port = d(.port, 22)
        username = d(.username, "")
        identityFile = d(.identityFile, "")
    }

    /// Value for ssh -J
    var proxyJumpValue: String {
        var value = ""
        if !username.isEmpty { value += "\(username)@" }
        value += host
        if port != 22 { value += ":\(port)" }
        return value
    }
}

struct CustomAction: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String = ""
    var command: String = ""

    init() {}

    enum CodingKeys: String, CodingKey { case id, name, command }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? def }
        id = d(.id, UUID())
        name = d(.name, "")
        command = d(.command, "")
    }
}

struct ConnectionProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String = ""
    var kind: ProfileKind = .ssh

    // SSH / Telnet
    var host: String = ""
    var port: Int = 22
    var username: String = ""
    var authType: AuthType = .agent
    var identityFile: String = ""
    var extraSSHOptions: [String] = []
    var agentForward: Bool = false // ssh -A
    var legacySCP: Bool = false // -O + HostKeyAlgorithms=+ssh-rsa for dropbear/BusyBox
    var jumpHost: JumpHost = JumpHost()
    var portForwards: [PortForward] = []
    /// Cloudflare Access: tunnel via `cloudflared access ssh`. Mutually
    /// exclusive with jumpHost.
    var cloudflareAccess: Bool = false

    // Serial
    var serialDevice: String = ""
    var baudRate: Int = 115200
    var dataBits: Int = 8
    var stopBits: Int = 1
    var parity: String = "none" // none | even | odd

    // Local
    var workingDirectory: String = ""

    // Shared
    var tags: [String] = []
    var aiAllowed: Bool = false
    var customActions: [CustomAction] = []
    var notes: String = ""

    init() {}

    enum CodingKeys: String, CodingKey {
        case id, name, kind, host, port, username, authType, identityFile, extraSSHOptions
        case agentForward, legacySCP, jumpHost, portForwards, cloudflareAccess
        case serialDevice, baudRate, dataBits, stopBits, parity, workingDirectory
        case tags, aiAllowed, customActions, notes
    }

    /// Resilient decode: any key missing from older saved data falls back to its
    /// default, so adding a field never wipes a user's saved profiles.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? def }
        id = d(.id, UUID())
        name = d(.name, "")
        kind = d(.kind, .ssh)
        host = d(.host, "")
        port = d(.port, 22)
        username = d(.username, "")
        authType = d(.authType, .agent)
        identityFile = d(.identityFile, "")
        extraSSHOptions = d(.extraSSHOptions, [])
        agentForward = d(.agentForward, false)
        legacySCP = d(.legacySCP, false)
        jumpHost = d(.jumpHost, JumpHost())
        portForwards = d(.portForwards, [])
        cloudflareAccess = d(.cloudflareAccess, false)
        serialDevice = d(.serialDevice, "")
        baudRate = d(.baudRate, 115200)
        dataBits = d(.dataBits, 8)
        stopBits = d(.stopBits, 1)
        parity = d(.parity, "none")
        workingDirectory = d(.workingDirectory, "")
        tags = d(.tags, [])
        aiAllowed = d(.aiAllowed, false)
        customActions = d(.customActions, [])
        notes = d(.notes, "")
    }

    /// Human-readable connection target, e.g. `pi@10.0.0.4:22`
    var target: String {
        switch kind {
        case .local:
            return workingDirectory.isEmpty ? "~" : workingDirectory
        case .ssh:
            let user = username.isEmpty ? "" : "\(username)@"
            let p = port == 22 ? "" : ":\(port)"
            return "\(user)\(host)\(p)"
        case .telnet:
            return "\(host):\(port == 22 ? 23 : port)"
        case .serial:
            return "\(serialDevice) @ \(baudRate)"
        }
    }

    /// Keychain key for this profile's password.
    var passwordKeychainKey: String { "profile.\(id.uuidString)" }
    /// Keychain key for a pasted private key (authType == .keyText).
    var pemTextKeychainKey: String { "profile.\(id.uuidString).pemText" }
}
