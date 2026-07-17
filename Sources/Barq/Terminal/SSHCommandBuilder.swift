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

    /// The command to run on the remote instead of a default interactive login
    /// shell, or nil to keep the default login shell.
    /// - An explicit `remoteCommand` wins.
    /// - Otherwise, `loginShell == false` runs a plain (non-login) interactive
    ///   shell — `exec ${SHELL:-/bin/sh}` isn't invoked as a login shell, so it
    ///   skips /etc/profile[.d], which is exactly the gate some devices use.
    static func remoteShellCommand(for profile: ConnectionProfile) -> String? {
        if !profile.remoteCommand.isEmpty { return profile.remoteCommand }
        if !profile.loginShell { return "exec ${SHELL:-/bin/sh}" }
        return nil
    }

    static func sshArguments(for profile: ConnectionProfile) -> [String] {
        var args: [String] = []

        if profile.port != 22 {
            args += ["-p", String(profile.port)]
        }
        // A remote command doesn't get a PTY by default; force one (-tt) so the
        // shell/command is interactive.
        let command = remoteShellCommand(for: profile)
        if command != nil {
            args += ["-tt"]
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
        // Fail fast on an unreachable host (default is ~75s of silent hang),
        // then keep the session alive through short hiccups once connected.
        if !profile.extraSSHOptions.contains(where: { $0.lowercased().hasPrefix("connecttimeout") }) {
            args += ["-o", "ConnectTimeout=15"]
        }
        args += ["-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=3"]

        var destination = profile.host
        if !profile.username.isEmpty {
            destination = "\(profile.username)@\(profile.host)"
        }
        // `--` terminates option parsing so a host like "-oProxyCommand=…"
        // can never be interpreted as an ssh option (option injection).
        args.append("--")
        args.append(destination)
        // Remote command (if any) follows the destination; ssh sends it to the
        // remote shell verbatim.
        if let command { args.append(command) }
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
