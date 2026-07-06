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
    @State private var search = ""

    init(state: AppState) {
        self.state = state
        self.profiles = state.profiles
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.yellow)
                Text("Barq")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button {
                    state.editingProfile = nil
                    state.showingProfileEditor = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .help("New connection profile")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Search hosts…", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            List {
                ForEach(visibleTags, id: \.self) { tag in
                    Section {
                        ForEach(visibleProfiles(tag: tag)) { profile in
                            ProfileRow(profile: profile, state: state)
                        }
                    } header: {
                        Text(tag)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(VisualEffect())
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
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: profile.kind.symbol)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name.isEmpty ? profile.target : profile.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Text(profile.target)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // AI access chip — one click grants/revokes agent access.
            Button {
                var updated = profile
                updated.aiAllowed.toggle()
                state.profiles.upsert(updated)
            } label: {
                Text("AI")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(profile.aiAllowed ? Color.green.opacity(0.25) : Color.primary.opacity(0.08)))
                    .foregroundStyle(profile.aiAllowed ? .green : .secondary)
            }
            .buttonStyle(.borderless)
            .help(profile.aiAllowed ? "AI agents can use this profile — click to revoke" : "Click to grant AI agents access to this profile")
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { state.connect(profile: profile) }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Connect") { state.connect(profile: profile) }
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
            Button("Delete", role: .destructive) {
                state.profiles.remove(id: profile.id)
            }
        }
    }
}
