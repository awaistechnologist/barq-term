import Foundation
import Combine

extension Notification.Name {
    /// Posted when a session is opened (by the user or an agent) so the UI can
    /// attach a tab.
    static let barqSessionOpened = Notification.Name("BarqSessionOpened")
    static let barqSessionClosed = Notification.Name("BarqSessionClosed")
}

/// Registry of live sessions, shared by the UI, AI layer and MCP bridge.
@MainActor
final class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published private(set) var sessions: [TerminalSession] = []
    private var nextID = 1

    private init() {}

    @discardableResult
    func open(profile: ConnectionProfile, origin: SessionOrigin = .user) -> TerminalSession {
        let session = TerminalSession(
            id: String(nextID),
            profile: profile,
            origin: origin,
            settings: SettingsStore.shared
        )
        nextID += 1
        sessions.append(session)
        session.start()
        NotificationCenter.default.post(name: .barqSessionOpened, object: session)
        return session
    }

    func session(id: String) -> TerminalSession? {
        sessions.first { $0.id == id }
    }

    func close(id: String) {
        guard let session = session(id: id) else { return }
        session.terminate()
        sessions.removeAll { $0.id == id }
        NotificationCenter.default.post(name: .barqSessionClosed, object: session)
    }

    /// Snapshot for MCP `list_sessions`.
    func listing() -> [[String: String]] {
        sessions.map {
            [
                "session_id": $0.id,
                "profile": $0.profile.name,
                "kind": $0.profile.kind.rawValue,
                "target": $0.profile.target,
                "status": $0.status.label,
                "origin": $0.origin.rawValue
            ]
        }
    }
}
