import Foundation

/// Parses an ad-hoc SSH target like `user@host:2222` into a throwaway profile.
/// Pure — unit tested.
enum QuickConnect {
    /// Returns a connectable SSH profile, or nil if the spec has no host.
    static func profile(from spec: String) -> ConnectionProfile? {
        var rest = spec.trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }

        // Optional ssh:// scheme.
        if rest.hasPrefix("ssh://") { rest.removeFirst("ssh://".count) }

        var username = ""
        if let at = rest.firstIndex(of: "@") {
            username = String(rest[..<at])
            rest = String(rest[rest.index(after: at)...])
        }

        var port = 22
        // Split host:port, but leave bracketed IPv6 (`[::1]:22`) host intact.
        if !rest.hasPrefix("["), let colon = rest.lastIndex(of: ":") {
            let portStr = String(rest[rest.index(after: colon)...])
            if let p = Int(portStr), p > 0 {
                port = p
                rest = String(rest[..<colon])
            }
        }

        let host = rest
        guard SSHCommandBuilder.isSafeHost(host) else { return nil }

        var profile = ConnectionProfile()
        profile.kind = .ssh
        profile.host = host
        profile.username = username
        profile.port = port
        profile.name = username.isEmpty ? host : "\(username)@\(host)"
        return profile
    }
}
