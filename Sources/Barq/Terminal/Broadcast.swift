import Foundation

/// Pure routing logic for "broadcast input": when enabled, keystrokes in the
/// focused pane are mirrored to the *other* panes in the same tab.
enum Broadcast {
    /// Sessions that should receive a mirrored copy of input typed into
    /// `focusedSessionID`. The focused pane handles its own input natively, so
    /// it is excluded.
    static func targets(in tabSessionIDs: [String], focused focusedSessionID: String) -> [String] {
        tabSessionIDs.filter { $0 != focusedSessionID }
    }
}
