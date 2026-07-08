import Foundation

/// Resolves a profile's private key into a concrete path that `ssh -i` can use.
///
/// - `.key`  → the identity file path (tilde-expanded).
/// - `.keyText` → the pasted key (kept in the Keychain) written to a 0600 temp
///   file in the app-support keys dir, so ssh can read it.
enum SSHKeyMaterializer {

    /// Returns a copy of the profile ready to connect: for pasted-key auth, its
    /// `identityFile` points at a freshly-written temp key file. Other auth
    /// types are returned unchanged.
    static func resolvedForConnect(_ profile: ConnectionProfile) -> ConnectionProfile {
        guard profile.authType == .keyText else { return profile }
        guard let path = writeTempKey(for: profile) else { return profile }
        var resolved = profile
        resolved.identityFile = path
        return resolved
    }

    /// Write the profile's pasted key to a private temp file; returns its path.
    @discardableResult
    static func writeTempKey(for profile: ConnectionProfile) -> String? {
        guard var text = Keychain.get(profile.pemTextKeychainKey), !text.isEmpty else { return nil }
        // OpenSSH is strict: the key must end with a trailing newline.
        if !text.hasSuffix("\n") { text += "\n" }
        let url = AppPaths.keysDirectory.appendingPathComponent("key-\(profile.id.uuidString)")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return url.path
        } catch {
            return nil
        }
    }

    /// Remove a profile's materialized key file (called when a profile is deleted).
    static func removeTempKey(for profile: ConnectionProfile) {
        let url = AppPaths.keysDirectory.appendingPathComponent("key-\(profile.id.uuidString)")
        try? FileManager.default.removeItem(at: url)
    }
}
