import SwiftUI
import AppKit

/// Slim banner shown when a newer Barq release is available on GitHub.
private struct UpdateBanner: View {
    let update: UpdateChecker.Release
    let theme: BarqTheme
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: BarqDesign.s2) {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(theme.electric)
            Text("Barq \(update.version) is available")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Button("Download") {
                if let url = URL(string: update.url) { NSWorkspace.shared.open(url) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, BarqDesign.s3)
        .padding(.vertical, 7)
        .background(theme.electric.opacity(0.12))
        .overlay(alignment: .bottom) { theme.hairline.frame(height: 1) }
    }
}

struct ContentView: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject var settings = SettingsStore.shared
    @State private var tearOffTargeted = false
    private var theme: BarqTheme { settings.theme }

    var body: some View {
        ZStack {
            // The chrome/gutter tone sits behind everything; terminal panes are
            // darker cards that float on top of it.
            theme.elevated.ignoresSafeArea()

            VStack(spacing: 0) {
                TabBarView(state: state)
                if let update = state.availableUpdate {
                    UpdateBanner(update: update, theme: theme) { state.availableUpdate = nil }
                }
                HStack(spacing: 0) {
                    if state.sidebarVisible {
                        SidebarView(state: state)
                            .frame(width: 250)
                            .overlay(alignment: .trailing) { theme.hairline.frame(width: 1) }
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    terminalArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // Chrome-style tear-off: drag a tab into the body to pop
                        // it out into its own window.
                        .dropDestination(for: TabTransfer.self) { payload, _ in
                            guard let id = payload.first?.id else { return false }
                            state.detach(tabID: id)
                            return true
                        } isTargeted: { tearOffTargeted = $0 }
                        .overlay {
                            if tearOffTargeted {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(theme.electric.opacity(0.10))
                                        .overlay(RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(theme.electric.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [7, 5])))
                                    Label("Release to open in a new window", systemImage: "rectangle.badge.plus")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(theme.electric)
                                        .padding(.horizontal, 14).padding(.vertical, 9)
                                        .background(.ultraThinMaterial, in: Capsule())
                                }
                                .padding(BarqDesign.s2)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                            }
                        }
                    if state.aiPanelVisible {
                        AIPanelView(state: state)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
            // Extend the top bar up under the (hidden) titlebar so the traffic
            // lights sit inline with it — no empty band above the top bar.
            .ignoresSafeArea(.container, edges: .top)

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

