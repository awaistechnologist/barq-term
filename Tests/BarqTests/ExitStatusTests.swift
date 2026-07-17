import Testing
@testable import Barq

@Suite struct ExitStatusTests {
    @Test func testNormalExitIsShifted() {
        // raw wait() status 512 == 2 << 8 -> exit code 2
        #expect(ExitStatus.normalize(512) == 2)
    }

    @Test func testZeroStaysZero() {
        #expect(ExitStatus.normalize(0) == 0)
    }

    @Test func testSSHConnectionError() {
        // ssh exits 255 -> raw 255 << 8 == 65280 -> 255
        #expect(ExitStatus.normalize(65280) == 255)
    }

    @Test func testKilledBySignal() {
        // SIGTERM (15) with no core dump -> 128 + 15 == 143
        #expect(ExitStatus.normalize(15) == 143)
    }

    @Test func testNilStaysNil() {
        #expect(ExitStatus.normalize(nil) == nil)
    }
}
