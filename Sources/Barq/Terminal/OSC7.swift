import Foundation

/// OSC 7 "current working directory" reports arrive as file:// URLs
/// (e.g. `file://Mac.local/Users/me/code`). Pure parsing — unit tested.
enum OSC7 {
    static func parsePath(_ directory: String?) -> String? {
        guard let directory, !directory.isEmpty else { return nil }
        if directory.hasPrefix("/") { return directory }
        guard let url = URL(string: directory), url.scheme == "file" else { return nil }
        let path = url.path
        return path.isEmpty ? nil : path.removingPercentEncoding ?? path
    }
}
