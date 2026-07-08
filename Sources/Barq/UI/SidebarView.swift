import SwiftUI
import AppKit

/// NSVisualEffectView-backed vibrancy for the sidebar.
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct SidebarView: View {
    @ObservedObject var state: AppState
    @ObservedObject var profiles: ProfileStore
    @ObservedObject var settings = SettingsStore.shared
    @State private var search = ""

    private var theme: BarqTheme { settings.theme }

    init(state: AppState) {
        self.state = state
        self.profiles = state.profiles
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search + add
            HStack(spacing: BarqDesign.s2) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                    TextField("Search hosts", text: $search)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textPrimary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: BarqDesign.rChip).fill(theme.hoverFill))

                Button {
                    state.editingProfile = nil
                    state.showingProfileEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(theme.hoverFill))
                }
                .buttonStyle(.plain)
                .help("New connection profile")
            }
            .padding(.horizontal, BarqDesign.s3)
            .padding(.top, BarqDesign.s3)
            .padding(.bottom, BarqDesign.s2)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: BarqDesign.s3) {
                    ForEach(visibleTags, id: \.self) { tag in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tag)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(theme.textTertiary)
                                .padding(.horizontal, BarqDesign.s3)
                                .padding(.bottom, 2)
                            ForEach(visibleProfiles(tag: tag)) { profile in
                                ProfileRow(profile: profile, state: state, theme: theme)
                            }
                        }
                    }
                    if visibleTags.isEmpty {
                        Text(search.isEmpty ? "No hosts yet" : "No matches")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, BarqDesign.s5)
                    }
                }
                .padding(.vertical, BarqDesign.s2)
            }
        }
        .background(theme.elevated)
    }

    private var visibleTags: [String] {
        profiles.allTags.filter { !visibleProfiles(tag: $0).isEmpty }
    }

    private func visibleProfiles(tag: String) -> [ConnectionProfile] {
        let all = profiles.profiles(tag: tag)
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.host.localizedCaseInsensitiveContains(search) ||
            $0.target.localizedCaseInsensitiveContains(search)
        }
    }
}

private struct ProfileRow: View {
    let profile: ConnectionProfile
    @ObservedObject var state: AppState
    let theme: BarqTheme
    @State private var hovering = false

    var body: some View {
        HStack(spacing: BarqDesign.s2) {
            Image(systemName: profile.kind.symbol)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name.isEmpty ? profile.target : profile.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(profile.target)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if ProxyService.canLaunchChrome(profile) {
                Button {
                    ProxyService.launchChrome(for: profile)
                } label: {
                    Image(systemName: "globe").font(.system(size: 11)).foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0.6)
                .help("Launch Chrome through this profile's SOCKS proxy")
            }

            // AI access chip — electric when granted.
            Button {
                var updated = profile
                updated.aiAllowed.toggle()
                state.profiles.upsert(updated)
            } label: {
                Text("AI")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(profile.aiAllowed ? theme.electric.opacity(0.9) : theme.hoverFill))
                    .foregroundStyle(profile.aiAllowed ? (theme.isDark ? Color.black.opacity(0.85) : .white) : theme.textTertiary)
            }
            .buttonStyle(.plain)
            .help(profile.aiAllowed ? "AI agents can use this profile — click to revoke" : "Click to grant AI agents access")
        }
        .padding(.horizontal, BarqDesign.s2)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: BarqDesign.rChip)
                .fill(hovering ? theme.hoverFill : .clear)
        )
        .padding(.horizontal, BarqDesign.s2 - 2)
        .contentShape(Rectangle())
        .onTapGesture { state.connect(profile: profile) }
        .onHover { hovering = $0 }
        .help("Connect to \(profile.name.isEmpty ? profile.target : profile.name) — right-click for more")
        .contextMenu {
            Button("Connect") { state.connect(profile: profile) }
            if profile.kind == .ssh {
                Button("Open SFTP") { state.connect(profile: profile, launch: .sftp) }
            }
            Button("Edit…") {
                state.editingProfile = profile
                state.showingProfileEditor = true
            }
            if !profile.customActions.isEmpty {
                Menu("Actions") {
                    ForEach(profile.customActions) { action in
                        Button(action.name) {
                            if let session = state.focusedSession {
                                session.send(action.command + "\n")
                            }
                        }
                    }
                }
            }
            Divider()
            Button("Delete", role: .destructive) { state.profiles.remove(id: profile.id) }
        }
    }
}
