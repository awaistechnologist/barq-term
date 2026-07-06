import Testing
import Foundation
@testable import Barq

/// Tests for the H1 fix: secret vault values must be scrubbed from any string
/// returned to an agent, even when echoed by the shell or printed by a command.
@Suite @MainActor struct VaultRedactionTests {

    func makeVault() -> VaultStore {
        VaultStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("barq-redact-\(UUID().uuidString).json"))
    }

    @Test func redactsSecretValues() throws {
        let vault = makeVault()
        let name = "TEST_SECRET_\(UInt32.random(in: 0..<9999))"
        defer { vault.remove(name: name) }
        try vault.set(name: name, value: "hunter2secret", summary: "", policy: .secret)

        // Simulate a shell echoing the expanded command back to the buffer.
        let echoed = "$ curl -H 'Authorization: hunter2secret' https://api.example.com\nOK"
        let redacted = vault.redactSecrets(in: echoed)
        #expect(!redacted.contains("hunter2secret"), "secret must never survive to the agent")
        #expect(redacted.contains("‹redacted:\(name)›"))
        #expect(redacted.contains("api.example.com"), "non-secret text is preserved")
    }

    @Test func doesNotRedactOpenOrApprovalValues() throws {
        let vault = makeVault()
        let open = "TEST_OPEN_\(UInt32.random(in: 0..<9999))"
        let appr = "TEST_APPR_\(UInt32.random(in: 0..<9999))"
        defer { vault.remove(name: open); vault.remove(name: appr) }
        try vault.set(name: open, value: "openvalue123", summary: "", policy: .open)
        try vault.set(name: appr, value: "apprvalue456", summary: "", policy: .approval)

        let text = "openvalue123 and apprvalue456"
        // Only secret-policy values are redacted; open/approval are readable by design.
        #expect(vault.redactSecrets(in: text) == text)
    }

    @Test func ignoresVeryShortSecretsToAvoidFalsePositives() throws {
        let vault = makeVault()
        let name = "TEST_SHORT_\(UInt32.random(in: 0..<9999))"
        defer { vault.remove(name: name) }
        try vault.set(name: name, value: "ab", summary: "", policy: .secret)
        // A 2-char value would redact everywhere it appears in normal output —
        // too noisy, so short values are left alone (documented tradeoff).
        #expect(vault.redactSecrets(in: "abcabc") == "abcabc")
    }
}
