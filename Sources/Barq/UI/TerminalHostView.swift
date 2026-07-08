import SwiftUI
import SwiftTerm
import AppKit

/// Hosts a session's SwiftTerm NSView inside SwiftUI, and — crucially — drives
/// keyboard first-responder so typing actually goes to the terminal instead of
/// the sidebar search field.
struct TerminalRepresentable: NSViewRepresentable {
    let session: TerminalSession
    /// True when this pane is the focused pane of the selected tab.
    let isActive: Bool

    final class Coordinator {
        let sessionID: String
        weak var view: TerminalView?
        var clickMonitor: Any?
        var focusObserver: NSObjectProtocol?

        init(sessionID: String) { self.sessionID = sessionID }

        /// Make the terminal the window's first responder, retrying briefly
        /// until the view is actually in a window.
        func grabFocus(attemptsLeft: Int = 12) {
            guard let view else { return }
            if let window = view.window {
                if window.firstResponder !== view {
                    window.makeFirstResponder(view)
                }
            } else if attemptsLeft > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
                    self?.grabFocus(attemptsLeft: attemptsLeft - 1)
                }
            }
        }

        func teardown() {
            if let monitor = clickMonitor { NSEvent.removeMonitor(monitor); clickMonitor = nil }
            if let observer = focusObserver { NotificationCenter.default.removeObserver(observer); focusObserver = nil }
        }

        deinit { teardown() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(sessionID: session.id) }

    func makeNSView(context: Context) -> TerminalView {
        let view = session.terminalView!
        let coordinator = context.coordinator
        coordinator.view = view
        let sessionID = session.id

        // Click to focus this pane (left) and middle-click paste.
        coordinator.clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .otherMouseDown]) { [weak view, weak session, weak coordinator] event in
            guard let view, let window = view.window, event.window === window else { return event }
            let point = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(point) else { return event }
            if event.type == .leftMouseDown {
                // Explicitly steal keyboard focus from the sidebar/search etc.
                window.makeFirstResponder(view)
                coordinator?.grabFocus()
                NotificationCenter.default.post(name: .barqSessionFocused, object: sessionID)
            } else if event.buttonNumber == 2 {
                if let text = NSPasteboard.general.string(forType: .string) {
                    Task { @MainActor in session?.paste(text) }
                }
                return nil // consume the middle click
            }
            return event
        }

        // Explicit focus requests (tab switch, new session, overlay dismiss).
        coordinator.focusObserver = NotificationCenter.default.addObserver(
            forName: .barqFocusTerminal, object: nil, queue: .main
        ) { [weak coordinator] note in
            guard let coordinator, note.object as? String == sessionID else { return }
            coordinator.grabFocus()
        }

        if isActive { coordinator.grabFocus() }
        return view
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        // Take focus when this pane becomes the active one, but never yank it
        // away from a text field the user is deliberately editing (AI panel,
        // search overlay): only claim it if nothing or another terminal holds it.
        guard isActive, let window = nsView.window else { return }
        let current = window.firstResponder
        let heldByEditableField = (current as? NSView)?.isKind(of: NSTextView.self) ?? false
        if current !== nsView && !heldByEditableField {
            context.coordinator.grabFocus()
        }
    }

    static func dismantleNSView(_ nsView: TerminalView, coordinator: Coordinator) {
        coordinator.teardown()
    }
}

/// Renders one terminal pane with a focus ring and exit overlay.
struct TerminalPaneView: View {
    @ObservedObject var session: TerminalSession
    let isFocused: Bool
    let theme: BarqTheme

    var body: some View {
        ZStack {
            TerminalRepresentable(session: session, isActive: isFocused)
            if case .exited(let code) = session.status {
                VStack(spacing: 8) {
                    Image(systemName: "bolt.slash")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("Session ended\(code.map { " (exit \($0))" } ?? "")")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Close Pane") {
                        AppState.shared.closeSession(session.id)
                    }
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .background(theme.chrome)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isFocused ? theme.electric.opacity(0.6) : theme.hairline, lineWidth: isFocused ? 1.5 : 1)
        )
        .shadow(color: .black.opacity(theme.isDark ? 0.28 : 0.10), radius: 6, y: 2)
        .padding(BarqDesign.s2)
    }
}

/// Recursive renderer for a tab's split tree.
struct SplitNodeView: View {
    let node: SplitNode
    let focusedSessionID: String
    let theme: BarqTheme

    var body: some View {
        switch node {
        case .leaf(let sessionID):
            if let session = SessionManager.shared.session(id: sessionID) {
                TerminalPaneView(session: session, isFocused: sessionID == focusedSessionID, theme: theme)
            } else {
                Color.clear
            }
        case .split(let direction, let first, let second):
            if direction == .horizontal {
                HSplitView {
                    SplitNodeView(node: first, focusedSessionID: focusedSessionID, theme: theme)
                    SplitNodeView(node: second, focusedSessionID: focusedSessionID, theme: theme)
                }
            } else {
                VSplitView {
                    SplitNodeView(node: first, focusedSessionID: focusedSessionID, theme: theme)
                    SplitNodeView(node: second, focusedSessionID: focusedSessionID, theme: theme)
                }
            }
        }
    }
}
