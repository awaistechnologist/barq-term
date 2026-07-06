import Foundation
import SwiftUI
import Combine

enum SplitDirection {
    case horizontal // side by side
    case vertical   // stacked
}

/// Binary split tree for a tab's terminals.
indirect enum SplitNode {
    case leaf(String) // session id
    case split(SplitDirection, SplitNode, SplitNode)

    var sessionIDs: [String] {
        switch self {
        case .leaf(let id): return [id]
        case .split(_, let a, let b): return a.sessionIDs + b.sessionIDs
        }
    }

    /// Replace the leaf holding `sessionID` with a split of it and `newID`.
    func splitting(sessionID: String, with newID: String, direction: SplitDirection) -> SplitNode {
        switch self {
        case .leaf(let id) where id == sessionID:
            return .split(direction, .leaf(id), .leaf(newID))
        case .leaf:
            return self
        case .split(let dir, let a, let b):
            return .split(dir,
                          a.splitting(sessionID: sessionID, with: newID, direction: direction),
                          b.splitting(sessionID: sessionID, with: newID, direction: direction))
        }
    }

    /// Remove a leaf; returns nil if the tree becomes empty.
    func removing(sessionID: String) -> SplitNode? {
        switch self {
        case .leaf(let id):
            return id == sessionID ? nil : self
        case .split(let dir, let a, let b):
            let na = a.removing(sessionID: sessionID)
            let nb = b.removing(sessionID: sessionID)
            switch (na, nb) {
            case (nil, nil): return nil
            case (let node?, nil), (nil, let node?): return node
            case (let na?, let nb?): return .split(dir, na, nb)
            }
        }
    }
}

struct TerminalTab: Identifiable {
    let id = UUID()
    var root: SplitNode
    var focusedSessionID: String
    var customTitle: String?
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let profiles = ProfileStore()
    let vault = VaultStore()
    let sessions = SessionManager.shared
    let settings = SettingsStore.shared

    @Published var tabs: [TerminalTab] = []
    @Published var selectedTabID: UUID?
    @Published var sidebarVisible = true
    @Published var aiPanelVisible = false
    @Published var paletteVisible = false
    @Published var composerVisible = false
    @Published var editingProfile: ConnectionProfile?
    @Published var showingProfileEditor = false

    private var bridge: BridgeServer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        NotificationCenter.default.publisher(for: .barqSessionOpened)
            .compactMap { $0.object as? TerminalSession }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] session in
                guard let self else { return }
                // Attach a tab for sessions we did not open ourselves (agents).
                if session.origin == .agent {
                    self.attachTab(for: session)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .barqSessionFocused)
            .compactMap { $0.object as? String }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessionID in
                guard let self else { return }
                if let idx = self.tabs.firstIndex(where: { $0.root.sessionIDs.contains(sessionID) }) {
                    self.tabs[idx].focusedSessionID = sessionID
                }
            }
            .store(in: &cancellables)
    }

    func startServices() {
        if settings.mcpEnabled {
            let handler = BridgeHandler(profiles: profiles, vault: vault)
            let server = BridgeServer(handler: handler)
            server.start()
            bridge = server
        }
        Task { await AIService.shared.refreshOllama() }
    }

    // MARK: Tabs & sessions

    var selectedTab: TerminalTab? {
        tabs.first { $0.id == selectedTabID }
    }

    var focusedSession: TerminalSession? {
        guard let tab = selectedTab else { return nil }
        return sessions.session(id: tab.focusedSessionID)
    }

    func newLocalTab() {
        let profile = profiles.profiles.first { $0.kind == .local } ?? {
            var p = ConnectionProfile()
            p.name = "Local"
            p.kind = .local
            return p
        }()
        connect(profile: profile)
    }

    func connect(profile: ConnectionProfile) {
        let session = sessions.open(profile: profile, origin: .user)
        attachTab(for: session)
    }

    private func attachTab(for session: TerminalSession) {
        let tab = TerminalTab(root: .leaf(session.id), focusedSessionID: session.id)
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func closeTab(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        for sessionID in tab.root.sessionIDs {
            sessions.close(id: sessionID)
        }
        tabs.removeAll { $0.id == id }
        if selectedTabID == id {
            selectedTabID = tabs.last?.id
        }
    }

    func closeSession(_ sessionID: String) {
        sessions.close(id: sessionID)
        for idx in tabs.indices {
            if tabs[idx].root.sessionIDs.contains(sessionID) {
                if let newRoot = tabs[idx].root.removing(sessionID: sessionID) {
                    tabs[idx].root = newRoot
                    if tabs[idx].focusedSessionID == sessionID {
                        tabs[idx].focusedSessionID = newRoot.sessionIDs[0]
                    }
                } else {
                    let tabID = tabs[idx].id
                    tabs.remove(at: idx)
                    if selectedTabID == tabID { selectedTabID = tabs.last?.id }
                }
                break
            }
        }
    }

    func splitFocused(direction: SplitDirection) {
        guard var tab = selectedTab, let focused = focusedSession else { return }
        let session = sessions.open(profile: focused.profile, origin: .user)
        tab.root = tab.root.splitting(sessionID: focused.id, with: session.id, direction: direction)
        tab.focusedSessionID = session.id
        tabs = tabs.map { $0.id == tab.id ? tab : $0 }
    }

    func title(for tab: TerminalTab) -> String {
        if let custom = tab.customTitle { return custom }
        if let session = sessions.session(id: tab.focusedSessionID) {
            return session.title
        }
        return "Terminal"
    }
}

extension Notification.Name {
    static let barqSessionFocused = Notification.Name("BarqSessionFocused")
}
