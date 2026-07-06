import SwiftUI

struct TabBarView: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(state.tabs) { tab in
                        TabChip(
                            title: state.title(for: tab),
                            isSelected: tab.id == state.selectedTabID,
                            isAgent: state.sessions.session(id: tab.focusedSessionID)?.origin == .agent,
                            select: { state.selectedTabID = tab.id },
                            close: { state.closeTab(id: tab.id) }
                        )
                    }
                }
                .padding(.horizontal, 6)
            }

            Spacer(minLength: 0)

            Button {
                state.newLocalTab()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("New local tab (⌘T)")

            Button {
                state.aiPanelVisible.toggle()
            } label: {
                Image(systemName: "sparkles")
                    .foregroundStyle(state.aiPanelVisible ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help("Toggle AI panel (⇧⌘A)")
            .padding(.trailing, 8)
        }
        .frame(height: 34)
        .background(.bar)
    }
}

private struct TabChip: View {
    let title: String
    let isSelected: Bool
    let isAgent: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            if isAgent {
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                    .foregroundStyle(.purple)
                    .help("Opened by an AI agent")
            }
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.borderless)
            .opacity(hovering || isSelected ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.primary.opacity(0.12) : (hovering ? Color.primary.opacity(0.06) : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hovering = $0 }
    }
}
