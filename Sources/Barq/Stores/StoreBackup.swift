import Foundation

/// Safety net for JSON stores: if a data file can't be parsed, move it aside
/// (rather than letting the app silently overwrite it with defaults) so the
/// user's data can be recovered.
enum StoreBackup {
    /// Rename `url` to `<name>.corrupt-<timestamp>` next to it. Returns true if
    /// a file was moved.
    @discardableResult
    static func backup(_ url: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return false }
        let stamp = Int(Date().timeIntervalSince1970)
        let dest = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).corrupt-\(stamp)")
        do {
            try fm.moveItem(at: url, to: dest)
            NSLog("Barq: could not parse \(url.lastPathComponent); backed up to \(dest.lastPathComponent)")
            return true
        } catch {
            return false
        }
    }
}
