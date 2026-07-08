import SwiftUI

@main
struct BarqApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var state = AppState.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { state.newLocalTab() }
                    .keyboardShortcut("t", modifiers: .command)
                Button("Close Tab") {
                    if let id = state.selectedTabID { state.closeTab(id: id) }
                }
                .keyboardShortcut("w", modifiers: .command)
                Divider()
                Button("Import Profiles…") { importProfiles() }
                Button("Export Profiles…") { exportProfiles() }
                Button("Import from ~/.ssh/config…") { importSSHConfig() }
                Button("Export to ssh config…") { exportSSHConfig() }
            }
            CommandGroup(after: .textEditing) {
                Button("Find…") {
                    state.focusedSession?.showFindBar()
                }
                .keyboardShortcut("f", modifiers: .command)
            }
            CommandMenu("Shell") {
                Button("Split Right") { state.splitFocused(direction: .horizontal) }
                    .keyboardShortcut("d", modifiers: .command)
                Button("Split Down") { state.splitFocused(direction: .vertical) }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Move Pane to New Window") { state.detachFocusedSession() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Toggle("Broadcast Input to All Panes", isOn: $state.broadcastInput)
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Divider()
                Button("Quick Connect…") { quickConnect() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Button("New Connection Profile…") {
                    state.editingProfile = nil
                    state.showingProfileEditor = true
                }
                Divider()
                Button("Bigger Text") { state.adjustFontSize(by: 1) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Smaller Text") { state.adjustFontSize(by: -1) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { state.resetFontSize() }
                    .keyboardShortcut("0", modifiers: .command)
            }
            CommandMenu("AI") {
                Button("AI Command…") { state.composerVisible = true }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Explain Last Output") {
                    state.aiPanelVisible = true
                    NotificationCenter.default.post(name: .barqExplainRequested, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
                Button("Toggle AI Panel") { state.aiPanelVisible.toggle() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                Button(state.sidebarVisible ? "Hide Hosts Sidebar" : "Show Hosts Sidebar") {
                    state.sidebarVisible.toggle()
                }
                .keyboardShortcut("b", modifiers: .command)
                Button("Command Palette…") { state.paletteVisible = true }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Search All Sessions…") { state.globalSearchVisible = true }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }
            CommandMenu("Tools") {
                Button("Context Vault") {
                    openWindow(id: "vault")
                }
                Button("Snippets") {
                    openWindow(id: "snippets")
                }
            }
        }

        Window("Context Vault", id: "vault") {
            VaultView(vault: state.vault)
        }

        Window("Snippets", id: "snippets") {
            SnippetsView(state: state)
        }

        Settings {
            SettingsView()
        }
    }
}

@MainActor
private func quickConnect() {
    let alert = NSAlert()
    alert.messageText = "Quick Connect"
    alert.informativeText = "Enter an SSH target, e.g. user@host or user@host:2222"
    alert.addButton(withTitle: "Connect")
    alert.addButton(withTitle: "Cancel")
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
    field.placeholderString = "user@host:port"
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    if alert.runModal() == .alertFirstButtonReturn {
        AppState.shared.quickConnect(field.stringValue)
    }
}

@MainActor
private func exportProfiles() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "barq-profiles.json"
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    if let data = try? AppState.shared.profiles.exportJSON() {
        try? data.write(to: url, options: .atomic)
    }
}

@MainActor
private func importProfiles() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url,
          let data = try? Data(contentsOf: url) else { return }
    try? AppState.shared.profiles.importJSON(data, merge: true)
}

@MainActor
private func importSSHConfig() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseFiles = true
    panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
    panel.showsHiddenFiles = true
    guard panel.runModal() == .OK, let url = panel.url,
          let text = try? String(contentsOf: url, encoding: .utf8) else { return }
    for profile in SSHConfigCodec.parse(text) {
        if AppState.shared.profiles.profile(named: profile.name) == nil {
            AppState.shared.profiles.upsert(profile)
        }
    }
}

@MainActor
private func exportSSHConfig() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "config"
    panel.showsHiddenFiles = true
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let text = SSHConfigCodec.generate(AppState.shared.profiles.profiles)
    try? text.write(to: url, atomically: true, encoding: .utf8)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            AppState.shared.startServices()
        }
    }

    /// Finder "Open with Barq" on a folder → local tab there.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            for url in urls {
                if url.isFileURL {
                    AppState.shared.openLocalTab(in: url.path)
                } else if url.scheme == "barq" {
                    AppState.shared.handleURL(url)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Capture final working directories before exit.
        SessionRestore.save(SessionRestore.snapshot(from: AppState.shared.tabs, groups: AppState.shared.groups, sessions: AppState.shared.sessions))
    }
}

extension Notification.Name {
    static let barqExplainRequested = Notification.Name("BarqExplainRequested")
}
