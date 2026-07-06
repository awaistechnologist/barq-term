import SwiftUI

@main
struct BarqApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var state = AppState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { state.newLocalTab() }
                    .keyboardShortcut("t", modifiers: .command)
                Button("Close Tab") {
                    if let id = state.selectedTabID { state.closeTab(id: id) }
                }
                .keyboardShortcut("w", modifiers: .command)
            }
            CommandMenu("Shell") {
                Button("Split Right") { state.splitFocused(direction: .horizontal) }
                    .keyboardShortcut("d", modifiers: .command)
                Button("Split Down") { state.splitFocused(direction: .vertical) }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Divider()
                Button("New Connection Profile…") {
                    state.editingProfile = nil
                    state.showingProfileEditor = true
                }
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
            }
        }

        Window("Context Vault", id: "vault") {
            VaultView(vault: state.vault)
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            AppState.shared.startServices()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

extension Notification.Name {
    static let barqExplainRequested = Notification.Name("BarqExplainRequested")
}
