import Testing
import Foundation
@testable import Barq

/// Regression coverage for the keyboard-focus routing bug where typing landed
/// in the sidebar search instead of the terminal. The AppKit first-responder
/// call can't be unit-tested headlessly, but the pure logic that picks *which*
/// session should receive focus can — and it's what drives the fix.
@Suite struct FocusTests {

    func tab(focused: String) -> TerminalTab {
        TerminalTab(root: .leaf(focused), focusedSessionID: focused)
    }

    @Test func picksFocusedPaneOfSelectedTab() {
        let a = tab(focused: "sess-A"), b = tab(focused: "sess-B")
        let tabs = [a, b]
        #expect(AppState.activeSessionID(tabs: tabs, selectedTabID: b.id) == "sess-B")
        #expect(AppState.activeSessionID(tabs: tabs, selectedTabID: a.id) == "sess-A")
    }

    @Test func nilWhenNothingSelected() {
        let tabs = [tab(focused: "sess-A")]
        #expect(AppState.activeSessionID(tabs: tabs, selectedTabID: nil) == nil)
    }

    @Test func nilWhenSelectionDangling() {
        let tabs = [tab(focused: "sess-A")]
        #expect(AppState.activeSessionID(tabs: tabs, selectedTabID: UUID()) == nil)
    }

    @Test func nilWhenNoTabs() {
        #expect(AppState.activeSessionID(tabs: [], selectedTabID: UUID()) == nil)
    }
}
