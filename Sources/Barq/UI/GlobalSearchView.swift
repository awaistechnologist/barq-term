import SwiftUI

/// ⇧⌘F: search across every open session's scrollback and jump to a result.
struct GlobalSearchView: View {
    @ObservedObject var state: AppState
    @State private var query = ""
    @State private var hits: [GlobalSearchHit] = []
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search all sessions…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($fieldFocused)
                    .onChange(of: query) { _ in runSearch() }
                if !hits.isEmpty {
                    Text("\(hits.count)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)

            if !hits.isEmpty {
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(hits) { hit in
                            Button {
                                jump(to: hit)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "terminal")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                        Text(hit.sessionTitle)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                        Text("line \(hit.lineNumber)")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.tertiary)
                                    }
                                    Text(hit.line)
                                        .font(.system(size: 12, design: .monospaced))
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 340)
            }
        }
        .frame(width: 600)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.1)))
        .shadow(radius: 24, y: 8)
        .onAppear {
            if !state.searchPrefill.isEmpty {
                query = state.searchPrefill
                state.searchPrefill = ""
                runSearch()
            }
            fieldFocused = true
        }
        .onExitCommand { state.globalSearchVisible = false }
    }

    private func runSearch() {
        let sources = state.sessions.sessions.map {
            GlobalSearch.Source(sessionID: $0.id, title: $0.title, text: $0.readOutput(maxBytes: 200_000))
        }
        hits = GlobalSearch.search(query, in: sources)
    }

    private func jump(to hit: GlobalSearchHit) {
        if let tab = state.tabs.first(where: { $0.root.sessionIDs.contains(hit.sessionID) }) {
            state.selectedTabID = tab.id
            state.focusSession(hit.sessionID)
        }
        state.globalSearchVisible = false
    }
}
