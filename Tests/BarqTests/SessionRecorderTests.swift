import Testing
import Foundation
@testable import Barq

@Suite struct SessionRecorderTests {

    @Test func headerIsValidAsciicastV2() throws {
        let recorder = SessionRecorder(cols: 100, rows: 30)
        let header = recorder.header(title: "test", timestamp: 1_700_000_000)
        let obj = try JSONSerialization.jsonObject(with: Data(header.utf8)) as? [String: Any]
        #expect(obj?["version"] as? Int == 2)
        #expect(obj?["width"] as? Int == 100)
        #expect(obj?["height"] as? Int == 30)
        #expect(obj?["title"] as? String == "test")
    }

    @Test func eventLineFormat() throws {
        let recorder = SessionRecorder()
        let line = recorder.eventLine(elapsed: 1.5, data: "hello")
        let arr = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [Any]
        #expect(arr?.count == 3)
        #expect(arr?[1] as? String == "o")
        #expect(arr?[2] as? String == "hello")
    }

    @Test func eventLineEscapesControlChars() throws {
        let recorder = SessionRecorder()
        let line = recorder.eventLine(elapsed: 0.1, data: "\u{1B}[31mred\u{1B}[0m\n")
        // Must be valid JSON with the escape sequences preserved as data.
        let arr = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [Any]
        #expect(arr?[2] as? String == "\u{1B}[31mred\u{1B}[0m\n")
    }

    @Test func recordsToFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("barq-rec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let recorder = SessionRecorder(cols: 80, rows: 24)
        // Deterministic clock: advance 1s per call.
        var tick = 0
        recorder.now = {
            defer { tick += 1 }
            return Date(timeIntervalSince1970: 1_700_000_000 + Double(tick))
        }

        let url = recorder.start(title: "mysession", to: dir)
        #expect(url != nil)
        #expect(recorder.isRecording)
        recorder.record("first\n")
        recorder.record("second\n")
        let saved = recorder.stop()
        #expect(!recorder.isRecording)
        #expect(saved == url)

        let contents = try String(contentsOf: url!, encoding: .utf8)
        let lines = contents.split(separator: "\n")
        #expect(lines.count == 3, "header + 2 events")

        // First line is the header.
        let header = try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any]
        #expect(header?["version"] as? Int == 2)

        // Events carry increasing timestamps.
        let e1 = try JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as? [Any]
        let e2 = try JSONSerialization.jsonObject(with: Data(lines[2].utf8)) as? [Any]
        #expect((e1?[0] as? Double ?? 0) < (e2?[0] as? Double ?? 0))
        #expect(e1?[2] as? String == "first\n")
    }

    @Test func doubleStartIsIdempotent() throws {
        let dir = FileManager.default.temporaryDirectory
        let recorder = SessionRecorder()
        let first = recorder.start(title: "a", to: dir)
        let second = recorder.start(title: "a", to: dir)
        #expect(first == second, "second start returns the same file, not a new one")
        recorder.stop()
        if let first { try? FileManager.default.removeItem(at: first) }
    }
}
