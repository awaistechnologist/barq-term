import SwiftUI

struct PaletteAction: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let symbol: String
    let perform: () -> Void
}

/// ⇧⌘P command palette: fuzzy access to every app action and profile.
struct CommandPaletteView: View {
    @ObservedObject var state: AppState
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "command")
                    .foregroundStyle(.secondary)
                TextField("Type a command or host name…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($fieldFocused)
                    .onSubmit(runHighlighted)
            }
            .padding(12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, action in
                            HStack(spacing: 10) {
                                Image(systemName: action.symbol)
                                    .frame(width: 18)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(action.title)
                                        .font(.system(size: 13))
                                    if let subtitle = action.subtitle {
                                        Text(subtitle)
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(index == highlighted ? Color.accentColor.opacity(0.18) : .clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                action.perform()
                                state.paletteVisible = false
                            }
                            .id(index)
                        }
                    }
                }
                .frame(maxHeight: 320)
                .onChange(of: highlighted) { value in
                    proxy.scrollTo(value)
                }
            }
        }
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.1)))
        .shadow(radius: 24, y: 8)
        .onAppear { fieldFocused = true }
        .onExitCommand { state.paletteVisible = false }
        .onChange(of: query) { _ in highlighted = 0 }
        .onMoveCommand { direction in
            switch direction {
            case .down: highlighted = min(highlighted + 1, max(filtered.count - 1, 0))
            case .up: highlighted = max(highlighted - 1, 0)
            default: break
            }
        }
    }

    private func runHighlighted() {
        guard filtered.indices.contains(highlighted) else { return }
        filtered[highlighted].perform()
        state.paletteVisible = false
    }

    private var allActions: [PaletteAction] {
        var actions: [PaletteAction] = [
            PaletteAction(title: "New Local Tab", subtitle: "⌘T", symbol: "plus.rectangle") { state.newLocalTab() },
            PaletteAction(title: "Split Right", subtitle: "⌘D", symbol: "rectangle.split.2x1") { state.splitFocused(direction: .horizontal) },
            PaletteAction(title: "Split Down", subtitle: "⇧⌘D", symbol: "rectangle.split.1x2") { state.splitFocused(direction: .vertical) },
            PaletteAction(title: "AI Command…", subtitle: "⌘K — natural language to command", symbol: "sparkles") { state.composerVisible = true },
            PaletteAction(title: "Toggle AI Panel", subtitle: "⇧⌘A", symbol: "sidebar.right") { state.aiPanelVisible.toggle() },
            PaletteAction(title: "Toggle Sidebar", subtitle: "⌘B", symbol: "sidebar.left") { state.sidebarVisible.toggle() },
            PaletteAction(title: "New Connection Profile…", subtitle: nil, symbol: "plus.circle") {
                state.editingProfile = nil
                state.showingProfileEditor = true
            }
        ]
        for theme in Themes.all {
            actions.append(PaletteAction(title: "Theme: \(theme.name)", subtitle: nil, symbol: "paintpalette") {
                state.settings.themeID = theme.id
            })
        }
        for profile in state.profiles.profiles {
            actions.append(PaletteAction(
                title: "Connect: \(profile.name.isEmpty ? profile.target : profile.name)",
                subtitle: profile.target,
                symbol: profile.kind.symbol
            ) { state.connect(profile: profile) })
        }
        return actions
    }

    private var filtered: [PaletteAction] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return allActions }
        return allActions.filter { fuzzyMatch(needle: trimmed.lowercased(), haystack: ($0.title + " " + ($0.subtitle ?? "")).lowercased()) }
    }

    /// Simple subsequence fuzzy match.
    private func fuzzyMatch(needle: String, haystack: String) -> Bool {
        var iterator = haystack.makeIterator()
        for char in needle {
            var found = false
            while let candidate = iterator.next() {
                if candidate == char { found = true; break }
            }
            if !found { return false }
        }
        return true
    }
}
