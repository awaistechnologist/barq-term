import Foundation

enum AppPaths {
    static var supportDirectory: URL {
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
}
