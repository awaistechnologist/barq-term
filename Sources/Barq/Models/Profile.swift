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

    var id: String { rawValue }

    var label: String {
        switch self {
        case .agent: return "SSH Agent / Ask"
        case .password: return "Password"
        case .key: return "Identity File"
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
}
