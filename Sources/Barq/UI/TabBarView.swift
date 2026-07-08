import SwiftUI
import UniformTypeIdentifiers

/// The seamless top bar: spans the full window width, hosts the tab strip and
/// window controls, and doubles as the window-drag region. Adopts the active
/// theme's colors.
struct TabBarView: View {
    @ObservedObject var state: AppState
    @ObservedObject var settings = SettingsStore.shared
    private var theme: BarqTheme { settings.theme }

    var body: some View {
        HStack(spacing: BarqDesign.s2) {
            // Clear the traffic-light buttons.
            Spacer().frame(width: BarqDesign.trafficLightInset)

            // Lightning wordmark — click to return Home.
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { state.goHome() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.electric)
                    Text("Barq")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(state.selectedTabID == nil ? theme.electric : theme.textPrimary)
                }
            }
            .buttonStyle(.plain)
            .help("Home")
            .padding(.trailing, BarqDesign.s2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BarqDesign.s2) {
                    ForEach(state.tabLayout) { item in
                        switch item {
                        case .group(let group, let members):
                            GroupSegment(state: state, group: group, members: members, theme: theme)
                        case .ungrouped(let tab):
                            TabItemView(state: state, tab: tab, theme: theme)
                        }
                    }
                    Color.clear
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                        .dropDestination(for: TabTransfer.self) { payload, _ in
                            guard let dragged = payload.first?.id else { return false }
                            state.moveTab(dragged, before: nil)
                            return true
                        }
                }
                .padding(.vertical, 5)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: state.tabs.map(\.id))
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: state.groups)

            Spacer(minLength: BarqDesign.s2)

            controls
        }
        .padding(.horizontal, BarqDesign.s3)
        .frame(height: BarqDesign.topBarHeight)
        .background(
            ZStack {
                WindowDragArea()
                theme.elevated
            }
        )
        .overlay(alignment: .bottom) {
            theme.hairline.frame(height: 1)
        }
    }

    private var controls: some View {
        HStack(spacing: BarqDesign.s1) {
            TopBarButton(symbol: "magnifyingglass", theme: theme, help: "Command palette (⇧⌘P)") {
                state.paletteVisible = true
            }
            TopBarButton(
                symbol: state.broadcastInput ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right",
                theme: theme, tint: state.broadcastInput ? .orange : nil,
                help: state.broadcastInput ? "Broadcasting to all panes — click to stop" : "Broadcast input to all panes"
            ) { state.broadcastInput.toggle() }
            TopBarButton(
                symbol: "sparkles", theme: theme,
                tint: state.aiPanelVisible ? theme.electric : nil,
                help: "Toggle AI panel (⇧⌘A)"
            ) { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { state.aiPanelVisible.toggle() } }
            TopBarButton(symbol: "plus", theme: theme, help: "New tab (⌘T)") {
                state.newLocalTab()
            }
        }
    }
}

/// A compact, hover-highlighting icon button for the top bar.
private struct TopBarButton: View {
    let symbol: String
    let theme: BarqTheme
    var tint: Color? = nil
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint ?? theme.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(hovering ? theme.hoverFill : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
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
    let theme: BarqTheme

    private var accent: Color { Color(BarqTheme.hexToNSColor(group.colorHex)) }
    private var containsSelected: Bool { members.contains { $0.id == state.selectedTabID } }

    var body: some View {
        HStack(spacing: BarqDesign.s1) {
            header
            if !group.collapsed {
                ForEach(members) { tab in
                    TabItemView(state: state, tab: tab, theme: theme, insideGroupBox: true)
                }
            }
        }
        .padding(.horizontal, BarqDesign.s1)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: BarqDesign.rChip + 2)
                .fill(accent.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: BarqDesign.rChip + 2).strokeBorder(accent.opacity(0.30), lineWidth: 1))
        )
        .dropDestination(for: TabTransfer.self) { payload, _ in
            guard let dragged = payload.first?.id else { return false }
            state.moveTab(dragged, intoGroup: group.id)
            return true
        }
    }

    private var header: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                state.toggleCollapse(groupID: group.id)
            }
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
            .background(RoundedRectangle(cornerRadius: 6).fill(containsSelected ? accent.opacity(0.18) : .clear))
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

// MARK: - Tab item

private struct TabItemView: View {
    @ObservedObject var state: AppState
    let tab: TerminalTab
    let theme: BarqTheme
    var insideGroupBox: Bool = false
    @State private var hovering = false

    private var group: TabGroup? { state.group(id: tab.groupID) }
    private var accent: Color { group.map { Color(BarqTheme.hexToNSColor($0.colorHex)) } ?? theme.electric }
    private var isSelected: Bool { tab.id == state.selectedTabID }
    private var isAgent: Bool { state.sessions.session(id: tab.focusedSessionID)?.origin == .agent }

    var body: some View {
        HStack(spacing: 6) {
            if group != nil, !insideGroupBox {
                Circle().fill(accent).frame(width: 6, height: 6)
            }
            if isAgent {
                Image(systemName: "sparkles").font(.system(size: 9)).foregroundStyle(.purple)
                    .help("Opened by an AI agent")
            }
            Text(state.title(for: tab))
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                .lineLimit(1)
            Button { state.closeTab(id: tab.id) } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.plain)
            .opacity(hovering || isSelected ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: BarqDesign.rChip).fill(fillColor)
                if isSelected {
                    RoundedRectangle(cornerRadius: BarqDesign.rChip)
                        .strokeBorder(accent.opacity(0.5), lineWidth: 1)
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture { state.selectedTabID = tab.id }
        .onHover { hovering = $0 }
        .draggable(TabTransfer(id: tab.id)) {
            Text(state.title(for: tab))
                .padding(6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .dropDestination(for: TabTransfer.self) { payload, _ in
            guard let dragged = payload.first?.id, dragged != tab.id else { return false }
            state.moveTab(dragged, before: tab.id)
            return true
        }
        .contextMenu { menu }
    }

    private var fillColor: Color {
        if isSelected { return accent.opacity(theme.isDark ? 0.16 : 0.14) }
        if hovering { return theme.hoverFill }
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
            Button(session.isRecording ? "Stop Recording" : "Start Recording") { session.toggleRecording() }
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
