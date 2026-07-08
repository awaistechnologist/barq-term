import Foundation

/// Builds argument vectors for /usr/bin/ssh, scp and sftp from a profile.
/// Pure functions — unit tested.
enum SSHCommandBuilder {

    /// A host is safe to pass to ssh/scp/sftp only if it can't be mistaken for
    /// an option (leading `-`) and contains no whitespace or shell/URL
    /// metacharacters. Used both to validate profiles at creation and as a
    /// belt-and-suspenders guard alongside the `--` option terminator.
    static func isSafeHost(_ host: String) -> Bool {
        guard !host.isEmpty, !host.hasPrefix("-") else { return false }
        // Hostnames / IPs / IPv6 in brackets: letters, digits, . : - [ ] % only.
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:-[]%")
        return host.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// True for auth modes that pass an identity file to ssh. `.keyText` becomes
    /// a materialized temp file (see SSHKeyMaterializer) before we build args.
    static func usesIdentityFile(_ profile: ConnectionProfile) -> Bool {
        profile.authType == .key || profile.authType == .keyText
    }

    static func sshArguments(for profile: ConnectionProfile) -> [String] {
        var args: [String] = []

        if profile.port != 22 {
            args += ["-p", String(profile.port)]
        }
        if usesIdentityFile(profile), !profile.identityFile.isEmpty {
            args += ["-i", expandTilde(profile.identityFile), "-o", "IdentitiesOnly=yes"]
        }
        if profile.agentForward {
            args += ["-A"]
        }
        if profile.cloudflareAccess {
            // Zero-trust tunnel: ssh pipes through `cloudflared access ssh`.
            args += ["-o", "ProxyCommand=cloudflared access ssh --hostname %h"]
        } else if profile.jumpHost.enabled, !profile.jumpHost.host.isEmpty {
            args += ["-J", profile.jumpHost.proxyJumpValue]
            if !profile.jumpHost.identityFile.isEmpty {
                // Applies the key to the whole chain; ssh will offer it to both hops.
                args += ["-i", expandTilde(profile.jumpHost.identityFile)]
            }
        }
        for forward in profile.portForwards where forward.enabled {
            args += forward.sshArguments
        }
        if profile.legacySCP {
            args += ["-o", "HostKeyAlgorithms=+ssh-rsa", "-o", "PubkeyAcceptedKeyTypes=+ssh-rsa"]
        }
        for option in profile.extraSSHOptions where !option.isEmpty {
            args += ["-o", option]
        }
        // Keep sessions alive through short network hiccups.
        args += ["-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=3"]

        var destination = profile.host
        if !profile.username.isEmpty {
            destination = "\(profile.username)@\(profile.host)"
        }
        // `--` terminates option parsing so a host like "-oProxyCommand=…"
        // can never be interpreted as an ssh option (option injection).
        args.append("--")
        args.append(destination)
        return args
    }

    /// scp arguments for a single file transfer. `upload == true` copies
    /// localPath → remotePath, otherwise remotePath → localPath.
    static func scpArguments(for profile: ConnectionProfile, localPath: String, remotePath: String, upload: Bool, recursive: Bool = false) -> [String] {
        var args: [String] = []
        if recursive { args.append("-r") }
        if profile.port != 22 {
            args += ["-P", String(profile.port)]
        }
        if usesIdentityFile(profile), !profile.identityFile.isEmpty {
            args += ["-i", expandTilde(profile.identityFile), "-o", "IdentitiesOnly=yes"]
        }
        if profile.jumpHost.enabled, !profile.jumpHost.host.isEmpty {
            args += ["-J", profile.jumpHost.proxyJumpValue]
        }
        if profile.legacySCP {
            // Legacy protocol for dropbear/BusyBox targets.
            args += ["-O", "-o", "HostKeyAlgorithms=+ssh-rsa", "-o", "PubkeyAcceptedKeyTypes=+ssh-rsa"]
        }
        args += ["-o", "BatchMode=yes"]

        let user = profile.username.isEmpty ? "" : "\(profile.username)@"
        let remote = "\(user)\(profile.host):\(remotePath)"
        args.append("--")
        if upload {
            args += [expandTilde(localPath), remote]
        } else {
            args += [remote, expandTilde(localPath)]
        }
        return args
    }

    /// sftp arguments for an interactive SFTP session using a profile.
    static func sftpArguments(for profile: ConnectionProfile) -> [String] {
        var args: [String] = []
        if profile.port != 22 {
            args += ["-P", String(profile.port)]
        }
        if usesIdentityFile(profile), !profile.identityFile.isEmpty {
            args += ["-i", expandTilde(profile.identityFile), "-o", "IdentitiesOnly=yes"]
        }
        if profile.jumpHost.enabled, !profile.jumpHost.host.isEmpty {
            args += ["-J", profile.jumpHost.proxyJumpValue]
        }
        if profile.legacySCP {
            args += ["-o", "HostKeyAlgorithms=+ssh-rsa", "-o", "PubkeyAcceptedKeyTypes=+ssh-rsa"]
        }
        let user = profile.username.isEmpty ? "" : "\(profile.username)@"
        args.append("\(user)\(profile.host)")
        return args
    }

    static func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
