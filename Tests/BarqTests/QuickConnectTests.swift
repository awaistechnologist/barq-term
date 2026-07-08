import Testing
import Foundation
@testable import Barq

@Suite struct QuickConnectTests {

    @Test func parsesUserHostPort() {
        let p = QuickConnect.profile(from: "deploy@10.0.0.5:2222")
        #expect(p?.username == "deploy")
        #expect(p?.host == "10.0.0.5")
        #expect(p?.port == 2222)
        #expect(p?.kind == .ssh)
    }

    @Test func parsesHostOnly() {
        let p = QuickConnect.profile(from: "example.com")
        #expect(p?.username == "")
        #expect(p?.host == "example.com")
        #expect(p?.port == 22)
    }

    @Test func stripsSSHScheme() {
        let p = QuickConnect.profile(from: "ssh://root@box")
        #expect(p?.username == "root")
        #expect(p?.host == "box")
    }

    @Test func namesProfileFromTarget() {
        #expect(QuickConnect.profile(from: "me@server")?.name == "me@server")
        #expect(QuickConnect.profile(from: "server")?.name == "server")
    }

    @Test func rejectsEmptyAndUnsafeHosts() {
        #expect(QuickConnect.profile(from: "") == nil)
        #expect(QuickConnect.profile(from: "   ") == nil)
        // Option-injection style host must be rejected (isSafeHost).
        #expect(QuickConnect.profile(from: "-oProxyCommand=touch /tmp/x") == nil)
    }

    @Test func nonNumericPortIsTreatedAsPartOfHost() {
        // "host:notaport" — the colon isn't a valid port, so no port split.
        let p = QuickConnect.profile(from: "myhost")
        #expect(p?.port == 22)
    }
}
