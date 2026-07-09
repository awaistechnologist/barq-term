import SwiftUI
import AppKit

/// Hosts a single torn-off session in its own NSWindow. The session's
/// TerminalView moves out of the main tab hierarchy into this window; closing
/// the window closes the session.
@MainActor
final class DetachedWindowManager {
    static let shared = DetachedWindowManager()
    private var controllers: [String: NSWindowController] = [:]
    /// Sessions whose window is being closed for reattach — the close observer
    /// must NOT kill the session in that case.
    private var reattaching: Set<String> = []

    func detach(session: TerminalSession) {
        let hosting = NSHostingController(
            rootView: DetachedTerminalView(session: session, theme: SettingsStore.shared.theme)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = session.title
        window.setContentSize(NSSize(width: 760, height: 480))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        controllers[session.id] = controller
        window.delegate = CloseObserver.shared

        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func closeController(for sessionID: String) {
        controllers[sessionID] = nil
    }

    /// Close a detached window because its session is being merged back into the
    /// main window — keep the session alive. The flag is cleared by the close
    /// observer (which runs asynchronously), not here, so it's still set when
    /// `windowWillClose` fires.
    func closeForReattach(sessionID: String) {
        guard let controller = controllers[sessionID] else { return }
        reattaching.insert(sessionID)
        controllers[sessionID] = nil
        controller.close()
    }

    /// Returns true if this close is a reattach (and clears the flag), so the
    /// observer knows to keep the session alive.
    func consumeReattaching(_ sessionID: String) -> Bool {
        reattaching.remove(sessionID) != nil
    }
}

/// Bridges NSWindow close → session close.
private final class CloseObserver: NSObject, NSWindowDelegate {
    static let shared = CloseObserver()
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let hosting = window.contentViewController as? NSHostingController<DetachedTerminalView> else { return }
        let id = hosting.rootView.session.id
        Task { @MainActor in
            // Merging back into the main window keeps the session alive.
            if DetachedWindowManager.shared.consumeReattaching(id) { return }
            SessionManager.shared.close(id: id)
            DetachedWindowManager.shared.closeController(for: id)
        }
    }
}

struct DetachedTerminalView: View {
    @ObservedObject var session: TerminalSession
    let theme: BarqTheme

    var body: some View {
        TerminalPaneView(session: session, isFocused: true, theme: theme)
            .frame(minWidth: 400, minHeight: 240)
            .overlay(alignment: .topTrailing) {
                Button {
                    AppState.shared.reattachSession(session.id)
                } label: {
                    Label("Merge Back", systemImage: "arrow.uturn.left.square")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Return this session to the main window")
                .padding(8)
            }
    }
}
