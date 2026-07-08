import Testing
import Foundation
@testable import Barq

@Suite struct AppVersionTests {

    @Test func parsesTagsWithVPrefix() {
        #expect(AppVersion.components("v0.7.1") == [0, 7, 1])
        #expect(AppVersion.components("1.2.3") == [1, 2, 3])
    }

    @Test func newerDetection() {
        #expect(AppVersion.isNewer("0.8.0", than: "0.7.1"))
        #expect(AppVersion.isNewer("v1.0.0", than: "0.9.9"))
        #expect(AppVersion.isNewer("0.7.2", than: "0.7.1"))
        #expect(!AppVersion.isNewer("0.7.1", than: "0.7.1"))
        #expect(!AppVersion.isNewer("0.7.0", than: "0.7.1"))
    }

    @Test func handlesDifferingComponentCounts() {
        #expect(AppVersion.isNewer("0.7.1.1", than: "0.7.1"))
        #expect(!AppVersion.isNewer("0.7", than: "0.7.0"))
        #expect(AppVersion.isNewer("1.0", than: "0.9.9"))
    }
}
