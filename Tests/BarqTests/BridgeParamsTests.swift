import Testing
import Foundation
@testable import Barq

@Suite struct BridgeParamsTests {
    @Test func testPlainString() {
        #expect(BridgeParams.string(["session_id": "1"], "session_id") == "1")
        #expect(BridgeParams.string(["session_id": "abc"], "session_id") == "abc")
    }

    @Test func testNumericValueCoercedToString() {
        // The bug: an agent re-sends session_id "1" as the number 1.
        #expect(BridgeParams.string(["session_id": 1], "session_id") == "1")
        #expect(BridgeParams.string(["session_id": 16 as Int], "session_id") == "16")
        #expect(BridgeParams.string(["session_id": NSNumber(value: 18)], "session_id") == "18")
    }

    @Test func testMissingReturnsNil() {
        #expect(BridgeParams.string([:], "session_id") == nil)
        #expect(BridgeParams.string(["other": "x"], "session_id") == nil)
    }
}
