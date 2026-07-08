import Foundation
import Combine

/// A reusable command snippet. `${VAR}` placeholders can be filled at run time,
/// and `${BARQ:NAME}` vault references are expanded like anywhere else.
struct Snippet: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String = ""
    var command: String = ""
    var tags: [String] = []

    init(id: UUID = UUID(), title: String = "", command: String = "", tags: [String] = []) {
        self.id = id; self.title = title; self.command = command; self.tags = tags
    }

    enum CodingKeys: String, CodingKey { case id, title, command, tags }

    // Resilient: missing keys fall back to defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? def }
        id = d(.id, UUID())
        title = d(.title, "")
        command = d(.command, "")
        tags = d(.tags, [])
    }

    /// Placeholder names of the form `${NAME}` (excluding `${BARQ:...}`).
    var placeholders: [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\$\{(?!BARQ:)([A-Za-z0-9_]+)\}"#) else { return [] }
        let range = NSRange(command.startIndex..., in: command)
        var names: [String] = []
        for match in regex.matches(in: command, range: range) {
            if let r = Range(match.range(at: 1), in: command) {
                let name = String(command[r])
                if !names.contains(name) { names.append(name) }
            }
        }
        return names
    }

    /// Substitute placeholder values into the command.
    func filled(with values: [String: String]) -> String {
        var result = command
        for (key, value) in values {
            result = result.replacingOccurrences(of: "${\(key)}", with: value)
        }
        return result
    }
}

final class SnippetStore: ObservableObject {
    @Published private(set) var snippets: [Snippet] = []
    private let fileURL: URL

    init(fileURL: URL = AppPaths.supportDirectory.appendingPathComponent("snippets.json")) {
        self.fileURL = fileURL
        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else { return }
        do {
            snippets = try JSONDecoder().decode([Snippet].self, from: data)
        } catch {
            StoreBackup.backup(fileURL)
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(snippets) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func upsert(_ snippet: Snippet) {
        if let idx = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[idx] = snippet
        } else {
            snippets.append(snippet)
        }
        save()
    }

    func remove(id: UUID) {
        snippets.removeAll { $0.id == id }
        save()
    }

    /// Fuzzy-ish search by title, command, or tag.
    func search(_ query: String) -> [Snippet] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return snippets }
        return snippets.filter {
            $0.title.lowercased().contains(q) ||
            $0.command.lowercased().contains(q) ||
            $0.tags.contains { $0.lowercased().contains(q) }
        }
    }
}
