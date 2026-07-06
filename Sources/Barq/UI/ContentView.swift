import SwiftUI

struct ContentView: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject var settings = SettingsStore.shared

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if state.sidebarVisible {
                    SidebarView(state: state)
                        .frame(width: 240)
                    Divider()
                }

                VStack(spacing: 0) {
                    TabBarView(state: state)
                    Divider()
                    terminalArea
                }
                .background(Color(nsColor: settings.theme.backgroundColor))

                if state.aiPanelVisible {
                    Divider()
                    AIPanelView(state: state)
                }
            }

            // Overlays
            if state.paletteVisible || state.composerVisible {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture {
                        state.paletteVisible = false
                        state.composerVisible = false
                    }
                VStack {
                    Spacer().frame(height: 90)
                    if state.paletteVisible {
                        CommandPaletteView(state: state)
                    } else if state.composerVisible {
                        CommandComposerView(state: state)
                    }
                    Spacer()
                }
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .sheet(isPresented: $state.showingProfileEditor) {
            ProfileEditorView(state: state, profile: state.editingProfile)
        }
        .onAppear {
            if state.tabs.isEmpty {
                state.newLocalTab()
            }
        }
    }

    @ViewBuilder
    private var terminalArea: some View {
        if let tab = state.selectedTab {
            SplitNodeView(node: tab.root, focusedSessionID: tab.focusedSessionID, theme: settings.theme)
                .id(tab.id)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.yellow.opacity(0.6))
                Text("Barq")
                    .font(.system(size: 22, weight: .bold))
                Text("⌘T for a local shell — or double-click a host in the sidebar")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button("New Terminal (⌘T)") { state.newLocalTab() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
