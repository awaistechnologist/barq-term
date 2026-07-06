import Testing
import Foundation
@testable import Barq

@Suite struct TabGroupPaletteTests {

    @Test func hashIsStableAndDeterministic() {
        // FNV-1a: same input → same output every run (unlike Swift hashValue).
        #expect(TabGroupPalette.stableHash("AWS") == TabGroupPalette.stableHash("AWS"))
        #expect(TabGroupPalette.stableHash("AWS") != TabGroupPalette.stableHash("HOME"))
    }

    @Test func colorIsFromPaletteAndStablePerName() {
        let c = TabGroupPalette.color(for: "LAB")
        #expect(TabGroupPalette.colors.contains(c))
        #expect(TabGroupPalette.color(for: "LAB") == c, "same tag always maps to the same color")
    }
}

@Suite struct TabLayoutTests {

    func tab(_ group: UUID?) -> TerminalTab {
        TerminalTab(root: .leaf(UUID().uuidString), focusedSessionID: "s", groupID: group)
    }

    @Test func ungroupedTabsRenderInline() {
        let a = tab(nil), b = tab(nil)
        let items = TabLayout.items(tabs: [a, b], groups: [])
        #expect(items.count == 2)
        if case .ungrouped = items[0] {} else { Issue.record("expected ungrouped") }
    }

    @Test func multiMemberGroupRendersBoxedAndGathersAll() {
        let g = TabGroup(name: "AWS", colorHex: "#89b4fa")
        // Interleave: grouped, lone, grouped — the group must gather both members
        // at the first member's position, lone tab after.
        let g1 = tab(g.id)
        let lone = tab(nil)
        let g2 = tab(g.id)
        let items = TabLayout.items(tabs: [g1, lone, g2], groups: [g])
        #expect(items.count == 2)
        guard case .group(let grp, let members) = items[0] else {
            Issue.record("first item should be the group"); return
        }
        #expect(grp.name == "AWS")
        #expect(members.count == 2, "both grouped tabs gathered together")
        if case .ungrouped = items[1] {} else { Issue.record("lone tab should follow") }
    }

    @Test func singleMemberGroupRendersInlineNotBoxed() {
        // A group with only one member renders inline (no container box) — the
        // box appears only once a second tab joins.
        let g = TabGroup(name: "SOLO", colorHex: "#a6e3a1")
        let only = tab(g.id)
        let items = TabLayout.items(tabs: [only], groups: [g])
        #expect(items.count == 1)
        if case .ungrouped = items[0] {} else { Issue.record("single-member group must render inline") }
    }

    @Test func tabWithDanglingGroupIDRendersUngrouped() {
        // Group was deleted but a tab still references it → render as a lone tab.
        let orphan = tab(UUID())
        let items = TabLayout.items(tabs: [orphan], groups: [])
        #expect(items.count == 1)
        if case .ungrouped = items[0] {} else { Issue.record("dangling group id must degrade gracefully") }
    }
}

@Suite @MainActor struct TabGroupOperationsTests {

    /// A minimal AppState-free harness would be ideal, but the group ops live on
    /// AppState (they touch persistence). We exercise them on the shared state,
    /// cleaning up after ourselves.
    func freshTab(in state: AppState, group: UUID? = nil) -> UUID {
        let t = TerminalTab(root: .leaf(UUID().uuidString), focusedSessionID: "x", groupID: group)
        state.tabs.append(t)
        return t.id
    }

    @Test func groupIDForNameCreatesOnceCaseInsensitive() {
        let state = AppState.shared
        let before = state.groups.count
        let a = state.groupID(forName: "PROD", createIfMissing: true)
        let b = state.groupID(forName: "prod", createIfMissing: true)
        #expect(a == b, "case-insensitive lookup reuses the group")
        #expect(state.groups.count == before + 1)
        state.ungroup(id: a!)
    }

    @Test func createGroupFromTabAndUngroup() {
        let state = AppState.shared
        let t = freshTab(in: state)
        let gid = state.createGroup(fromTab: t, name: "TESTGRP")!
        #expect(state.tabs.first { $0.id == t }?.groupID == gid)
        state.ungroup(id: gid)
        #expect(state.tabs.first { $0.id == t }?.groupID == nil)
        #expect(!state.groups.contains { $0.id == gid })
        state.tabs.removeAll { $0.id == t }
    }

    @Test func emptyGroupsArePruned() {
        let state = AppState.shared
        let t = freshTab(in: state)
        let gid = state.createGroup(fromTab: t, name: "TMP")!
        #expect(state.groups.contains { $0.id == gid })
        state.removeFromGroup(tabID: t) // last member leaves → group pruned
        #expect(!state.groups.contains { $0.id == gid })
        state.tabs.removeAll { $0.id == t }
    }

    @Test func moveTabIntoGroupClustersIt() {
        let state = AppState.shared
        let a = freshTab(in: state)
        let gid = state.createGroup(fromTab: a, name: "CLUSTER")!
        let b = freshTab(in: state)
        state.moveTab(b, intoGroup: gid)
        #expect(state.tabs.first { $0.id == b }?.groupID == gid)
        // a and b should be adjacent (clustered).
        let ia = state.tabs.firstIndex { $0.id == a }!
        let ib = state.tabs.firstIndex { $0.id == b }!
        #expect(abs(ia - ib) == 1)
        state.ungroup(id: gid)
        state.tabs.removeAll { $0.id == a || $0.id == b }
    }

    @Test func toggleCollapseAndRename() {
        let state = AppState.shared
        let t = freshTab(in: state)
        let gid = state.createGroup(fromTab: t, name: "COLL")!
        #expect(state.group(id: gid)?.collapsed == false)
        state.toggleCollapse(groupID: gid)
        #expect(state.group(id: gid)?.collapsed == true)
        state.renameGroup(id: gid, to: "RENAMED")
        #expect(state.group(id: gid)?.name == "RENAMED")
        state.ungroup(id: gid)
        state.tabs.removeAll { $0.id == t }
    }
}
