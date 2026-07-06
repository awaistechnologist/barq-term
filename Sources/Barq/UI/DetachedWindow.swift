import SwiftUI
import AppKit

/// Hosts a single torn-off session in its own NSWindow. The session's
/// TerminalView moves out of the main tab hierarchy into this window; closing
/// the window closes the session.
@MainActor
final class DetachedWindowManager {
    static let shared = DetachedWindowManager()
    private var controllers: [String: NSWindowController] = [:]

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
}

/// Bridges NSWindow close → session close.
private final class CloseObserver: NSObject, NSWindowDelegate {
    static let shared = CloseObserver()
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let hosting = window.contentViewController as? NSHostingController<DetachedTerminalView> else { return }
        let id = hosting.rootView.session.id
        Task { @MainActor in
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
    }
}
