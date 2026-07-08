import Testing
import Foundation
@testable import Barq

@Suite struct SSHKeyMaterializerTests {

    func makeProfile(auth: AuthType) -> ConnectionProfile {
        var p = ConnectionProfile()
        p.name = "keytest"
        p.kind = .ssh
        p.host = "10.0.0.9"
        p.authType = auth
        return p
    }

    @Test func nonKeyTextProfilesPassThroughUnchanged() {
        let p = makeProfile(auth: .agent)
        let resolved = SSHKeyMaterializer.resolvedForConnect(p)
        #expect(resolved.identityFile == p.identityFile)
        #expect(resolved.authType == .agent)
    }

    @Test func keyTextIsWrittenToPrivateTempFileAndUsed() throws {
        let p = makeProfile(auth: .keyText)
        let pem = "-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----"
        Keychain.set(pem, for: p.pemTextKeychainKey)
        defer {
            Keychain.delete(p.pemTextKeychainKey)
            SSHKeyMaterializer.removeTempKey(for: p)
        }

        let resolved = SSHKeyMaterializer.resolvedForConnect(p)
        #expect(!resolved.identityFile.isEmpty, "a temp key path must be set")
        #expect(FileManager.default.fileExists(atPath: resolved.identityFile))

        // Content must round-trip and be newline-terminated for OpenSSH.
        let written = try String(contentsOfFile: resolved.identityFile, encoding: .utf8)
        #expect(written.hasPrefix("-----BEGIN OPENSSH PRIVATE KEY-----"))
        #expect(written.hasSuffix("\n"))

        // Permissions must be owner-only (0600).
        let attrs = try FileManager.default.attributesOfItem(atPath: resolved.identityFile)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
        #expect(perms == 0o600)
    }

    @Test func keyTextWithoutStoredKeyReturnsUnchanged() {
        let p = makeProfile(auth: .keyText) // nothing in Keychain
        let resolved = SSHKeyMaterializer.resolvedForConnect(p)
        #expect(resolved.identityFile.isEmpty)
    }

    @Test func removeTempKeyDeletesFile() {
        let p = makeProfile(auth: .keyText)
        Keychain.set("k\n", for: p.pemTextKeychainKey)
        defer { Keychain.delete(p.pemTextKeychainKey) }
        let path = SSHKeyMaterializer.writeTempKey(for: p)
        #expect(path != nil)
        #expect(FileManager.default.fileExists(atPath: path!))
        SSHKeyMaterializer.removeTempKey(for: p)
        #expect(!FileManager.default.fileExists(atPath: path!))
    }
}
