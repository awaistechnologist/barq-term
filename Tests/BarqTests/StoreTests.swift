import Testing
import Foundation
@testable import Barq

private func tempFile(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("barq-tests-\(UUID().uuidString)-\(name)")
}

@Suite struct ProfileStoreTests {

    @Test func firstLaunchSeedsALocalProfile() {
        let store = ProfileStore(fileURL: tempFile("profiles.json"))
        #expect(store.profiles.count == 1)
        #expect(store.profiles[0].kind == .local)
    }

    @Test func upsertPersistsAndReloads() throws {
        let url = tempFile("profiles.json")
        let store = ProfileStore(fileURL: url)
        var profile = ConnectionProfile()
        profile.name = "router"
        profile.kind = .ssh
        profile.host = "10.0.0.1"
        store.upsert(profile)

        let reloaded = ProfileStore(fileURL: url)
        #expect(reloaded.profile(named: "router")?.host == "10.0.0.1")
    }

    @Test func upsertReplacesById() {
        let store = ProfileStore(fileURL: tempFile("profiles.json"))
        var profile = ConnectionProfile()
        profile.name = "a"
        store.upsert(profile)
        let countAfterInsert = store.profiles.count
        profile.name = "b"
        store.upsert(profile)
        #expect(store.profiles.count == countAfterInsert, "same id must update, not duplicate")
        #expect(store.profile(named: "b") != nil)
        #expect(store.profile(named: "a") == nil)
    }

    @Test func profileLookupIsCaseInsensitive() {
        let store = ProfileStore(fileURL: tempFile("profiles.json"))
        var profile = ConnectionProfile()
        profile.name = "Staging-Server"
        store.upsert(profile)
        #expect(store.profile(named: "staging-server") != nil)
    }

    @Test func tagsGroupingAndOtherBucket() {
        let store = ProfileStore(fileURL: tempFile("profiles.json"))
        var tagged = ConnectionProfile()
        tagged.name = "lab1"
        tagged.tags = ["LAB"]
        store.upsert(tagged)
        // The seeded Local profile has tag LOCAL; add an untagged one.
        var untagged = ConnectionProfile()
        untagged.name = "misc"
        untagged.tags = []
        store.upsert(untagged)

        #expect(store.allTags.contains("LAB"))
        #expect(store.allTags.contains("OTHER"))
        #expect(store.profiles(tag: "LAB").map(\.name) == ["lab1"])
        #expect(store.profiles(tag: "OTHER").map(\.name) == ["misc"])
    }

    @Test func removeDeletesProfile() {
        let store = ProfileStore(fileURL: tempFile("profiles.json"))
        var profile = ConnectionProfile()
        profile.name = "gone"
        store.upsert(profile)
        store.remove(id: profile.id)
        #expect(store.profile(named: "gone") == nil)
    }

    @Test func exportImportRoundTrip() throws {
        let store = ProfileStore(fileURL: tempFile("profiles.json"))
        var profile = ConnectionProfile()
        profile.name = "exported"
        store.upsert(profile)
        let data = try store.exportJSON()

        let other = ProfileStore(fileURL: tempFile("profiles2.json"))
        try other.importJSON(data, merge: true)
        #expect(other.profile(named: "exported") != nil)
        // Importing again must not duplicate (merge by id).
        let before = other.profiles.count
        try other.importJSON(data, merge: true)
        #expect(other.profiles.count == before)
    }
}

@Suite struct KeychainTests {

    @Test func setGetDeleteRoundTrip() {
        let key = "test.\(UUID().uuidString)"
        defer { Keychain.delete(key) }
        #expect(Keychain.get(key) == nil)
        #expect(Keychain.set("secret-value", for: key))
        #expect(Keychain.get(key) == "secret-value")
        #expect(Keychain.set("updated", for: key), "second set must update in place")
        #expect(Keychain.get(key) == "updated")
        #expect(Keychain.delete(key))
        #expect(Keychain.get(key) == nil)
    }
}

@Suite struct VaultStoreTests {

    func makeVault() -> VaultStore {
        VaultStore(fileURL: tempFile("vault.json"))
    }

    @Test func setAndReadBack() throws {
        let vault = makeVault()
        let name = "TEST_VAR_\(UInt32.random(in: 0..<9999))"
        defer { vault.remove(name: name) }
        try vault.set(name: name, value: "10.0.0.7", summary: "staging box", policy: .open)
        #expect(vault.value(of: name) == "10.0.0.7")
        #expect(vault.item(named: name)?.policy == .open)
    }

    @Test func invalidNameRejected() {
        let vault = makeVault()
        #expect(throws: VaultError.self) {
            try vault.set(name: "bad name", value: "x", summary: "", policy: .open)
        }
    }

    @Test func persistenceAcrossReload() throws {
        let url = tempFile("vault.json")
        let name = "TEST_PERSIST_\(UInt32.random(in: 0..<9999))"
        let vault = VaultStore(fileURL: url)
        defer { vault.remove(name: name) }
        try vault.set(name: name, value: "v", summary: "desc", policy: .secret)

        let reloaded = VaultStore(fileURL: url)
        #expect(reloaded.item(named: name)?.summary == "desc")
        #expect(reloaded.item(named: name)?.policy == .secret)
        #expect(reloaded.value(of: name) == "v", "value comes from Keychain, not the JSON file")
    }

    @Test func agentReadOpenPolicyReturnsValue() async throws {
        let vault = makeVault()
        let name = "TEST_OPEN_\(UInt32.random(in: 0..<9999))"
        defer { vault.remove(name: name) }
        try vault.set(name: name, value: "readable", summary: "", policy: .open)
        let value = try await vault.agentRead(name: name, agent: "test-agent")
        #expect(value == "readable")
    }

    @Test func agentReadSecretPolicyRefuses() async throws {
        let vault = makeVault()
        let name = "TEST_SECRET_\(UInt32.random(in: 0..<9999))"
        defer { vault.remove(name: name) }
        try vault.set(name: name, value: "hidden", summary: "", policy: .secret)
        await #expect(throws: VaultError.self) {
            _ = try await vault.agentRead(name: name, agent: "test-agent")
        }
    }

    @Test func agentReadUnknownThrows() async {
        let vault = makeVault()
        await #expect(throws: VaultError.self) {
            _ = try await vault.agentRead(name: "TEST_DOES_NOT_EXIST", agent: "test-agent")
        }
    }

    @Test func expansionSubstitutesOpenAndSecretValues() async throws {
        let vault = makeVault()
        let ip = "TEST_IP_\(UInt32.random(in: 0..<9999))"
        let token = "TEST_TOKEN_\(UInt32.random(in: 0..<9999))"
        defer { vault.remove(name: ip); vault.remove(name: token) }
        try vault.set(name: ip, value: "192.168.7.1", summary: "", policy: .open)
        try vault.set(name: token, value: "s3cr3t", summary: "", policy: .secret)

        let expanded = try await vault.expandVariables(
            in: "curl -H 'X-Token: ${BARQ:\(token)}' http://${BARQ:\(ip)}/status",
            agent: "test-agent"
        )
        #expect(expanded == "curl -H 'X-Token: s3cr3t' http://192.168.7.1/status")
    }

    @Test func expansionRepeatsAndUnknowns() async throws {
        let vault = makeVault()
        let name = "TEST_REPEAT_\(UInt32.random(in: 0..<9999))"
        defer { vault.remove(name: name) }
        try vault.set(name: name, value: "X", summary: "", policy: .open)

        let expanded = try await vault.expandVariables(in: "${BARQ:\(name)}/${BARQ:\(name)}", agent: "a")
        #expect(expanded == "X/X")

        await #expect(throws: VaultError.self) {
            _ = try await vault.expandVariables(in: "echo ${BARQ:TEST_MISSING_VAR}", agent: "a")
        }
    }

    @Test func commandsWithoutReferencesPassThroughUntouched() async throws {
        let vault = makeVault()
        let cmd = "echo $HOME && printf '%s' plain"
        let expanded = try await vault.expandVariables(in: cmd, agent: "a")
        #expect(expanded == cmd)
    }

    @Test func discoveryListingNeverContainsValues() throws {
        let vault = makeVault()
        let name = "TEST_DISCO_\(UInt32.random(in: 0..<9999))"
        defer { vault.remove(name: name) }
        try vault.set(name: name, value: "super-hidden-value", summary: "a database", policy: .secret)
        let listing = vault.discoveryListing()
        let entry = listing.first { $0["name"] == name }
        #expect(entry != nil)
        #expect(entry?["policy"] == "secret")
        #expect(entry?["usage"] == "${BARQ:\(name)}")
        let joined = listing.flatMap(\.values).joined()
        #expect(!joined.contains("super-hidden-value"), "discovery must never leak values")
    }

    @Test func removeAlsoDeletesKeychainValue() throws {
        let vault = makeVault()
        let name = "TEST_RM_\(UInt32.random(in: 0..<9999))"
        try vault.set(name: name, value: "v", summary: "", policy: .open)
        vault.remove(name: name)
        #expect(vault.item(named: name) == nil)
        #expect(vault.value(of: name) == nil)
    }
}
