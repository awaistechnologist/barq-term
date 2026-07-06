import Testing
import Foundation
@testable import Barq

/// Bridge = the MCP enforcement boundary. These tests exercise every tool
/// path that doesn't require a live UI, including the security refusals.
@Suite struct BridgeHandlerTests {

    func makeHandler() -> (BridgeHandler, ProfileStore, VaultStore) {
        let profiles = ProfileStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("barq-tests-\(UUID().uuidString)-profiles.json")
        )
        let vault = VaultStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("barq-tests-\(UUID().uuidString)-vault.json")
        )
        return (BridgeHandler(profiles: profiles, vault: vault), profiles, vault)
    }

    @Test func pingAnswers() async throws {
        let (handler, _, _) = makeHandler()
        let result = try await handler.handle(method: "ping", params: [:]) as? [String: Any]
        #expect(result?["app"] as? String == "Barq")
    }

    @Test func unknownMethodThrows() async {
        let (handler, _, _) = makeHandler()
        await #expect(throws: BridgeError.self) {
            _ = try await handler.handle(method: "no_such_tool", params: [:])
        }
    }

    @Test func missingParamThrows() async {
        let (handler, _, _) = makeHandler()
        await #expect(throws: BridgeError.self) {
            _ = try await handler.handle(method: "connect", params: [:])
        }
    }

    @Test func listProfilesShowsAIStatus() async throws {
        let (handler, profiles, _) = makeHandler()
        var profile = ConnectionProfile()
        profile.name = "router"
        profile.kind = .ssh
        profile.host = "10.1.1.1"
        profile.aiAllowed = true
        await MainActor.run { profiles.upsert(profile) }

        let result = try await handler.handle(method: "list_profiles", params: [:]) as? [[String: String]]
        let router = result?.first { $0["name"] == "router" }
        #expect(router?["ai_allowed"] == "true")
        #expect(router?["target"] == "10.1.1.1")
    }

    @Test func connectRefusedWithoutAIAccess() async throws {
        let (handler, profiles, _) = makeHandler()
        var profile = ConnectionProfile()
        profile.name = "locked"
        profile.kind = .ssh
        profile.host = "10.1.1.2"
        profile.aiAllowed = false
        await MainActor.run { profiles.upsert(profile) }

        do {
            _ = try await handler.handle(method: "connect", params: ["profile_name": "locked"])
            Issue.record("connect must refuse profiles without AI access")
        } catch let error as BridgeError {
            #expect(error.localizedDescription.contains("AI access disabled"))
        }
    }

    @Test func connectUnknownProfileThrows() async {
        let (handler, _, _) = makeHandler()
        await #expect(throws: BridgeError.self) {
            _ = try await handler.handle(method: "connect", params: ["profile_name": "ghost"])
        }
    }

    @Test func addProfileDefaultsToNoAIAccess() async throws {
        let (handler, profiles, _) = makeHandler()
        let result = try await handler.handle(method: "add_profile", params: [
            "name": "agent-made",
            "kind": "ssh",
            "host": "10.9.9.9",
            "username": "root",
            "tags": "lab, iot"
        ]) as? [String: String]
        #expect(result?["ai_allowed"] == "false", "agent-created profiles must not be agent-usable until the user opts in")

        let created = await MainActor.run { profiles.profile(named: "agent-made") }
        #expect(created?.aiAllowed == false)
        #expect(created?.tags == ["LAB", "IOT"], "tags are normalized to uppercase")
    }

    @Test func addProfileRejectsOptionInjectionHost() async {
        let (handler, _, _) = makeHandler()
        await #expect(throws: BridgeError.self, "hosts that look like ssh options must be rejected") {
            _ = try await handler.handle(method: "add_profile", params: [
                "name": "evil", "kind": "ssh", "host": "-oProxyCommand=touch /tmp/pwned"
            ])
        }
    }

    @Test func removeProfileByName() async throws {
        let (handler, profiles, _) = makeHandler()
        var profile = ConnectionProfile()
        profile.name = "temp"
        await MainActor.run { profiles.upsert(profile) }
        _ = try await handler.handle(method: "remove_profile", params: ["name": "temp"])
        let gone = await MainActor.run { profiles.profile(named: "temp") }
        #expect(gone == nil)
    }

    @Test func sessionToolsRejectUnknownSession() async {
        let (handler, _, _) = makeHandler()
        for method in ["get_status", "read_output", "send_input", "run_command"] {
            await #expect(throws: (any Error).self, "\(method) must fail for unknown session") {
                _ = try await handler.handle(method: method, params: [
                    "session_id": "does-not-exist", "command": "x", "text": "x"
                ])
            }
        }
    }

    @Test func listSerialPortsReturnsDevPaths() async throws {
        let (handler, _, _) = makeHandler()
        let ports = try await handler.handle(method: "list_serial_ports", params: [:]) as? [String]
        #expect(ports != nil)
        #expect(ports!.allSatisfy { $0.hasPrefix("/dev/") })
    }

    @Test func vaultSetAndGetOverBridge() async throws {
        let (handler, _, vault) = makeHandler()
        let name = "TEST_BRIDGE_\(UInt32.random(in: 0..<9999))"
        defer { vault.remove(name: name) }

        _ = try await handler.handle(method: "vault_set", params: [
            "name": name, "value": "42", "description": "answer", "policy": "open"
        ])
        let got = try await handler.handle(method: "vault_get", params: ["name": name]) as? [String: String]
        #expect(got?["value"] == "42")

        let listing = try await handler.handle(method: "vault_list", params: [:]) as? [[String: String]]
        #expect(listing?.contains { $0["name"] == name } == true)
    }

    @Test func vaultGetSecretRefusesOverBridge() async throws {
        let (handler, _, vault) = makeHandler()
        let name = "TEST_BRIDGE_SEC_\(UInt32.random(in: 0..<9999))"
        defer { vault.remove(name: name) }
        _ = try await handler.handle(method: "vault_set", params: [
            "name": name, "value": "classified", "policy": "secret"
        ])
        do {
            _ = try await handler.handle(method: "vault_get", params: ["name": name])
            Issue.record("secret vault_get must refuse")
        } catch {
            #expect(error.localizedDescription.contains("never returned"))
        }
    }

    @Test func vaultSetInvalidPolicyFallsBackToOpen() async throws {
        let (handler, _, vault) = makeHandler()
        let name = "TEST_BRIDGE_POL_\(UInt32.random(in: 0..<9999))"
        defer { vault.remove(name: name) }
        let result = try await handler.handle(method: "vault_set", params: [
            "name": name, "value": "v", "policy": "bogus"
        ]) as? [String: String]
        #expect(result?["policy"] == "open")
    }
}

/// Full-stack integration: PTY session + marker-based run_command through the
/// same path MCP agents use.
@Suite struct SessionIntegrationTests {

    @MainActor
    @Test func localSessionRunsCommandAndCapturesOutput() async throws {
        var profile = ConnectionProfile()
        profile.name = "itest-local"
        profile.kind = .local
        let session = SessionManager.shared.open(profile: profile, origin: .user)
        defer { SessionManager.shared.close(id: session.id) }

        // Give the shell a moment to start.
        try await Task.sleep(nanoseconds: 800_000_000)
        let result = await session.runCommand("echo barq_integration_$((6*7))", timeout: 15)
        #expect(result.output.contains("barq_integration_42"))
        #expect(result.exitCode == 0)

        let listing = SessionManager.shared.listing()
        #expect(listing.contains { $0["session_id"] == session.id })
    }
}
