import Testing
import Foundation
@testable import Barq

@Suite struct SSHCommandBuilderTests {

    func makeProfile() -> ConnectionProfile {
        var profile = ConnectionProfile()
        profile.name = "test"
        profile.kind = .ssh
        profile.host = "10.0.0.5"
        profile.username = "pi"
        return profile
    }

    @Test func testBasicSSH() {
        let args = SSHCommandBuilder.sshArguments(for: makeProfile())
        #expect(args.last == "pi@10.0.0.5")
        #expect(!(args.contains("-p")), "default port 22 needs no -p")
    }

    @Test func testCustomPort() {
        var profile = makeProfile()
        profile.port = 2222
        let args = SSHCommandBuilder.sshArguments(for: profile)
        #expect(args.contains("-p"))
        #expect(args[args.firstIndex(of: "-p")! + 1] == "2222")
    }

    @Test func testIdentityFile() {
        var profile = makeProfile()
        profile.authType = .key
        profile.identityFile = "~/.ssh/id_ed25519"
        let args = SSHCommandBuilder.sshArguments(for: profile)
        let idx = args.firstIndex(of: "-i")
        #expect(idx != nil)
        #expect(args[idx! + 1].hasSuffix("/.ssh/id_ed25519"))
        #expect(!(args[idx! + 1].contains("~")), "tilde must be expanded")
        #expect(args.contains("IdentitiesOnly=yes"))
    }

    @Test func testAgentForward() {
        var profile = makeProfile()
        profile.agentForward = true
        #expect(SSHCommandBuilder.sshArguments(for: profile).contains("-A"))
        var off = makeProfile()
        off.agentForward = false
        #expect(!SSHCommandBuilder.sshArguments(for: off).contains("-A"))
    }

    @Test func testCustomSSHOptions() {
        var profile = makeProfile()
        profile.extraSSHOptions = ["StrictHostKeyChecking=no", "ConnectTimeout=5"]
        let args = SSHCommandBuilder.sshArguments(for: profile)
        #expect(args.contains("StrictHostKeyChecking=no"))
        #expect(args.contains("ConnectTimeout=5"))
    }

    @Test func testKeyTextUsesIdentityFileWhenResolved() {
        var profile = makeProfile()
        profile.authType = .keyText
        // After materialization the resolver sets identityFile to a temp path;
        // the builder must then emit -i for pasted-key auth too.
        profile.identityFile = "/tmp/barq-key-xyz"
        let args = SSHCommandBuilder.sshArguments(for: profile)
        let idx = args.firstIndex(of: "-i")
        #expect(idx != nil)
        #expect(args[idx! + 1] == "/tmp/barq-key-xyz")
        #expect(SSHCommandBuilder.usesIdentityFile(profile))
    }

    @Test func testJumpHost() {
        var profile = makeProfile()
        profile.jumpHost = JumpHost(enabled: true, host: "bastion.example.com", port: 2200, username: "gate", identityFile: "")
        let args = SSHCommandBuilder.sshArguments(for: profile)
        let idx = args.firstIndex(of: "-J")
        #expect(idx != nil)
        #expect(args[idx! + 1] == "gate@bastion.example.com:2200")
    }

    @Test func testPortForwards() {
        var profile = makeProfile()
        profile.portForwards = [
            PortForward(kind: .local, bindAddress: "127.0.0.1", listenPort: 8080, targetHost: "internal", targetPort: 80, enabled: true),
            PortForward(kind: .dynamic, bindAddress: "127.0.0.1", listenPort: 1080, targetHost: "", targetPort: 0, enabled: true),
            PortForward(kind: .remote, bindAddress: "0.0.0.0", listenPort: 9000, targetHost: "localhost", targetPort: 3000, enabled: false)
        ]
        let args = SSHCommandBuilder.sshArguments(for: profile)
        #expect(args.contains("-L"))
        #expect(args.contains("127.0.0.1:8080:internal:80"))
        #expect(args.contains("-D"))
        #expect(args.contains("127.0.0.1:1080"))
        #expect(!(args.contains("-R")), "disabled rules must be skipped")
    }

    @Test func testLegacySCPFlags() {
        var profile = makeProfile()
        profile.legacySCP = true
        let scp = SSHCommandBuilder.scpArguments(for: profile, localPath: "/tmp/f.bin", remotePath: "/opt/f.bin", upload: true)
        #expect(scp.contains("-O"))
        #expect(scp.contains("HostKeyAlgorithms=+ssh-rsa"))
        #expect(scp.last == "pi@10.0.0.5:/opt/f.bin")
    }

    @Test func testDestinationIsOptionGuarded() {
        // `--` must precede the destination so a hostile host can't be parsed
        // as an ssh option (CVE-class option injection).
        let args = SSHCommandBuilder.sshArguments(for: makeProfile())
        let dashDash = args.firstIndex(of: "--")
        #expect(dashDash != nil)
        #expect(args[dashDash! + 1] == "pi@10.0.0.5", "-- immediately precedes the destination")
        #expect(dashDash! == args.count - 2, "nothing but the destination follows --")
    }

    @Test func testScpDestinationOptionGuarded() {
        let scp = SSHCommandBuilder.scpArguments(for: makeProfile(), localPath: "/tmp/a", remotePath: "/tmp/b", upload: true)
        #expect(scp.contains("--"))
        let dashDash = scp.firstIndex(of: "--")!
        #expect(dashDash < scp.count - 2, "-- precedes the positional source/target args")
    }

    @Test func testIsSafeHost() {
        #expect(SSHCommandBuilder.isSafeHost("example.com"))
        #expect(SSHCommandBuilder.isSafeHost("10.0.0.1"))
        #expect(SSHCommandBuilder.isSafeHost("fe80::1%en0"))
        #expect(SSHCommandBuilder.isSafeHost("[::1]"))
        // Rejected: option-injection and shell/space metacharacters.
        #expect(!SSHCommandBuilder.isSafeHost("-oProxyCommand=touch /tmp/pwned"))
        #expect(!SSHCommandBuilder.isSafeHost("host with space"))
        #expect(!SSHCommandBuilder.isSafeHost("a;rm -rf /"))
        #expect(!SSHCommandBuilder.isSafeHost("$(whoami)"))
        #expect(!SSHCommandBuilder.isSafeHost(""))
    }

    @Test func testCloudflareAccessProxyCommand() {
        var profile = makeProfile()
        profile.cloudflareAccess = true
        let args = SSHCommandBuilder.sshArguments(for: profile)
        #expect(args.contains("ProxyCommand=cloudflared access ssh --hostname %h"))
        #expect(!args.contains("-J"))
    }

    @Test func testCloudflareOverridesJumpHost() {
        var profile = makeProfile()
        profile.cloudflareAccess = true
        profile.jumpHost = JumpHost(enabled: true, host: "b", port: 22, username: "u", identityFile: "")
        let args = SSHCommandBuilder.sshArguments(for: profile)
        #expect(!args.contains("-J"), "cloudflare takes precedence over jump host")
    }

    @Test func testSCPDownloadDirection() {
        let scp = SSHCommandBuilder.scpArguments(for: makeProfile(), localPath: "/tmp/out.log", remotePath: "/var/log/sys.log", upload: false)
        #expect(scp.last == "/tmp/out.log")
        #expect(scp[scp.count - 2] == "pi@10.0.0.5:/var/log/sys.log")
    }
}
