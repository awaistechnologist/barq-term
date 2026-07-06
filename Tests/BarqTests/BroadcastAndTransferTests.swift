import Testing
import Foundation
@testable import Barq

@Suite struct BroadcastTests {

    @Test func targetsExcludeFocusedPane() {
        let targets = Broadcast.targets(in: ["1", "2", "3"], focused: "2")
        #expect(targets == ["1", "3"])
    }

    @Test func singlePaneHasNoTargets() {
        #expect(Broadcast.targets(in: ["1"], focused: "1").isEmpty)
    }

    @Test func focusedNotInListYieldsAll() {
        #expect(Broadcast.targets(in: ["1", "2"], focused: "9") == ["1", "2"])
    }
}

@Suite struct SFTPArgumentTests {

    @Test func sftpArgsUseHostAndPort() {
        var profile = ConnectionProfile()
        profile.kind = .ssh
        profile.host = "files.example.com"
        profile.username = "deploy"
        profile.port = 2222
        let args = SSHCommandBuilder.sftpArguments(for: profile)
        #expect(args.contains("-P"))
        #expect(args.contains("2222"))
        #expect(args.last == "deploy@files.example.com")
    }

    @Test func sftpArgsIncludeIdentity() {
        var profile = ConnectionProfile()
        profile.kind = .ssh
        profile.host = "h"
        profile.authType = .key
        profile.identityFile = "~/.ssh/id"
        let args = SSHCommandBuilder.sftpArguments(for: profile)
        #expect(args.contains("-i"))
        #expect(args.contains("IdentitiesOnly=yes"))
    }

    @Test func sftpArgsHonorJumpHost() {
        var profile = ConnectionProfile()
        profile.kind = .ssh
        profile.host = "h"
        profile.jumpHost = JumpHost(enabled: true, host: "bastion", port: 22, username: "g", identityFile: "")
        let args = SSHCommandBuilder.sftpArguments(for: profile)
        #expect(args.contains("-J"))
        #expect(args.contains("g@bastion"))
    }
}
