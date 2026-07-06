import Testing
import Foundation
@testable import Barq

@Suite struct TelnetParserTests {
    let IAC: UInt8 = 255, DONT: UInt8 = 254, DO: UInt8 = 253, WONT: UInt8 = 252, WILL: UInt8 = 251
    let SB: UInt8 = 250, SE: UInt8 = 240
    let ECHO: UInt8 = 1, SGA: UInt8 = 3, NAWS: UInt8 = 31

    func makeBackend() -> TelnetBackend {
        TelnetBackend(host: "test.invalid", port: 23)
    }

    @Test func plainDataPassesThrough() {
        let backend = makeBackend()
        let out = backend.parseTelnet(Array("login: ".utf8))
        #expect(out == Array("login: ".utf8))
    }

    @Test func escapedIACByteIsUnescaped() {
        let backend = makeBackend()
        let out = backend.parseTelnet([0x41, IAC, IAC, 0x42])
        #expect(out == [0x41, 0xFF, 0x42])
    }

    @Test func doUnknownOptionRefusedWithWont() {
        let backend = makeBackend()
        let out = backend.parseTelnet([IAC, DO, NAWS])
        #expect(out.isEmpty, "negotiation bytes must not reach the terminal")
        #expect(backend.lastNegotiationResponse == [IAC, WONT, NAWS])
    }

    @Test func doSGAAcceptedWithWill() {
        let backend = makeBackend()
        _ = backend.parseTelnet([IAC, DO, SGA])
        #expect(backend.lastNegotiationResponse == [IAC, WILL, SGA])
    }

    @Test func willEchoAcceptedWithDo() {
        let backend = makeBackend()
        _ = backend.parseTelnet([IAC, WILL, ECHO])
        #expect(backend.lastNegotiationResponse == [IAC, DO, ECHO])
    }

    @Test func willUnknownOptionRefusedWithDont() {
        let backend = makeBackend()
        _ = backend.parseTelnet([IAC, WILL, NAWS])
        #expect(backend.lastNegotiationResponse == [IAC, DONT, NAWS])
    }

    @Test func subnegotiationIsSwallowed() {
        let backend = makeBackend()
        let out = backend.parseTelnet([0x41] + [IAC, SB, NAWS, 0, 80, 0, 24, IAC, SE] + [0x42])
        #expect(out == [0x41, 0x42])
    }

    @Test func negotiationSplitAcrossPackets() {
        let backend = makeBackend()
        // IAC arrives at the end of one packet, verb+option in the next.
        let first = backend.parseTelnet([0x41, IAC])
        let second = backend.parseTelnet([DO, SGA, 0x42])
        #expect(first == [0x41])
        #expect(second == [0x42])
        #expect(backend.lastNegotiationResponse == [IAC, WILL, SGA])
    }

    @Test func mixedDataAndNegotiation() {
        let backend = makeBackend()
        let out = backend.parseTelnet(Array("ab".utf8) + [IAC, DO, SGA] + Array("cd".utf8))
        #expect(out == Array("abcd".utf8))
    }
}
