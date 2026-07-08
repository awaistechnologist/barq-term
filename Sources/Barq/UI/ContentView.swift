import SwiftUI

struct ContentView: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject var settings = SettingsStore.shared
    private var theme: BarqTheme { settings.theme }

    var body: some View {
        ZStack {
            // The chrome/gutter tone sits behind everything; terminal panes are
            // darker cards that float on top of it.
            theme.elevated.ignoresSafeArea()

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
            // Land on Home. Returning users get their restored sessions; new
            // users see the Home launch surface (no auto blank shell).
            if state.tabs.isEmpty {
                _ = state.restoreSessions()
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
            HomeView(state: state)
        }
    }
}

