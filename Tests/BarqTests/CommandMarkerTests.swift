import Testing
import Foundation
@testable import Barq

@Suite struct CommandMarkerTests {

    @Test func testWrapIsPOSIX() {
        let wrapped = CommandMarker.wrap(command: "ls -la", token: "abc123")
        #expect(wrapped.hasPrefix("ls -la; printf"))
        #expect(wrapped.contains("__BARQ_abc123"))
        #expect(wrapped.contains("$?"))
    }

    @Test func testExtractIncomplete() {
        let result = CommandMarker.extract(output: "some partial output", token: "abc123", sentCommand: "ls")
        #expect(!(result.done))
        #expect(result.exitCode == nil)
    }

    @Test func testExtractComplete() {
        let output = "file1\nfile2\n__BARQ_abc123_0__\n"
        let result = CommandMarker.extract(output: output, token: "abc123", sentCommand: "ls")
        #expect(result.done)
        #expect(result.exitCode == 0)
        #expect(result.payload == "file1\nfile2")
    }

    @Test func testExtractNonZeroExit() {
        let output = "No such file\n__BARQ_abc123_2__\n"
        let result = CommandMarker.extract(output: output, token: "abc123", sentCommand: "ls /nope")
        #expect(result.done)
        #expect(result.exitCode == 2)
    }

    @Test func testEchoRemoval() {
        // Terminals echo the sent line (including the printf suffix) back.
        let echoed = "ls -la; printf '\\n__BARQ_abc123_%s__\\n' \"$?\"\ntotal 8\nfile1\n__BARQ_abc123_0__\n"
        let result = CommandMarker.extract(output: echoed, token: "abc123", sentCommand: "ls -la")
        #expect(result.done)
        #expect(!(result.payload.contains("__BARQ_")), "marker must not leak into payload")
        #expect(result.payload.contains("file1"))
    }

    @Test func testTokenUniqueness() {
        #expect(CommandMarker.makeToken() != CommandMarker.makeToken())
        #expect(CommandMarker.makeToken().count == 16)
    }
}

@Suite struct OutputBufferTests {

    @Test func testAppendAndTail() {
        let buffer = OutputBuffer(capacity: 64)
        let bytes = Array("hello world".utf8)
        buffer.append(bytes[...])
        #expect(buffer.tail() == "hello world")
        #expect(buffer.totalReceived == 11)
    }

    @Test func testCapacityRolling() {
        let buffer = OutputBuffer(capacity: 8)
        buffer.append(Array("0123456789".utf8)[...])
        #expect(buffer.tail() == "23456789")
        #expect(buffer.totalReceived == 10)
    }

    @Test func testSinceOffset() {
        let buffer = OutputBuffer()
        buffer.append(Array("first ".utf8)[...])
        let offset = buffer.totalReceived
        buffer.append(Array("second".utf8)[...])
        let (text, newOffset) = buffer.since(offset: offset)
        #expect(text == "second")
        #expect(newOffset == 12)
    }

    @Test func testANSIStripping() {
        let colored = "\u{1B}[31mred\u{1B}[0m normal \u{1B}]0;title\u{07}done\r\n"
        #expect(OutputBuffer.clean(colored) == "red normal done\n")
    }
}
