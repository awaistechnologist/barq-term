import Foundation

/// A restorable snapshot of an open tab: which profile, where it was, and which
/// group it belonged to (by name/color, so grouping survives a relaunch).
struct RestorableSession: Codable, Equatable {
    var profileID: UUID
    var workingDirectory: String?
    var customTitle: String?
    var groupName: String?
    var groupColorHex: String?
}

/// Persists and reloads the set of open sessions so relaunching Barq restores
/// your workspace (local shells reopen in their last directory).
enum SessionRestore {
    static var fileURL: URL { AppPaths.supportDirectory.appendingPathComponent("session-restore.json") }

    @MainActor
    static func snapshot(from tabs: [TerminalTab], groups: [TabGroup], sessions: SessionManager) -> [RestorableSession] {
        let groupByID = Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var result: [RestorableSession] = []
        for tab in tabs {
            // Restore the focused pane of each tab (splits are re-derived on demand).
            guard let session = sessions.session(id: tab.focusedSessionID) else { continue }
            let group = tab.groupID.flatMap { groupByID[$0] }
            result.append(RestorableSession(
                profileID: session.profile.id,
                workingDirectory: session.resolvedWorkingDirectory,
                customTitle: tab.customTitle,
                groupName: group?.name,
                groupColorHex: group?.colorHex
            ))
        }
        return result
    }

    static func save(_ snapshot: [RestorableSession]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    static func load() -> [RestorableSession] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([RestorableSession].self, from: data) else { return [] }
        return decoded
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
