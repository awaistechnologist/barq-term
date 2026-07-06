import Foundation

/// Records a session's output to the asciinema v2 `.cast` format:
/// a JSON header line followed by `[time, "o", data]` event lines.
/// https://docs.asciinema.org/manual/asciicast/v2/
final class SessionRecorder {
    private(set) var isRecording = false
    private var handle: FileHandle?
    private var startTime: Date?
    private(set) var url: URL?
    private let lock = NSLock()

    let cols: Int
    let rows: Int
    /// Injectable clock for deterministic tests.
    var now: () -> Date = { Date() }

    init(cols: Int = 80, rows: Int = 24) {
        self.cols = cols
        self.rows = rows
    }

    /// Build the asciicast v2 header line.
    func header(title: String, timestamp: TimeInterval) -> String {
        let obj: [String: Any] = [
            "version": 2,
            "width": cols,
            "height": rows,
            "timestamp": Int(timestamp),
            "title": title,
            "env": ["TERM": "xterm-256color", "SHELL": "/bin/zsh"]
        ]
        let data = try! JSONSerialization.data(withJSONObject: obj)
        return String(decoding: data, as: UTF8.self)
    }

    /// Serialize one output event line: `[elapsed, "o", data]`.
    func eventLine(elapsed: TimeInterval, data: String) -> String {
        // JSONSerialization on an array keeps number/string encoding correct
        // and escapes control characters in `data`.
        let rounded = (elapsed * 1_000_000).rounded() / 1_000_000
        let arr: [Any] = [rounded, "o", data]
        let out = try! JSONSerialization.data(withJSONObject: arr)
        return String(decoding: out, as: UTF8.self)
    }

    @discardableResult
    func start(title: String, to directory: URL) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        guard !isRecording else { return url }
        let stamp = Int(now().timeIntervalSince1970)
        let safe = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "_")
        let fileURL = directory.appendingPathComponent("barq-\(safe)-\(stamp).cast")
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return nil }
        handle.write(Data((header(title: title, timestamp: now().timeIntervalSince1970) + "\n").utf8))
        self.handle = handle
        self.url = fileURL
        self.startTime = now()
        isRecording = true
        return fileURL
    }

    func record(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        guard isRecording, let handle, let startTime else { return }
        let elapsed = now().timeIntervalSince(startTime)
        handle.write(Data((eventLine(elapsed: elapsed, data: text) + "\n").utf8))
    }

    @discardableResult
    func stop() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        guard isRecording else { return nil }
        try? handle?.close()
        handle = nil
        isRecording = false
        return url
    }
}
