import Testing
import Foundation
@testable import Barq

@Suite struct SSHConfigCodecTests {

    @Test func parsesBasicHostBlock() {
        let config = """
        Host webserver
            HostName 192.168.1.50
            User deploy
            Port 2222
            IdentityFile ~/.ssh/deploy_key
        """
        let profiles = SSHConfigCodec.parse(config)
        #expect(profiles.count == 1)
        let p = profiles[0]
        #expect(p.name == "webserver")
        #expect(p.host == "192.168.1.50")
        #expect(p.username == "deploy")
        #expect(p.port == 2222)
        #expect(p.authType == .key)
        #expect(p.identityFile == "~/.ssh/deploy_key")
    }

    @Test func skipsWildcardHosts() {
        let config = """
        Host *
            ServerAliveInterval 60

        Host realbox
            HostName 10.0.0.1
        """
        let profiles = SSHConfigCodec.parse(config)
        #expect(profiles.count == 1)
        #expect(profiles[0].name == "realbox")
    }

    @Test func parsesProxyJump() {
        let config = """
        Host internal
            HostName 10.0.0.9
            ProxyJump gate@bastion.example.com:2200
        """
        let p = SSHConfigCodec.parse(config)[0]
        #expect(p.jumpHost.enabled)
        #expect(p.jumpHost.username == "gate")
        #expect(p.jumpHost.host == "bastion.example.com")
        #expect(p.jumpHost.port == 2200)
    }

    @Test func parsesCloudflareProxyCommand() {
        let config = """
        Host cf
            HostName secure.example.com
            ProxyCommand cloudflared access ssh --hostname %h
        """
        #expect(SSHConfigCodec.parse(config)[0].cloudflareAccess)
    }

    @Test func ignoresCommentsAndBlanks() {
        let config = """
        # a comment
        Host x

            HostName 1.2.3.4
        """
        let profiles = SSHConfigCodec.parse(config)
        #expect(profiles.count == 1)
        #expect(profiles[0].host == "1.2.3.4")
    }

    @Test func generateRoundTrips() {
        var profile = ConnectionProfile()
        profile.name = "myhost"
        profile.kind = .ssh
        profile.host = "example.com"
        profile.username = "me"
        profile.port = 2022
        profile.authType = .key
        profile.identityFile = "~/.ssh/id"

        let text = SSHConfigCodec.generate([profile])
        let reparsed = SSHConfigCodec.parse(text)[0]
        #expect(reparsed.name == "myhost")
        #expect(reparsed.host == "example.com")
        #expect(reparsed.username == "me")
        #expect(reparsed.port == 2022)
    }

    @Test func generateEmitsProxyJumpAndCloudflare() {
        var jump = ConnectionProfile()
        jump.name = "j"; jump.kind = .ssh; jump.host = "h"
        jump.jumpHost = JumpHost(enabled: true, host: "b", port: 22, username: "u", identityFile: "")
        #expect(SSHConfigCodec.generate([jump]).contains("ProxyJump u@b"))

        var cf = ConnectionProfile()
        cf.name = "c"; cf.kind = .ssh; cf.host = "h"; cf.cloudflareAccess = true
        #expect(SSHConfigCodec.generate([cf]).contains("cloudflared access ssh"))
    }
}

@Suite struct ChromeProxyLauncherTests {

    @Test func allTrafficUsesProxyServer() {
        let args = ChromeProxyLauncher.arguments(port: 1080, mode: .all, hosts: [], pacPath: nil, profileDir: "/tmp/x")
        #expect(args.contains("--proxy-server=socks5://127.0.0.1:1080"))
        #expect(!args.contains { $0.hasPrefix("--proxy-bypass-list") })
    }

    @Test func excludeAddsBypassList() {
        let args = ChromeProxyLauncher.arguments(port: 1080, mode: .exclude, hosts: ["*.corp.com", "10.0.0.1"], pacPath: nil, profileDir: "/tmp/x")
        let bypass = args.first { $0.hasPrefix("--proxy-bypass-list=") }
        #expect(bypass != nil)
        #expect(bypass!.contains("*.corp.com"))
        #expect(bypass!.contains("<local>"))
    }

    @Test func includeUsesPacURL() {
        let args = ChromeProxyLauncher.arguments(port: 1080, mode: .include, hosts: ["*.corp.com"], pacPath: "/tmp/p.pac", profileDir: "/tmp/x")
        #expect(args.contains("--proxy-pac-url=file:///tmp/p.pac"))
    }

    @Test func pacScriptHandlesWildcardExactAndCIDR() {
        let pac = ChromeProxyLauncher.pacScript(port: 1080, hosts: ["*.corp.com", "internal.host", "192.168.2.0/24"])
        #expect(pac.contains("dnsDomainIs(host, \".corp.com\")"))
        #expect(pac.contains("host == \"internal.host\""))
        #expect(pac.contains("isInNet(host, \"192.168.2.0\", \"255.255.255.0\")"))
        #expect(pac.contains("SOCKS5 127.0.0.1:1080"))
    }

    @Test func cidrMaskComputation() {
        #expect(ChromeProxyLauncher.cidrMask(24) == "255.255.255.0")
        #expect(ChromeProxyLauncher.cidrMask(16) == "255.255.0.0")
        #expect(ChromeProxyLauncher.cidrMask(8) == "255.0.0.0")
        #expect(ChromeProxyLauncher.cidrMask(0) == "0.0.0.0")
    }

    @Test func emptyPacIsSafe() {
        let pac = ChromeProxyLauncher.pacScript(port: 1080, hosts: [])
        #expect(pac.contains("return \"DIRECT\""))
    }
}
