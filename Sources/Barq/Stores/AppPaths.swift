import Foundation

enum AppPaths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Barq", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var profilesFile: URL { supportDirectory.appendingPathComponent("profiles.json") }
    static var vaultFile: URL { supportDirectory.appendingPathComponent("vault.json") }
    static var bridgeSocket: URL { supportDirectory.appendingPathComponent("bridge.sock") }
}
