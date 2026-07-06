import Foundation
import SwiftUI
import AppKit
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
    let snippets = SnippetStore()
    let sessions = SessionManager.shared
    let settings = SettingsStore.shared

    @Published var tabs: [TerminalTab] = []
    @Published var selectedTabID: UUID?
    @Published var sidebarVisible = UserDefaults.standard.object(forKey: "sidebarVisible") as? Bool ?? true {
        didSet { UserDefaults.standard.set(sidebarVisible, forKey: "sidebarVisible") }
    }
    @Published var aiPanelVisible = false
    @Published var paletteVisible = false
    @Published var composerVisible = false
    @Published var globalSearchVisible = false
    @Published var snippetsVisible = false
    /// When true, keystrokes in the focused pane mirror to sibling panes.
    @Published var broadcastInput = false
    @Published var editingProfile: ConnectionProfile?
    @Published var showingProfileEditor = false

    private var bridge: BridgeServer?
    private var cancellables = Set<AnyCancellable>()
    private var broadcastMonitor: Any?

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

        // Re-style every open terminal when appearance settings change.
        settings.$themeID
            .dropFirst()
            .map { _ in () }
            .merge(with: settings.$fontName.dropFirst().map { _ in () },
                   settings.$fontSize.dropFirst().map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.restyleAllSessions() }
            .store(in: &cancellables)
    }

    private func restyleAllSessions() {
        let theme = settings.theme
        for session in sessions.sessions {
            session.terminalView.applyBarqStyle(theme: theme, settings: settings)
        }
    }

    // MARK: Session restore

    private var restoreScheduled = false

    /// Persist the current tab set (debounced to the next runloop tick).
    func persistSessions() {
        guard !restoreScheduled else { return }
        restoreScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.restoreScheduled = false
            SessionRestore.save(SessionRestore.snapshot(from: self.tabs, sessions: self.sessions))
        }
    }

    /// Reopen tabs saved from a previous run. Returns true if anything was
    /// restored. Local sessions reopen in their last working directory.
    @discardableResult
    func restoreSessions() -> Bool {
        let saved = SessionRestore.load()
        guard !saved.isEmpty else { return false }
        var restoredAny = false
        for entry in saved {
            guard var profile = profiles.profile(id: entry.profileID) else { continue }
            if profile.kind == .local, let cwd = entry.workingDirectory {
                profile.workingDirectory = cwd
            }
            let session = sessions.open(profile: profile, origin: .user)
            let tab = TerminalTab(root: .leaf(session.id), focusedSessionID: session.id, customTitle: entry.customTitle)
            tabs.append(tab)
            selectedTabID = tab.id
            restoredAny = true
        }
        return restoredAny
    }

    func startServices() {
        if settings.mcpEnabled {
            let handler = BridgeHandler(profiles: profiles, vault: vault)
            let server = BridgeServer(handler: handler)
            server.start()
            bridge = server
        }
        Task { await AIService.shared.refreshOllama() }
        installBroadcastMonitor()
    }

    /// Mirror keystrokes to sibling panes while broadcast is enabled.
    private func installBroadcastMonitor() {
        broadcastMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.broadcastInput,
                  let tab = self.selectedTab,
                  let chars = event.characters, !chars.isEmpty else { return event }
            let targets = Broadcast.targets(in: tab.root.sessionIDs, focused: tab.focusedSessionID)
            for id in targets {
                self.sessions.session(id: id)?.send(chars)
            }
            return event // focused pane still handles it natively
        }
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

    /// Open a local shell rooted at `path` (Finder "Open with Barq").
    func openLocalTab(in path: String) {
        var profile = ConnectionProfile()
        profile.name = (path as NSString).lastPathComponent
        profile.kind = .local
        profile.workingDirectory = path
        connect(profile: profile)
    }

    /// Handle a barq:// deep link. Deep links can be triggered by any webpage,
    /// so every action requires explicit user confirmation before it runs, and
    /// ad-hoc ssh hosts are validated to block option injection.
    func handleURL(_ url: URL) {
        switch BarqURL.parse(url) {
        case .connectProfile(let name):
            guard let profile = profiles.profile(named: name) else { return }
            if confirmDeepLink("Open a connection to “\(profile.name)” (\(profile.target))?") {
                connect(profile: profile)
            }
        case .openPath(let path):
            if confirmDeepLink("Open a local shell in “\(path)”?") {
                openLocalTab(in: path)
            }
        case .sshQuick(let host, let user, let port):
            guard SSHCommandBuilder.isSafeHost(host) else { return }
            let who = user.map { "\($0)@" } ?? ""
            if confirmDeepLink("Open an SSH session to “\(who)\(host)”?") {
                var profile = ConnectionProfile()
                profile.name = host
                profile.kind = .ssh
                profile.host = host
                profile.username = user ?? ""
                profile.port = port ?? 22
                connect(profile: profile)
            }
        case .unknown:
            break
        }
    }

    private func confirmDeepLink(_ message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Open link in Barq?"
        alert.informativeText = "\(message)\n\nThis was requested by an external link."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    func connect(profile: ConnectionProfile, launch: SessionLaunch = .shell) {
        let session = sessions.open(profile: profile, origin: .user, launch: launch)
        attachTab(for: session)
    }

    private func attachTab(for session: TerminalSession) {
        let tab = TerminalTab(root: .leaf(session.id), focusedSessionID: session.id)
        tabs.append(tab)
        selectedTabID = tab.id
        persistSessions()
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
        persistSessions()
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

    /// Move the focused session into its own window, removing it from the tab
    /// tree (the session stays alive).
    func detachFocusedSession() {
        guard let session = focusedSession else { return }
        let sessionID = session.id
        // Remove the leaf from its tab without terminating the session.
        for idx in tabs.indices where tabs[idx].root.sessionIDs.contains(sessionID) {
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
        DetachedWindowManager.shared.detach(session: session)
    }

    func splitFocused(direction: SplitDirection) {
        guard var tab = selectedTab, let focused = focusedSession else { return }
        let session = sessions.open(profile: focused.profile, origin: .user)
        tab.root = tab.root.splitting(sessionID: focused.id, with: session.id, direction: direction)
        tab.focusedSessionID = session.id
        tabs = tabs.map { $0.id == tab.id ? tab : $0 }
    }

    func focusSession(_ sessionID: String) {
        if let idx = tabs.firstIndex(where: { $0.root.sessionIDs.contains(sessionID) }) {
            tabs[idx].focusedSessionID = sessionID
        }
    }

    /// Run a snippet in the focused session (vault expansion happens as the
    /// user types, so this sends the literal command).
    func runSnippet(_ command: String) {
        focusedSession?.send(command + "\n")
    }

    func renameTab(id: UUID, to title: String) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[idx].customTitle = title.isEmpty ? nil : title
    }

    func closeOtherTabs(keeping id: UUID) {
        for tab in tabs where tab.id != id {
            closeTab(id: tab.id)
        }
        selectedTabID = id
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
