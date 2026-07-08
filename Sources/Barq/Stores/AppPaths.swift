import Foundation

enum AppPaths {
    static var supportDirectory: URL {
        // Tests/diagnostics can redirect all app data to a scratch dir via
        // BARQ_SUPPORT_DIR so they never touch the user's real profiles/vault.
        if let override = ProcessInfo.processInfo.environment["BARQ_SUPPORT_DIR"], !override.isEmpty {
            let dir = URL(fileURLWithPath: override, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            return dir
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Barq", isDirectory: true)
        // Owner-only (0700): this dir holds the bridge socket, profiles, and the
        // vault metadata; keep other local users out.
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return dir
    }

    static var profilesFile: URL { supportDirectory.appendingPathComponent("profiles.json") }
    static var vaultFile: URL { supportDirectory.appendingPathComponent("vault.json") }
    static var bridgeSocket: URL { supportDirectory.appendingPathComponent("bridge.sock") }

    /// Directory for materialized private keys (pasted keys written to disk so
    /// ssh can `-i` them). Owner-only.
    static var keysDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("keys", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return dir
    }
}
