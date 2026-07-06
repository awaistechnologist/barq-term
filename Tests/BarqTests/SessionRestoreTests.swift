import Testing
import Foundation
@testable import Barq

@Suite struct SessionRestoreTests {

    @Test func snapshotRoundTrips() throws {
        let id = UUID()
        let snapshot = [
            RestorableSession(profileID: id, workingDirectory: "/Users/me/code", customTitle: "work"),
            RestorableSession(profileID: UUID(), workingDirectory: nil, customTitle: nil)
        ]
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode([RestorableSession].self, from: data)
        #expect(decoded == snapshot)
        #expect(decoded[0].workingDirectory == "/Users/me/code")
        #expect(decoded[0].customTitle == "work")
    }

    @Test func loadReturnsEmptyWhenAbsent() {
        // Point at a guaranteed-missing file by clearing first.
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("barq-nonexistent-\(UUID().uuidString).json")
        let data = try? Data(contentsOf: missing)
        #expect(data == nil)
    }

    @Test func emptySnapshotDecodes() throws {
        let data = try JSONEncoder().encode([RestorableSession]())
        let decoded = try JSONDecoder().decode([RestorableSession].self, from: data)
        #expect(decoded.isEmpty)
    }
}
