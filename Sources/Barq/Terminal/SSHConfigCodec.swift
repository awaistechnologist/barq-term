import Foundation

/// Convert between `~/.ssh/config` Host blocks and Barq profiles.
/// Pure functions — unit tested.
enum SSHConfigCodec {

    /// Parse an ssh config file into profiles. `Host *` and wildcard hosts are
    /// skipped (they are defaults, not connectable targets).
    static func parse(_ text: String) -> [ConnectionProfile] {
        var profiles: [ConnectionProfile] = []
        var current: ConnectionProfile?

        func flush() {
            if let profile = current, !profile.host.isEmpty || !profile.name.isEmpty {
                profiles.append(profile)
            }
            current = nil
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            if key == "host" {
                flush()
                if value.contains("*") || value.contains("?") { current = nil; continue }
                var profile = ConnectionProfile()
                profile.name = value
                profile.kind = .ssh
                profile.host = value // overwritten by HostName if present
                current = profile
                continue
            }

            guard current != nil else { continue }
            switch key {
            case "hostname": current?.host = value
            case "user": current?.username = value
            case "port": current?.port = Int(value) ?? 22
            case "identityfile":
                current?.identityFile = value
                current?.authType = .key
            case "proxyjump":
                current?.jumpHost = parseProxyJump(value)
            case "proxycommand" where value.contains("cloudflared"):
                current?.cloudflareAccess = true
            default:
                current?.extraSSHOptions.append("\(parts[0])=\(value)")
            }
        }
        flush()
        return profiles
    }

    static func parseProxyJump(_ value: String) -> JumpHost {
        var jump = JumpHost(enabled: true, host: "", port: 22, username: "", identityFile: "")
        var spec = value
        if let at = spec.firstIndex(of: "@") {
            jump.username = String(spec[..<at])
            spec = String(spec[spec.index(after: at)...])
        }
        if let colon = spec.firstIndex(of: ":") {
            jump.host = String(spec[..<colon])
            jump.port = Int(spec[spec.index(after: colon)...]) ?? 22
        } else {
            jump.host = spec
        }
        return jump
    }

    /// Generate an ssh config fragment from profiles (SSH profiles only).
    static func generate(_ profiles: [ConnectionProfile]) -> String {
        var lines: [String] = []
        for profile in profiles where profile.kind == .ssh {
            let alias = profile.name.isEmpty ? profile.host : profile.name
            lines.append("Host \(alias)")
            if !profile.host.isEmpty { lines.append("    HostName \(profile.host)") }
            if !profile.username.isEmpty { lines.append("    User \(profile.username)") }
            if profile.port != 22 { lines.append("    Port \(profile.port)") }
            if profile.authType == .key, !profile.identityFile.isEmpty {
                lines.append("    IdentityFile \(profile.identityFile)")
            }
            if profile.cloudflareAccess {
                lines.append("    ProxyCommand cloudflared access ssh --hostname %h")
            } else if profile.jumpHost.enabled, !profile.jumpHost.host.isEmpty {
                lines.append("    ProxyJump \(profile.jumpHost.proxyJumpValue)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
