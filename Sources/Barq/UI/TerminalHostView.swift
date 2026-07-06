import SwiftUI
import SwiftTerm
import AppKit

/// Hosts a session's SwiftTerm NSView inside SwiftUI.
struct TerminalRepresentable: NSViewRepresentable {
    let session: TerminalSession

    final class Coordinator {
        var clickMonitor: Any?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> TerminalView {
        let view = session.terminalView!
        let sessionID = session.id
        // Focus tracking: clicking a pane marks its session focused.
        context.coordinator.clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak view] event in
            if let view, let window = view.window, event.window === window {
                let point = view.convert(event.locationInWindow, from: nil)
                if view.bounds.contains(point) {
                    NotificationCenter.default.post(name: .barqSessionFocused, object: sessionID)
                }
            }
            return event
        }
        return view
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {}

    static func dismantleNSView(_ nsView: TerminalView, coordinator: Coordinator) {
        if let monitor = coordinator.clickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

/// Renders one terminal pane with a focus ring and exit overlay.
struct TerminalPaneView: View {
    @ObservedObject var session: TerminalSession
    let isFocused: Bool
    let theme: BarqTheme

    var body: some View {
        ZStack {
            TerminalRepresentable(session: session)
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
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isFocused ? Color(nsColor: theme.accentColor).opacity(0.55) : .clear, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(2)
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
