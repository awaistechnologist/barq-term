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

    /// Swap one leaf's session id for another (used by reconnect-in-place).
    func replacingLeaf(_ oldID: String, with newID: String) -> SplitNode {
        switch self {
        case .leaf(let id): return id == oldID ? .leaf(newID) : self
        case .split(let dir, let a, let b):
            return .split(dir, a.replacingLeaf(oldID, with: newID), b.replacingLeaf(oldID, with: newID))
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
    /// The tab group this tab belongs to, if any.
    var groupID: UUID?
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
    @Published var groups: [TabGroup] = []
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
    /// A question routed from the omni-bar for the AI panel to answer.
    @Published var pendingAIQuestion: String?
    /// Recently connected profile IDs (most recent first), persisted.
    @Published var recentProfileIDs: [UUID] = AppState.loadRecents()
    /// A newer release available on GitHub, if any.
    @Published var availableUpdate: UpdateChecker.Release?

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

        NotificationCenter.default.publisher(for: .barqTerminalAction)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self,
                      let sessionID = note.object as? String,
                      let action = note.userInfo?["action"] as? String else { return }
                self.handleTerminalAction(action, sessionID: sessionID)
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
            SessionRestore.save(SessionRestore.snapshot(from: self.tabs, groups: self.groups, sessions: self.sessions))
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
            var tab = TerminalTab(root: .leaf(session.id), focusedSessionID: session.id, customTitle: entry.customTitle)
            // Rebuild groups by name so grouping survives a relaunch.
            if let groupName = entry.groupName {
                let gid = groupID(forName: groupName, createIfMissing: true)
                if let gid, let color = entry.groupColorHex {
                    setGroupColor(id: gid, hex: color)
                }
                tab.groupID = gid
            }
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
        Task { self.availableUpdate = await UpdateChecker.availableUpdate() }
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
        noteRecent(profile.id)
    }

    // MARK: Home & omni-bar journey

    /// Return to the Home launch surface (tabs stay open).
    func goHome() { selectedTabID = nil }

    /// Handle a right-click quick action from a terminal.
    private func handleTerminalAction(_ action: String, sessionID: String) {
        guard let session = sessions.session(id: sessionID) else { return }
        let cwd = session.currentDirectory
        switch action {
        case "newTabHere":
            openLocalTab(in: cwd ?? FileManager.default.homeDirectoryForCurrentUser.path)
        case "copyCwd":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(cwd ?? "~", forType: .string)
        case "saveDirAsProfile":
            var profile = ConnectionProfile()
            profile.kind = .local
            profile.workingDirectory = cwd ?? ""
            profile.name = cwd.map { ($0 as NSString).lastPathComponent } ?? "New Host"
            editingProfile = profile           // open the editor prefilled
            showingProfileEditor = true
        default:
            break
        }
    }

    /// Run the result the omni-bar produced.
    func perform(_ kind: OmniKind) {
        switch kind {
        case .connect(let id):
            if let profile = profiles.profile(id: id) { connect(profile: profile) }
        case .runLocal(let command):
            runInNewLocalTab(command)
        case .askAI(let question):
            askAI(question)
        case .search(let query):
            searchPrefill = query
            globalSearchVisible = true
        }
    }

    /// Prefill for the global-search overlay when opened from the omni-bar.
    @Published var searchPrefill: String = ""

    func runInNewLocalTab(_ command: String) {
        newLocalTab()
        let sessionID = selectedTab?.focusedSessionID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.sessions.session(id: sessionID ?? "")?.send(command + "\n")
        }
    }

    func askAI(_ question: String) {
        if selectedTab == nil { newLocalTab() }
        pendingAIQuestion = question
        aiPanelVisible = true
    }

    // MARK: Recents

    private static let recentsKey = "recentProfileIDs"

    private static func loadRecents() -> [UUID] {
        (UserDefaults.standard.stringArray(forKey: recentsKey) ?? []).compactMap(UUID.init)
    }

    private func noteRecent(_ id: UUID) {
        var ids = recentProfileIDs.filter { $0 != id }
        ids.insert(id, at: 0)
        recentProfileIDs = Array(ids.prefix(8))
        UserDefaults.standard.set(recentProfileIDs.map(\.uuidString), forKey: Self.recentsKey)
    }

    var recentProfiles: [ConnectionProfile] {
        recentProfileIDs.compactMap { profiles.profile(id: $0) }
    }

    /// Connect to an ad-hoc `user@host:port` without saving a profile.
    func quickConnect(_ spec: String) {
        guard let profile = QuickConnect.profile(from: spec) else { return }
        connect(profile: profile)
    }

    /// Adjust the terminal font size (⌘+ / ⌘−), clamped; live-restyles.
    func adjustFontSize(by delta: Double) {
        settings.fontSize = min(32, max(8, settings.fontSize + delta))
    }

    func resetFontSize() {
        settings.fontSize = 13
    }

    private func attachTab(for session: TerminalSession) {
        var tab = TerminalTab(root: .leaf(session.id), focusedSessionID: session.id)
        tab.groupID = autoGroupID(for: session.profile)
        tabs.append(tab)
        selectedTabID = tab.id
        persistSessions()
        focusActiveTerminal()
    }

    // MARK: Tab groups

    /// Ordered layout of the tab bar: group segments and lone tabs.
    var tabLayout: [TabLayoutItem] {
        TabLayout.items(tabs: tabs, groups: groups)
    }

    func group(id: UUID?) -> TabGroup? {
        guard let id else { return nil }
        return groups.first { $0.id == id }
    }

    /// Find (or create) the group a freshly-opened profile belongs to, based on
    /// its first connection tag. Untagged profiles are ungrouped.
    private func autoGroupID(for profile: ConnectionProfile) -> UUID? {
        guard let tag = profile.tags.first, !tag.isEmpty else { return nil }
        return groupID(forName: tag, createIfMissing: true)
    }

    /// Look up a group by name (case-insensitive), optionally creating it with a
    /// deterministic tag color.
    @discardableResult
    func groupID(forName name: String, createIfMissing: Bool) -> UUID? {
        if let existing = groups.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing.id
        }
        guard createIfMissing else { return nil }
        let group = TabGroup(name: name, colorHex: TabGroupPalette.color(for: name))
        groups.append(group)
        return group.id
    }

    func toggleCollapse(groupID: UUID) {
        guard let idx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[idx].collapsed.toggle()
    }

    func renameGroup(id: UUID, to name: String) {
        guard let idx = groups.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        groups[idx].name = name
    }

    func setGroupColor(id: UUID, hex: String) {
        guard let idx = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[idx].colorHex = hex
    }

    /// Put a tab into a group (creating a new group if `groupID` is nil).
    func assign(tabID: UUID, toGroup groupID: UUID?) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[idx].groupID = groupID
        pruneEmptyGroups()
        persistSessions()
    }

    /// Create a new group seeded from a tab and move that tab into it.
    @discardableResult
    func createGroup(fromTab tabID: UUID, name: String? = nil) -> UUID? {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return nil }
        let groupName = name ?? title(for: tabs[idx])
        let group = TabGroup(name: groupName, colorHex: TabGroupPalette.color(for: groupName))
        groups.append(group)
        tabs[idx].groupID = group.id
        pruneEmptyGroups()
        persistSessions()
        return group.id
    }

    func removeFromGroup(tabID: UUID) {
        assign(tabID: tabID, toGroup: nil)
    }

    /// Disband a group; its tabs become ungrouped.
    func ungroup(id: UUID) {
        for i in tabs.indices where tabs[i].groupID == id {
            tabs[i].groupID = nil
        }
        groups.removeAll { $0.id == id }
        persistSessions()
    }

    /// Reorder: move `tabID` to sit immediately before `targetID` (or to the end
    /// when `targetID` is nil), adopting the target's group.
    func moveTab(_ tabID: UUID, before targetID: UUID?) {
        guard let from = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        var tab = tabs.remove(at: from)
        if let targetID, let target = tabs.first(where: { $0.id == targetID }) {
            tab.groupID = target.groupID
            let insertAt = tabs.firstIndex(where: { $0.id == targetID }) ?? tabs.endIndex
            tabs.insert(tab, at: insertAt)
        } else {
            tabs.append(tab)
        }
        pruneEmptyGroups()
        persistSessions()
    }

    /// Drop a tab onto a group header: join that group, ordered next to members.
    func moveTab(_ tabID: UUID, intoGroup groupID: UUID) {
        guard let from = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        var tab = tabs.remove(at: from)
        tab.groupID = groupID
        // Insert after the last existing member so it clusters with the group.
        if let lastMember = tabs.lastIndex(where: { $0.groupID == groupID }) {
            tabs.insert(tab, at: lastMember + 1)
        } else {
            tabs.append(tab)
        }
        pruneEmptyGroups()
        persistSessions()
    }

    private func pruneEmptyGroups() {
        let used = Set(tabs.compactMap(\.groupID))
        groups.removeAll { !used.contains($0.id) }
    }

    func closeTab(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        for sessionID in tab.root.sessionIDs {
            sessions.close(id: sessionID)
        }
        tabs.removeAll { $0.id == id }
        pruneEmptyGroups()
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
                    pruneEmptyGroups()
                    if selectedTabID == tabID { selectedTabID = tabs.last?.id }
                }
                break
            }
        }
    }

    /// Move a session into its own window, removing it from the tab tree
    /// (the session stays alive).
    func detachSession(_ sessionID: String) {
        guard let session = sessions.session(id: sessionID) else { return }
        for idx in tabs.indices where tabs[idx].root.sessionIDs.contains(sessionID) {
            if let newRoot = tabs[idx].root.removing(sessionID: sessionID) {
                tabs[idx].root = newRoot
                if tabs[idx].focusedSessionID == sessionID {
                    tabs[idx].focusedSessionID = newRoot.sessionIDs[0]
                }
            } else {
                let tabID = tabs[idx].id
                tabs.remove(at: idx)
                pruneEmptyGroups()
                if selectedTabID == tabID { selectedTabID = tabs.last?.id }
            }
            break
        }
        DetachedWindowManager.shared.detach(session: session)
    }

    func detachFocusedSession() {
        if let session = focusedSession { detachSession(session.id) }
    }

    /// Reconnect a dead session in place, keeping its tab/pane position.
    func reconnect(_ sessionID: String) {
        guard let old = sessions.session(id: sessionID),
              let idx = tabs.firstIndex(where: { $0.root.sessionIDs.contains(sessionID) }) else { return }
        let profile = old.profile
        let fresh = sessions.open(profile: profile, origin: .user)
        tabs[idx].root = tabs[idx].root.replacingLeaf(sessionID, with: fresh.id)
        if tabs[idx].focusedSessionID == sessionID { tabs[idx].focusedSessionID = fresh.id }
        sessions.close(id: sessionID)
        focusActiveTerminal()
    }

    /// Tear a whole tab out into its own window (uses its focused pane).
    func detach(tabID: UUID) {
        if let tab = tabs.first(where: { $0.id == tabID }) {
            detachSession(tab.focusedSessionID)
        }
    }

    func splitFocused(direction: SplitDirection) {
        guard var tab = selectedTab, let focused = focusedSession else { return }
        let session = sessions.open(profile: focused.profile, origin: .user)
        tab.root = tab.root.splitting(sessionID: focused.id, with: session.id, direction: direction)
        tab.focusedSessionID = session.id
        tabs = tabs.map { $0.id == tab.id ? tab : $0 }
        focusActiveTerminal()
    }

    func focusSession(_ sessionID: String) {
        if let idx = tabs.firstIndex(where: { $0.root.sessionIDs.contains(sessionID) }) {
            tabs[idx].focusedSessionID = sessionID
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .barqFocusTerminal, object: sessionID)
        }
    }

    /// The session that should hold keyboard focus: the focused pane of the
    /// selected tab. Pure so it can be unit-tested without the singleton.
    nonisolated static func activeSessionID(tabs: [TerminalTab], selectedTabID: UUID?) -> String? {
        tabs.first { $0.id == selectedTabID }?.focusedSessionID
    }

    /// Give keyboard focus to the active pane of the selected tab. Called on tab
    /// switch, new session, split, and when an overlay/panel is dismissed — so
    /// typing lands in the terminal, not the sidebar search field.
    func focusActiveTerminal() {
        guard let sid = Self.activeSessionID(tabs: tabs, selectedTabID: selectedTabID) else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .barqFocusTerminal, object: sid)
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
    /// Request that a specific session's terminal become the window's first
    /// responder (object == sessionID string).
    static let barqFocusTerminal = Notification.Name("BarqFocusTerminal")
    /// A right-click quick action from a terminal (object == sessionID,
    /// userInfo["action"] == action key).
    static let barqTerminalAction = Notification.Name("BarqTerminalAction")
}
