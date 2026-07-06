import Foundation

/// A colored, collapsible group of tabs. Groups form automatically from a
/// profile's connection tag (HOME, AWS, LAB, …) and can also be created,
/// renamed, recolored, and reordered by hand.
struct TabGroup: Identifiable, Hashable {
    let id: UUID
    var name: String
    var colorHex: String
    var collapsed: Bool

    init(id: UUID = UUID(), name: String, colorHex: String, collapsed: Bool = false) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.collapsed = collapsed
    }
}

/// Deterministic group colors so a tag always gets the same hue across launches
/// (Catppuccin accent palette).
enum TabGroupPalette {
    static let colors = [
        "#f38ba8", // red
        "#fab387", // peach
        "#f9e2af", // yellow
        "#a6e3a1", // green
        "#94e2d5", // teal
        "#89b4fa", // blue
        "#cba6f7", // mauve
        "#f5c2e7"  // pink
    ]

    /// Stable FNV-1a hash (Swift's `hashValue` is randomized per launch).
    static func stableHash(_ s: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for byte in s.utf8 {
            h = (h ^ UInt32(byte)) &* 16_777_619
        }
        return h
    }

    static func color(for name: String) -> String {
        colors[Int(stableHash(name) % UInt32(colors.count))]
    }
}

/// One rendered element of the tab bar, in display order.
enum TabLayoutItem: Identifiable {
    case group(TabGroup, [TerminalTab])
    case ungrouped(TerminalTab)

    var id: String {
        switch self {
        case .group(let g, _): return "group-\(g.id.uuidString)"
        case .ungrouped(let t): return "tab-\(t.id.uuidString)"
        }
    }
}

/// Pure layout: turns the flat `tabs` list + `groups` into an ordered list of
/// group segments and lone tabs.
///
/// A group with **two or more** members renders as a boxed segment at the
/// position of its first member, gathering all members there (so a group's tabs
/// cluster even if the array isn't contiguous). A group with a **single** member
/// renders inline as a lone tab — the chip still carries the group's accent
/// color, so the container only appears once it holds more than one tab (the
/// modern "groups form when they matter" behavior). Ungrouped tabs render inline
/// in order.
enum TabLayout {
    static func items(tabs: [TerminalTab], groups: [TabGroup]) -> [TabLayoutItem] {
        let groupByID = Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let memberCounts = tabs.reduce(into: [UUID: Int]()) { counts, tab in
            if let gid = tab.groupID { counts[gid, default: 0] += 1 }
        }
        var emitted = Set<UUID>()
        var result: [TabLayoutItem] = []
        for tab in tabs {
            if let gid = tab.groupID, let group = groupByID[gid], (memberCounts[gid] ?? 0) >= 2 {
                guard !emitted.contains(gid) else { continue }
                emitted.insert(gid)
                result.append(.group(group, tabs.filter { $0.groupID == gid }))
            } else {
                result.append(.ungrouped(tab))
            }
        }
        return result
    }
}
