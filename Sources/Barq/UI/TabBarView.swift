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

            // Barq mark — click to return Home.
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

            GeometryReader { geo in
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
                        // Fills the empty part of the tab strip so dragging there
                        // moves the window (shrinks to nothing when tabs overflow
                        // and the strip scrolls).
                        WindowDragArea().frame(maxWidth: .infinity, minHeight: 24)
                    }
                    .padding(.vertical, 5)
                    .frame(minWidth: geo.size.width, alignment: .leading)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.82), value: state.tabs.map(\.id))
                .animation(.spring(response: 0.3, dampingFraction: 0.82), value: state.groups)
            }
            .frame(height: BarqDesign.topBarHeight)

            Spacer(minLength: BarqDesign.s2)

            controls
        }
        .padding(.trailing, BarqDesign.s3)   // leading inset is the traffic-light spacer
        .frame(height: BarqDesign.topBarHeight)
        .background(
            ZStack {
                theme.elevated
                // In front of the fill so empty top-bar space actually hits the
                // drag view; tabs/buttons live in the foreground and still win.
                WindowDragArea()
            }
        )
        .overlay(alignment: .bottom) {
            theme.hairline.frame(height: 1)
        }
    }

    private var controls: some View {
        HStack(spacing: BarqDesign.s1) {
            TopBarButton(
                symbol: state.sidebarVisible ? "sidebar.left" : "sidebar.leading",
                theme: theme,
                tint: state.sidebarVisible ? nil : theme.textTertiary,
                help: state.sidebarVisible ? "Hide hosts sidebar (⌘B)" : "Show hosts sidebar (⌘B)"
            ) { withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { state.sidebarVisible.toggle() } }

            TopBarButton(
                symbol: "sparkles", theme: theme,
                tint: state.aiPanelVisible ? theme.electric : nil,
                help: "Toggle AI panel (⇧⌘A)"
            ) { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { state.aiPanelVisible.toggle() } }

            TopBarButton(symbol: "plus", theme: theme, help: "New tab (⌘T)") {
                state.newLocalTab()
            }

            // Everything else lives in a labeled overflow menu, so no icon is a
            // mystery — the menu spells each action out in words.
            Menu {
                Button { state.paletteVisible = true } label: { Label("Command Palette", systemImage: "command") }
                Button { state.globalSearchVisible = true } label: { Label("Search All Sessions", systemImage: "magnifyingglass") }
                Button { state.composerVisible = true } label: { Label("Ask AI to Write a Command", systemImage: "wand.and.stars") }
                Divider()
                Toggle(isOn: $state.broadcastInput) { Label("Broadcast Input to All Panes", systemImage: "dot.radiowaves.left.and.right") }
                Button { state.splitFocused(direction: .horizontal) } label: { Label("Split Right", systemImage: "rectangle.split.2x1") }
                Button { state.splitFocused(direction: .vertical) } label: { Label("Split Down", systemImage: "rectangle.split.1x2") }
                Divider()
                Button { state.editingProfile = nil; state.showingProfileEditor = true } label: { Label("New Connection…", systemImage: "plus.circle") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 30)
            .help("More actions")
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
        // Visual content; non-interactive so the AppKit handle behind it
        // receives the mouse.
        HStack(spacing: 6) {
            if group != nil, !insideGroupBox {
                Circle().fill(accent).frame(width: 6, height: 6)
            }
            if isAgent {
                Image(systemName: "sparkles").font(.system(size: 9)).foregroundStyle(.purple)
            }
            Text(state.title(for: tab))
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                .lineLimit(1)
        }
        .padding(.leading, 10)
        .padding(.trailing, 26)
        .padding(.vertical, 5)
        .allowsHitTesting(false)
        .background(
            // Chip fill + AppKit handle. The handle sets mouseDownCanMoveWindow
            // = false so dragging a tab drags the tab — not the whole window,
            // which is what SwiftUI's .draggable did inside the titlebar band.
            ZStack {
                RoundedRectangle(cornerRadius: BarqDesign.rChip).fill(fillColor)
                if isSelected {
                    RoundedRectangle(cornerRadius: BarqDesign.rChip)
                        .strokeBorder(accent.opacity(0.5), lineWidth: 1)
                }
                TabDragHandle(
                    tabID: tab.id,
                    title: state.title(for: tab),
                    onSelect: { state.selectedTabID = tab.id },
                    onReorder: { dragged in state.moveTab(dragged, before: tab.id) },
                    onHover: { hovering = $0 },
                    menuProvider: buildContextMenu
                )
            }
        )
        .overlay(alignment: .trailing) {
            Button { state.closeTab(id: tab.id) } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovering || isSelected ? 1 : 0)
            .padding(.trailing, 6)
            .help("Close tab (⌘W)")
        }
    }

    private var fillColor: Color {
        if isSelected { return accent.opacity(theme.isDark ? 0.16 : 0.14) }
        if hovering { return theme.hoverFill }
        return .clear
    }

    private func buildContextMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(ClosureMenuItem(title: "Rename…") {
            if let v = TabPrompt.text(title: "Rename Tab", initial: state.title(for: tab)) {
                state.renameTab(id: tab.id, to: v)
            }
        })
        m.addItem(ClosureMenuItem(title: "Close") { state.closeTab(id: tab.id) })
        m.addItem(ClosureMenuItem(title: "Close Others") { state.closeOtherTabs(keeping: tab.id) })
        m.addItem(.separator())

        let groupItem = NSMenuItem(title: "Group", action: nil, keyEquivalent: "")
        let gm = NSMenu()
        gm.addItem(ClosureMenuItem(title: "New Group from Tab…") {
            if let v = TabPrompt.text(title: "New Group Name", initial: state.title(for: tab)) {
                state.createGroup(fromTab: tab.id, name: v)
            }
        })
        if !state.groups.isEmpty {
            gm.addItem(.separator())
            for g in state.groups {
                let item = ClosureMenuItem(title: g.name) { state.moveTab(tab.id, intoGroup: g.id) }
                if tab.groupID == g.id { item.state = .on }
                gm.addItem(item)
            }
        }
        if tab.groupID != nil {
            gm.addItem(.separator())
            gm.addItem(ClosureMenuItem(title: "Remove from Group") { state.removeFromGroup(tabID: tab.id) })
        }
        groupItem.submenu = gm
        m.addItem(groupItem)
        m.addItem(.separator())

        if let session = state.sessions.session(id: tab.focusedSessionID) {
            m.addItem(ClosureMenuItem(title: session.isRecording ? "Stop Recording" : "Start Recording") {
                session.toggleRecording()
            })
            m.addItem(.separator())
        }
        m.addItem(ClosureMenuItem(title: "Split Right") { state.selectedTabID = tab.id; state.splitFocused(direction: .horizontal) })
        m.addItem(ClosureMenuItem(title: "Split Down") { state.selectedTabID = tab.id; state.splitFocused(direction: .vertical) })
        m.addItem(ClosureMenuItem(title: "Move to New Window") { state.selectedTabID = tab.id; state.detachFocusedSession() })
        return m
    }
}

// MARK: - AppKit tab handle

/// A menu item that runs a closure — lets us build the tab context menu in
/// AppKit (the tab is now AppKit-driven for drag/selection).
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}

/// AppKit view that backs a tab: it receives the mouse (so it can suppress
/// window dragging via `mouseDownCanMoveWindow`), selects on click, starts a
/// real drag session on drag (for tear-off + reorder), accepts reorder drops,
/// and vends the context menu.
private struct TabDragHandle: NSViewRepresentable {
    let tabID: UUID
    let title: String
    let onSelect: () -> Void
    let onReorder: (UUID) -> Void
    let onHover: (Bool) -> Void
    let menuProvider: () -> NSMenu

    func makeNSView(context: Context) -> Handle {
        Handle(tabID: tabID, title: title, onSelect: onSelect, onReorder: onReorder, onHover: onHover, menuProvider: menuProvider)
    }

    func updateNSView(_ view: Handle, context: Context) {
        view.tabID = tabID
        view.title = title
        view.onSelect = onSelect
        view.onReorder = onReorder
        view.onHover = onHover
        view.menuProvider = menuProvider
    }

    final class Handle: NSView, NSDraggingSource {
        var tabID: UUID
        var title: String
        var onSelect: () -> Void
        var onReorder: (UUID) -> Void
        var onHover: (Bool) -> Void
        var menuProvider: () -> NSMenu
        private var mouseDownPoint: NSPoint?
        private var didDrag = false
        private var trackingArea: NSTrackingArea?

        init(tabID: UUID, title: String,
             onSelect: @escaping () -> Void,
             onReorder: @escaping (UUID) -> Void,
             onHover: @escaping (Bool) -> Void,
             menuProvider: @escaping () -> NSMenu) {
            self.tabID = tabID
            self.title = title
            self.onSelect = onSelect
            self.onReorder = onReorder
            self.onHover = onHover
            self.menuProvider = menuProvider
            super.init(frame: .zero)
            registerForDraggedTypes([TabTearOff.pasteboardType])
        }
        required init?(coder: NSCoder) { fatalError() }

        override var mouseDownCanMoveWindow: Bool { false }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let existing = trackingArea { removeTrackingArea(existing) }
            let area = NSTrackingArea(rect: bounds,
                                      options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                      owner: self)
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) { onHover(true) }
        override func mouseExited(with event: NSEvent) { onHover(false) }

        override func mouseDown(with event: NSEvent) {
            mouseDownPoint = event.locationInWindow
            didDrag = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = mouseDownPoint, !didDrag else { return }
            let dx = event.locationInWindow.x - start.x
            let dy = event.locationInWindow.y - start.y
            guard dx * dx + dy * dy > 16 else { return }
            didDrag = true
            beginTabDrag(with: event)
        }

        override func mouseUp(with event: NSEvent) {
            if !didDrag { onSelect() }
            mouseDownPoint = nil
        }

        override func menu(for event: NSEvent) -> NSMenu? { menuProvider() }

        // Reorder drop target.
        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            sender.draggingPasteboard.availableType(from: [TabTearOff.pasteboardType]) != nil ? .move : []
        }
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            sender.draggingPasteboard.availableType(from: [TabTearOff.pasteboardType]) != nil ? .move : []
        }
        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            guard let dragged = TabTearOff.tabID(from: sender.draggingPasteboard) else { return false }
            if dragged != tabID { onReorder(dragged) }
            return true
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .move
        }

        func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
            // Show the "release to open in a new window" affordance for the
            // duration of the drag.
            NotificationCenter.default.post(name: .barqTearOffTargeted, object: true)
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            NotificationCenter.default.post(name: .barqTearOffTargeted, object: false)
            // A tab reorder (drop onto another tab) reports .move. Anything else —
            // dropped on the terminal, elsewhere in the window, or off it — means
            // the user pulled the tab away: tear it off into its own window.
            if operation == [] {
                NotificationCenter.default.post(name: .barqTearOffTab, object: tabID)
            }
        }

        private func beginTabDrag(with event: NSEvent) {
            let item = NSPasteboardItem()
            if let data = try? JSONSerialization.data(withJSONObject: ["id": tabID.uuidString]) {
                item.setData(data, forType: TabTearOff.pasteboardType)
            }
            let dragItem = NSDraggingItem(pasteboardWriter: item)
            let image = Self.dragImage(for: title)
            let origin = convert(event.locationInWindow, from: nil)
            dragItem.setDraggingFrame(
                NSRect(x: origin.x - image.size.width / 2, y: origin.y - image.size.height / 2,
                       width: image.size.width, height: image.size.height),
                contents: image)
            beginDraggingSession(with: [dragItem], event: event, source: self)
        }

        private static func dragImage(for title: String) -> NSImage {
            let font = NSFont.systemFont(ofSize: 12)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: NSColor.labelColor,
            ]
            let text = title as NSString
            let textSize = text.size(withAttributes: attrs)
            let padX: CGFloat = 10, padY: CGFloat = 6
            let size = NSSize(width: min(textSize.width, 220) + padX * 2, height: textSize.height + padY * 2)
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
            NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 6, yRadius: 6).fill()
            text.draw(at: NSPoint(x: padX, y: padY), withAttributes: attrs)
            image.unlockFocus()
            return image
        }
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
