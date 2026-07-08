import SwiftUI

struct ContentView: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject var settings = SettingsStore.shared
    private var theme: BarqTheme { settings.theme }

    var body: some View {
        ZStack {
            theme.chrome.ignoresSafeArea()

            VStack(spacing: 0) {
                TabBarView(state: state)
                HStack(spacing: 0) {
                    if state.sidebarVisible {
                        SidebarView(state: state)
                            .frame(width: 250)
                            .overlay(alignment: .trailing) { theme.hairline.frame(width: 1) }
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    terminalArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if state.aiPanelVisible {
                        AIPanelView(state: state)
                            .overlay(alignment: .leading) { theme.hairline.frame(width: 1) }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }

            overlayLayer
            WindowConfigurator().frame(width: 0, height: 0)
        }
        .frame(minWidth: 900, minHeight: 560)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: state.sidebarVisible)
        .sheet(isPresented: $state.showingProfileEditor) {
            ProfileEditorView(state: state, profile: state.editingProfile)
        }
        .onAppear {
            if state.tabs.isEmpty {
                if !state.restoreSessions() { state.newLocalTab() }
            }
            state.focusActiveTerminal()
        }
        .onChange(of: state.selectedTabID) { _ in state.focusActiveTerminal() }
        .onChange(of: state.paletteVisible) { v in if !v { state.focusActiveTerminal() } }
        .onChange(of: state.composerVisible) { v in if !v { state.focusActiveTerminal() } }
        .onChange(of: state.globalSearchVisible) { v in if !v { state.focusActiveTerminal() } }
        .onChange(of: state.aiPanelVisible) { v in if !v { state.focusActiveTerminal() } }
    }

    // MARK: Overlays (command palette / composer / global search)

    @ViewBuilder
    private var overlayLayer: some View {
        let showing = state.paletteVisible || state.composerVisible || state.globalSearchVisible
        if showing {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.9)
                .ignoresSafeArea()
                .onTapGesture {
                    state.paletteVisible = false
                    state.composerVisible = false
                    state.globalSearchVisible = false
                }
                .transition(.opacity)
            VStack {
                Spacer().frame(height: 96)
                Group {
                    if state.paletteVisible {
                        CommandPaletteView(state: state)
                    } else if state.composerVisible {
                        CommandComposerView(state: state)
                    } else if state.globalSearchVisible {
                        GlobalSearchView(state: state)
                    }
                }
                .transition(.scale(scale: 0.97).combined(with: .opacity))
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var terminalArea: some View {
        if let tab = state.selectedTab {
            SplitNodeView(node: tab.root, focusedSessionID: tab.focusedSessionID, theme: theme)
                .id(tab.id)
        } else {
            WelcomeView(state: state, theme: theme)
        }
    }
}

/// Polished empty/welcome state.
private struct WelcomeView: View {
    @ObservedObject var state: AppState
    let theme: BarqTheme

    var body: some View {
        VStack(spacing: BarqDesign.s4) {
            ZStack {
                Circle()
                    .fill(theme.electric.opacity(0.14))
                    .frame(width: 84, height: 84)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(theme.electric)
            }
            VStack(spacing: 6) {
                Text("Barq")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                Text("Lightning for your machines")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textSecondary)
            }
            Button {
                state.newLocalTab()
            } label: {
                Label("New Terminal", systemImage: "plus")
            }
            .buttonStyle(AccentButtonStyle(theme: theme))

            HStack(spacing: BarqDesign.s3) {
                hint("⌘T", "New tab")
                hint("⇧⌘K", "Quick connect")
                hint("⌘K", "Ask AI")
                hint("⇧⌘P", "Palette")
            }
            .padding(.top, BarqDesign.s2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.chrome)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Keycap(text: key, theme: theme)
            Text(label).font(.system(size: 11)).foregroundStyle(theme.textTertiary)
        }
    }
}
