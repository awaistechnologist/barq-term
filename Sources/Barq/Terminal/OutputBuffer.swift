import Foundation

/// Rolling capture of a session's raw output so the AI layer and MCP clients
/// can read scrollback without touching the renderer. Thread-safe.
final class OutputBuffer {
    private var data = Data()
    private let capacity: Int
    private let lock = NSLock()
    /// Total bytes ever received — lets readers ask for "everything after X".
    private(set) var totalReceived: Int = 0

    init(capacity: Int = 512 * 1024) {
        self.capacity = capacity
    }

    func append(_ bytes: ArraySlice<UInt8>) {
        lock.lock()
        defer { lock.unlock() }
        data.append(contentsOf: bytes)
        totalReceived += bytes.count
        if data.count > capacity {
            data.removeFirst(data.count - capacity)
        }
    }

    /// The last `maxBytes` of output as a cleaned string.
    func tail(_ maxBytes: Int = 8192) -> String {
        lock.lock()
        defer { lock.unlock() }
        let slice = data.suffix(maxBytes)
        return Self.clean(String(decoding: slice, as: UTF8.self))
    }

    /// Output received after absolute offset `offset` (from `totalReceived`).
    func since(offset: Int) -> (text: String, newOffset: Int) {
        lock.lock()
        defer { lock.unlock() }
        let start = max(0, offset)
        let missing = totalReceived - data.count // bytes that already rolled off
        let localStart = max(0, start - missing)
        let slice = localStart < data.count ? data.suffix(data.count - localStart) : Data()
        return (Self.clean(String(decoding: slice, as: UTF8.self)), totalReceived)
    }

    /// Strip ANSI escape sequences and control characters for AI/MCP consumers.
    static func clean(_ text: String) -> String {
        var result = text
        // CSI sequences, OSC sequences, and single-char escapes.
        for pattern in [
            "\u{1B}\\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)", // OSC ... BEL/ST
            "\u{1B}\\[[0-9;?]*[ -/]*[@-~]",                 // CSI
            "\u{1B}[@-Z\\\\-_]"                               // other ESC x
        ] {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")
        return result
    }
}
