import Testing
import Foundation
@testable import Barq

@Suite struct OSC7Tests {

    @Test func parsesFileURLWithHostname() {
        #expect(OSC7.parsePath("file://Mac.local/Users/me/code") == "/Users/me/code")
    }

    @Test func parsesFileURLWithoutHostname() {
        #expect(OSC7.parsePath("file:///opt/project") == "/opt/project")
    }

    @Test func acceptsPlainAbsolutePaths() {
        #expect(OSC7.parsePath("/var/log") == "/var/log")
    }

    @Test func decodesPercentEncoding() {
        #expect(OSC7.parsePath("file://host/Users/me/My%20Projects") == "/Users/me/My Projects")
    }

    @Test func rejectsGarbage() {
        #expect(OSC7.parsePath(nil) == nil)
        #expect(OSC7.parsePath("") == nil)
        #expect(OSC7.parsePath("http://example.com/x") == nil)
        #expect(OSC7.parsePath("not a url") == nil)
    }
}
