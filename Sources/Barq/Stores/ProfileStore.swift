import Foundation
import Combine

final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [ConnectionProfile] = []

    private let fileURL: URL

    init(fileURL: URL = AppPaths.profilesFile) {
        self.fileURL = fileURL
        load()
        if profiles.isEmpty {
            // A starter local-shell profile so the app is useful on first launch.
            var local = ConnectionProfile()
            local.name = "Local"
            local.kind = .local
            local.tags = ["LOCAL"]
            profiles = [local]
            save()
        }
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([ConnectionProfile].self, from: data) {
            profiles = decoded
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(profiles) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func profile(id: UUID) -> ConnectionProfile? {
        profiles.first { $0.id == id }
    }

    func profile(named name: String) -> ConnectionProfile? {
        profiles.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func upsert(_ profile: ConnectionProfile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
        save()
    }

    func remove(id: UUID) {
        if let profile = profile(id: id) {
            Keychain.delete(profile.passwordKeychainKey)
        }
        profiles.removeAll { $0.id == id }
        save()
    }

    func setPassword(_ password: String?, for profile: ConnectionProfile) {
        if let password, !password.isEmpty {
            Keychain.set(password, for: profile.passwordKeychainKey)
        } else {
            Keychain.delete(profile.passwordKeychainKey)
        }
    }

    func password(for profile: ConnectionProfile) -> String? {
        Keychain.get(profile.passwordKeychainKey)
    }

    /// All distinct tags, sorted; profiles with no tag fall under "OTHER".
    var allTags: [String] {
        var tags = Set<String>()
        for profile in profiles {
            if profile.tags.isEmpty { tags.insert("OTHER") } else { tags.formUnion(profile.tags) }
        }
        return tags.sorted()
    }

    func profiles(tag: String) -> [ConnectionProfile] {
        profiles.filter { tag == "OTHER" ? $0.tags.isEmpty : $0.tags.contains(tag) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Import / Export

    func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(profiles)
    }

    func importJSON(_ data: Data, merge: Bool = true) throws {
        let incoming = try JSONDecoder().decode([ConnectionProfile].self, from: data)
        if merge {
            for profile in incoming where !profiles.contains(where: { $0.id == profile.id }) {
                profiles.append(profile)
            }
        } else {
            profiles = incoming
        }
        save()
    }
}
