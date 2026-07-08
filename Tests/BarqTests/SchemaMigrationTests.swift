import Testing
import Foundation
@testable import Barq

/// Guards the data-loss-on-upgrade bug: a profile/vault/snippet file written by
/// an OLDER build (missing fields added later) must still decode, with missing
/// fields defaulted — never dropped.
@Suite struct SchemaMigrationTests {

    private func temp(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("barq-migrate-\(UUID().uuidString)-\(name)")
    }

    @Test func decodesProfileMissingNewerFields() throws {
        // Pre-agentForward / pre-cloudflareAccess schema, with a port-forward
        // that predates filterMode/filterHosts.
        let oldJSON = """
        [{"id":"11111111-1111-1111-1111-111111111111","name":"prod","kind":"ssh",
          "host":"1.2.3.4","port":22,"username":"deploy","authType":"key",
          "identityFile":"~/.ssh/id","extraSSHOptions":[],"legacySCP":false,
          "jumpHost":{"enabled":false,"host":"","port":22,"username":"","identityFile":""},
          "portForwards":[{"id":"22222222-2222-2222-2222-222222222222","kind":"dynamic",
            "bindAddress":"127.0.0.1","listenPort":1080,"targetHost":"","targetPort":0,"enabled":true}],
          "serialDevice":"","baudRate":115200,"dataBits":8,"stopBits":1,"parity":"none",
          "workingDirectory":"","tags":["PROD"],"aiAllowed":false,"customActions":[],"notes":""}]
        """
        let decoded = try JSONDecoder().decode([ConnectionProfile].self, from: Data(oldJSON.utf8))
        #expect(decoded.count == 1, "old-schema profile must not be dropped")
        let p = decoded[0]
        #expect(p.name == "prod")
        #expect(p.host == "1.2.3.4")
        #expect(p.authType == .key)
        #expect(p.agentForward == false, "missing new field defaults, not throws")
        #expect(p.cloudflareAccess == false)
        #expect(p.portForwards.count == 1)
        #expect(p.portForwards[0].filterMode == .all, "PortForward's newer field also defaults")
    }

    @Test func profileStoreDoesNotWipeOldData() throws {
        // Write an old-schema file, then open a store on it: data must survive.
        let url = temp("profiles.json")
        let oldJSON = """
        [{"id":"33333333-3333-3333-3333-333333333333","name":"keeper","kind":"ssh","host":"h","port":22}]
        """
        try Data(oldJSON.utf8).write(to: url)
        let store = ProfileStore(fileURL: url)
        #expect(store.profile(named: "keeper") != nil, "opening a newer build must not discard old profiles")
        #expect(store.profiles.count == 1, "and must not replace them with the default Local seed")
    }

    @Test func corruptFileIsBackedUpNotOverwritten() throws {
        let url = temp("profiles.json")
        try Data("this is not json".utf8).write(to: url)
        _ = ProfileStore(fileURL: url)
        // The unreadable original was moved aside for recovery.
        let dir = url.deletingLastPathComponent()
        let backups = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        #expect(backups.contains { $0.hasPrefix(url.lastPathComponent + ".corrupt-") },
                "a file we can't parse must be preserved, not destroyed")
    }

    @Test func decodesVaultItemMissingNewerFields() throws {
        let oldJSON = """
        [{"id":"44444444-4444-4444-4444-444444444444","name":"STAGING_IP"}]
        """
        let items = try JSONDecoder().decode([VaultItem].self, from: Data(oldJSON.utf8))
        #expect(items.count == 1)
        #expect(items[0].name == "STAGING_IP")
        #expect(items[0].policy == .approval, "missing policy defaults")
    }

    @Test func decodesSnippetMissingNewerFields() throws {
        let oldJSON = """
        [{"id":"55555555-5555-5555-5555-555555555555","command":"df -h"}]
        """
        let snips = try JSONDecoder().decode([Snippet].self, from: Data(oldJSON.utf8))
        #expect(snips.count == 1)
        #expect(snips[0].command == "df -h")
        #expect(snips[0].title == "")
        #expect(snips[0].tags == [])
    }
}
