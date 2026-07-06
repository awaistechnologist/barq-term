import Testing
import Foundation
@testable import Barq

@Suite struct ModelTests {

    @Test func testProfileRoundTrip() throws {
        var profile = ConnectionProfile()
        profile.name = "router"
        profile.kind = .ssh
        profile.host = "192.168.1.1"
        profile.username = "admin"
        profile.tags = ["LAB", "ROUTERS"]
        profile.aiAllowed = true
        profile.jumpHost = JumpHost(enabled: true, host: "bastion", port: 22, username: "gate", identityFile: "~/.ssh/id")
        profile.portForwards = [PortForward(kind: .dynamic, bindAddress: "127.0.0.1", listenPort: 1080, targetHost: "", targetPort: 0, enabled: true)]

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ConnectionProfile.self, from: data)
        #expect(decoded == profile)
    }

    @Test func testVaultNameValidation() {
        #expect(VaultItem.isValidName("STAGING_IP"))
        #expect(VaultItem.isValidName("A1_B2"))
        #expect(!(VaultItem.isValidName("staging_ip")))
        #expect(!(VaultItem.isValidName("1BAD")))
        #expect(!(VaultItem.isValidName("BAD NAME")))
        #expect(!(VaultItem.isValidName("${BARQ:X}")))
    }

    @Test func testVaultItemRoundTrip() throws {
        let item = VaultItem(name: "DEPLOY_KEY", summary: "prod deploy token", policy: .secret, scope: .global)
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(VaultItem.self, from: data)
        #expect(decoded.name == "DEPLOY_KEY")
        #expect(decoded.policy == .secret)
    }

    @Test func testProfileTargetStrings() {
        var ssh = ConnectionProfile()
        ssh.kind = .ssh
        ssh.host = "server"
        ssh.username = "me"
        ssh.port = 2222
        #expect(ssh.target == "me@server:2222")

        var serial = ConnectionProfile()
        serial.kind = .serial
        serial.serialDevice = "/dev/cu.usbserial-0001"
        serial.baudRate = 9600
        #expect(serial.target == "/dev/cu.usbserial-0001 @ 9600")
    }

    @Test func testThemeColorParsing() {
        let color = BarqTheme.hexToTermColor("#ff8000")
        #expect(color.red == 0xFF * 257)
        #expect(color.green == 0x80 * 257)
        #expect(color.blue == 0)
        #expect(Themes.all.count == 6)
        #expect(Themes.theme(id: "nonexistent").id == "catppuccin-mocha", "unknown theme falls back to default")
    }

    @Test func testSplitNodeOperations() {
        var node = SplitNode.leaf("1")
        node = node.splitting(sessionID: "1", with: "2", direction: .horizontal)
        #expect(node.sessionIDs == ["1", "2"])
        node = node.splitting(sessionID: "2", with: "3", direction: .vertical)
        #expect(node.sessionIDs == ["1", "2", "3"])
        let removed = node.removing(sessionID: "2")
        #expect(removed?.sessionIDs == ["1", "3"])
        let single = SplitNode.leaf("9").removing(sessionID: "9")
        #expect(single == nil)
    }

    @Test func testAICommandExtraction() {
        #expect(AIService.extractCommand(from: "ls -la") == "ls -la")
        #expect(AIService.extractCommand(from: "```sh\ndf -h\n```") == "df -h")
        #expect(AIService.extractCommand(from: "```\nuptime\n```") == "uptime")
        #expect(AIService.extractCommand(from: "$ whoami") == "whoami")
    }
}
