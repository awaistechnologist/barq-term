import SwiftUI

/// Barq's landing surface — you open the app to this, not a blank prompt.
/// A greeting, one omni-bar that takes intent (connect / run / ask / search),
/// your machines as cards, and recents.
struct HomeView: View {
    @ObservedObject var state: AppState
    @ObservedObject var settings = SettingsStore.shared
    @ObservedObject var profiles: ProfileStore

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var omniFocused: Bool

    private var theme: BarqTheme { settings.theme }

    init(state: AppState) {
        self.state = state
        self.profiles = state.profiles
    }

    private var suggestions: [OmniSuggestion] {
        OmniIntent.suggestions(query: query, profiles: profiles.profiles)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: BarqDesign.s5) {
                Spacer().frame(height: 40)
                greeting
                omniBar
                machines
                recents
                Spacer(minLength: 24)
                Text("Barq \(appVersion)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
                Spacer(minLength: 16)
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, BarqDesign.s5)
        }
        .background(theme.chrome)
        .onAppear { omniFocused = true }
    }

    // MARK: Greeting

    private var greeting: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                BarqLogo(theme: theme, badge: 34, showWordmark: false)
                Text(timeGreeting)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
            }
            Text("What do you want to do? Type a command, a host, or just ask.")
                .font(.system(size: 13.5))
                .foregroundStyle(theme.textSecondary)
        }
    }

    private var timeGreeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "Good morning."
        case 12..<17: return "Good afternoon."
        case 17..<22: return "Good evening."
        default: return "Working late."
        }
    }

    // MARK: Omni-bar

    private var omniBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.electric)
                TextField("Ask, run a command, or connect to a host…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .foregroundStyle(theme.textPrimary)
                    .focused($omniFocused)
                    .onSubmit(runHighlighted)
                    .onChange(of: query) { _ in highlighted = 0 }
                    .onMoveCommand { dir in
                        let n = suggestions.count
                        guard n > 0 else { return }
                        if dir == .down { highlighted = min(highlighted + 1, n - 1) }
                        if dir == .up { highlighted = max(highlighted - 1, 0) }
                    }
                if !query.isEmpty {
                    Text("⏎").font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(theme.elevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(omniFocused ? theme.electric.opacity(0.6) : theme.hairline,
                                          lineWidth: omniFocused ? 1.5 : 1)
                    )
            )
            .shadow(color: omniFocused ? theme.electric.opacity(0.14) : .clear, radius: 10)

            if !suggestions.isEmpty {
                VStack(spacing: 2) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, s in
                        suggestionRow(s, selected: index == highlighted)
                            .onTapGesture { state.perform(s.kind); query = "" }
                    }
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.elevated))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.hairline))
                .padding(.top, 8)
            }
        }
    }

    private func suggestionRow(_ s: OmniSuggestion, selected: Bool) -> some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(iconTint(s.kind).opacity(0.16)).frame(width: 28, height: 28)
                Image(systemName: iconName(s.kind)).font(.system(size: 12, weight: .semibold)).foregroundStyle(iconTint(s.kind))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(s.title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(theme.textPrimary)
                Text(s.subtitle).font(.system(size: 11.5)).foregroundStyle(theme.textTertiary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? theme.electric.opacity(0.16) : .clear))
        .contentShape(Rectangle())
    }

    private func iconName(_ k: OmniKind) -> String {
        switch k {
        case .connect: return "bolt.horizontal.fill"
        case .runLocal: return "chevron.right"
        case .askAI: return "sparkles"
        case .search: return "magnifyingglass"
        }
    }
    private func iconTint(_ k: OmniKind) -> Color {
        switch k {
        case .connect: return theme.electric
        case .runLocal: return Color(BarqTheme.hexToNSColor(theme.ansi[4]))
        case .askAI: return .purple
        case .search: return theme.textSecondary
        }
    }

    private func runHighlighted() {
        guard suggestions.indices.contains(highlighted) else { return }
        state.perform(suggestions[highlighted].kind)
        query = ""
    }

    // MARK: Machines

    private var machines: some View {
        VStack(alignment: .leading, spacing: BarqDesign.s3) {
            Text("YOUR MACHINES")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.textTertiary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: BarqDesign.s3)], spacing: BarqDesign.s3) {
                ForEach(profiles.profiles) { profile in
                    MachineCard(profile: profile, theme: theme) { state.connect(profile: profile) }
                }
                AddMachineCard(theme: theme) {
                    state.editingProfile = nil
                    state.showingProfileEditor = true
                }
            }
        }
    }

    // MARK: Recents

    @ViewBuilder
    private var recents: some View {
        let recent = state.recentProfiles
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: BarqDesign.s3) {
                Text("JUMP BACK IN")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
                FlowRow(spacing: BarqDesign.s2) {
                    ForEach(recent) { profile in
                        Button { state.connect(profile: profile) } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "clock.arrow.circlepath").font(.system(size: 11)).foregroundStyle(theme.textTertiary)
                                Text(profile.name.isEmpty ? profile.target : profile.name)
                                    .font(.system(size: 12)).foregroundStyle(theme.textSecondary)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 9).fill(theme.elevated))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.hairline))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct MachineCard: View {
    let profile: ConnectionProfile
    let theme: BarqTheme
    let connect: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: connect) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: profile.kind.symbol)
                        .font(.system(size: 13)).foregroundStyle(theme.textSecondary)
                    Spacer()
                    if profile.aiAllowed {
                        Text("AI").font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(theme.electric.opacity(0.9)))
                            .foregroundStyle(theme.isDark ? .black : .white)
                    }
                }
                .padding(.bottom, 10)
                Text(profile.name.isEmpty ? profile.target : profile.name)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.textPrimary).lineLimit(1)
                Text(profile.target)
                    .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(theme.textTertiary).lineLimit(1)
                if !profile.tags.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(profile.tags.prefix(2), id: \.self) { tag in
                            Text(tag).font(.system(size: 9.5, weight: .bold)).foregroundStyle(theme.textSecondary)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 5).fill(theme.hoverFill))
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(hover ? theme.elevatedStrong : theme.elevated))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(hover ? theme.electric.opacity(0.4) : theme.hairline))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct AddMachineCard: View {
    let theme: BarqTheme
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 18, weight: .medium))
                Text("Add host").font(.system(size: 12))
            }
            .foregroundStyle(theme.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(RoundedRectangle(cornerRadius: 12).fill(hover ? theme.hoverFill : .clear))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Simple wrapping row for recents chips.
struct FlowRow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}
