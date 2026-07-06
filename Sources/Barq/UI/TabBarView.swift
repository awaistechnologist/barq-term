import SwiftUI
import UniformTypeIdentifiers

struct TabBarView: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(state.tabLayout) { item in
                        switch item {
                        case .group(let group, let members):
                            GroupSegment(state: state, group: group, members: members)
                        case .ungrouped(let tab):
                            TabItemView(state: state, tab: tab)
                        }
                    }
                    // Trailing drop zone: move a tab to the very end / ungroup it.
                    Color.clear
                        .frame(width: 28, height: 24)
                        .contentShape(Rectangle())
                        .dropDestination(for: TabTransfer.self) { payload, _ in
                            guard let dragged = payload.first?.id else { return false }
                            state.moveTab(dragged, before: nil)
                            return true
                        }
                }
                .padding(.horizontal, 6)
                .animation(.easeInOut(duration: 0.18), value: state.tabs.map(\.id))
                .animation(.easeInOut(duration: 0.18), value: state.groups)
            }

            Spacer(minLength: 0)

            Button { state.newLocalTab() } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("New local tab (⌘T)")

            Button { state.broadcastInput.toggle() } label: {
                Image(systemName: state.broadcastInput ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right")
                    .foregroundStyle(state.broadcastInput ? Color.orange : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(state.broadcastInput ? "Broadcasting input to all panes in this tab — click to stop" : "Broadcast input to all panes in this tab")

            Button { state.aiPanelVisible.toggle() } label: {
                Image(systemName: "sparkles")
                    .foregroundStyle(state.aiPanelVisible ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help("Toggle AI panel (⇧⌘A)")
            .padding(.trailing, 8)
        }
        .frame(height: 36)
        .background(.bar)
    }
}

// MARK: - Transferable tab id (drag & drop)

struct TabTransfer: Codable, Transferable {
    let id: UUID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .barqTab)
    }
}

extension UTType {
    static let barqTab = UTType(exportedAs: "io.barq.tab")
}

// MARK: - Group segment

private struct GroupSegment: View {
    @ObservedObject var state: AppState
    let group: TabGroup
    let members: [TerminalTab]

    private var accent: Color { Color(BarqTheme.hexToNSColor(group.colorHex)) }
    private var containsSelected: Bool { members.contains { $0.id == state.selectedTabID } }

    var body: some View {
        HStack(spacing: 4) {
            header
            if !group.collapsed {
                ForEach(members) { tab in
                    TabItemView(state: state, tab: tab, insideGroupBox: true)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(accent.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(accent.opacity(0.35), lineWidth: 1))
        )
        // Dropping anywhere on the group joins it.
        .dropDestination(for: TabTransfer.self) { payload, _ in
            guard let dragged = payload.first?.id else { return false }
            state.moveTab(dragged, intoGroup: group.id)
            return true
        }
    }

    private var header: some View {
        Button {
            state.toggleCollapse(groupID: group.id)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: group.collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                Circle().fill(accent).frame(width: 7, height: 7)
                Text(group.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                if group.collapsed {
                    Text("\(members.count)")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(accent.opacity(0.30)))
                }
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(containsSelected ? accent.opacity(0.18) : .clear)
            )
        }
        .buttonStyle(.plain)
        .help(group.collapsed ? "Expand \(group.name)" : "Collapse \(group.name)")
        .contextMenu {
            Button(group.collapsed ? "Expand Group" : "Collapse Group") { state.toggleCollapse(groupID: group.id) }
            Button("Rename Group…") { renameGroup() }
            Menu("Color") {
                ForEach(TabGroupPalette.colors, id: \.self) { hex in
                    Button {
                        state.setGroupColor(id: group.id, hex: hex)
                    } label: {
                        Label(hex, systemImage: hex == group.colorHex ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
            }
            Divider()
            Button("Ungroup") { state.ungroup(id: group.id) }
            Button("Close Group", role: .destructive) {
                for tab in members { state.closeTab(id: tab.id) }
            }
        }
    }

    private func renameGroup() {
        if let value = TabPrompt.text(title: "Rename Group", initial: group.name) {
            state.renameGroup(id: group.id, to: value)
        }
    }
}

// MARK: - Tab item (chip + drag/drop + context menu)

private struct TabItemView: View {
    @ObservedObject var state: AppState
    let tab: TerminalTab
    /// True when rendered inside a group's colored box (dot would be redundant).
    var insideGroupBox: Bool = false
    @State private var hovering = false

    private var group: TabGroup? { state.group(id: tab.groupID) }
    private var accent: Color? { group.map { Color(BarqTheme.hexToNSColor($0.colorHex)) } }
    private var isSelected: Bool { tab.id == state.selectedTabID }
    private var isAgent: Bool { state.sessions.session(id: tab.focusedSessionID)?.origin == .agent }

    var body: some View {
        HStack(spacing: 6) {
            // A lone tab that belongs to a group shows the group's accent dot,
            // so its (latent) grouping is visible before a second tab joins.
            if let accent, group != nil, !insideGroupBox {
                Circle().fill(accent).frame(width: 6, height: 6)
                    .help(group.map { "Group: \($0.name)" } ?? "")
            }
            if isAgent {
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                    .foregroundStyle(.purple)
                    .help("Opened by an AI agent")
            }
            Text(state.title(for: tab))
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
            Button { state.closeTab(id: tab.id) } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.borderless)
            .opacity(hovering || isSelected ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(fillColor))
        .overlay(alignment: .bottom) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1)
                    .fill(accent ?? Color.accentColor)
                    .frame(height: 2)
                    .padding(.horizontal, 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { state.selectedTabID = tab.id }
        .onHover { hovering = $0 }
        .draggable(TabTransfer(id: tab.id)) {
            Text(state.title(for: tab))
                .padding(6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        // Drop a tab onto this chip → reorder to sit before it (adopts its group).
        .dropDestination(for: TabTransfer.self) { payload, _ in
            guard let dragged = payload.first?.id, dragged != tab.id else { return false }
            state.moveTab(dragged, before: tab.id)
            return true
        }
        .contextMenu { menu }
    }

    private var fillColor: Color {
        if isSelected { return (accent ?? .primary).opacity(0.15) }
        if hovering { return Color.primary.opacity(0.06) }
        return .clear
    }

    @ViewBuilder
    private var menu: some View {
        Button("Rename…") {
            if let v = TabPrompt.text(title: "Rename Tab", initial: state.title(for: tab)) {
                state.renameTab(id: tab.id, to: v)
            }
        }
        Button("Close") { state.closeTab(id: tab.id) }
        Button("Close Others") { state.closeOtherTabs(keeping: tab.id) }
        Divider()
        Menu("Group") {
            Button("New Group from Tab…") {
                if let v = TabPrompt.text(title: "New Group Name", initial: state.title(for: tab)) {
                    state.createGroup(fromTab: tab.id, name: v)
                }
            }
            if !state.groups.isEmpty {
                Divider()
                ForEach(state.groups) { g in
                    Button {
                        state.moveTab(tab.id, intoGroup: g.id)
                    } label: {
                        Label(g.name, systemImage: tab.groupID == g.id ? "checkmark" : "circle")
                    }
                }
            }
            if tab.groupID != nil {
                Divider()
                Button("Remove from Group") { state.removeFromGroup(tabID: tab.id) }
            }
        }
        Divider()
        if let session = state.sessions.session(id: tab.focusedSessionID) {
            Button(session.isRecording ? "Stop Recording" : "Start Recording") {
                session.toggleRecording()
            }
            Divider()
        }
        Button("Split Right") { state.selectedTabID = tab.id; state.splitFocused(direction: .horizontal) }
        Button("Split Down") { state.selectedTabID = tab.id; state.splitFocused(direction: .vertical) }
        Button("Move to New Window") { state.selectedTabID = tab.id; state.detachFocusedSession() }
    }
}

// MARK: - Shared text prompt

enum TabPrompt {
    @MainActor
    static func text(title: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
