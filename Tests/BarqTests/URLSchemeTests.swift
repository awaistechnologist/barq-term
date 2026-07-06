import Testing
import Foundation
@testable import Barq

@Suite struct URLSchemeTests {

    @Test func parsesConnect() {
        let action = BarqURL.parse(URL(string: "barq://connect/staging-server")!)
        #expect(action == .connectProfile("staging-server"))
    }

    @Test func parsesConnectWithEncoding() {
        let action = BarqURL.parse(URL(string: "barq://connect/My%20Router")!)
        #expect(action == .connectProfile("My Router"))
    }

    @Test func parsesOpenPath() {
        let action = BarqURL.parse(URL(string: "barq://open?path=/Users/me/code")!)
        #expect(action == .openPath("/Users/me/code"))
    }

    @Test func parsesSSHQuick() {
        let action = BarqURL.parse(URL(string: "barq://ssh?host=box&user=root&port=2222")!)
        #expect(action == .sshQuick(host: "box", user: "root", port: 2222))
    }

    @Test func sshQuickWithoutOptionalParts() {
        let action = BarqURL.parse(URL(string: "barq://ssh?host=box")!)
        #expect(action == .sshQuick(host: "box", user: nil, port: nil))
    }

    @Test func rejectsWrongSchemeOrJunk() {
        #expect(BarqURL.parse(URL(string: "https://connect/x")!) == .unknown)
        #expect(BarqURL.parse(URL(string: "barq://ssh")!) == .unknown)
        #expect(BarqURL.parse(URL(string: "barq://open")!) == .unknown)
        #expect(BarqURL.parse(URL(string: "barq://bogus/x")!) == .unknown)
    }
}
