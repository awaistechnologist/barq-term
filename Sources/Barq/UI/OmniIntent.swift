import Foundation

/// What the omni-bar thinks the user wants. Pure value type — unit tested.
enum OmniKind: Equatable {
    case connect(UUID)      // connect to a saved profile
    case runLocal(String)   // run a command in a new local shell
    case askAI(String)      // ask the AI assistant
    case search(String)     // search all open sessions
}

struct OmniSuggestion: Equatable, Identifiable {
    let kind: OmniKind
    let title: String
    let subtitle: String
    var id: String { "\(title)|\(subtitle)" }
}

/// The omni-bar brain: turns a free-text query into a ranked list of actions,
/// interpreting intent (connect / run / ask / search) rather than requiring
/// shell syntax. Pure over its inputs.
enum OmniIntent {
    /// Words that signal a natural-language question → route to AI.
    private static let questionStarters = [
        "why", "how", "what", "explain", "fix", "which", "who", "when",
        "is", "are", "can", "should", "does", "do", "help"
    ]

    static func isQuestion(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return false }
        if t.hasSuffix("?") { return true }
        let first = t.split(separator: " ").first.map(String.init) ?? t
        return questionStarters.contains(first)
    }

    static func matchingProfiles(_ query: String, _ profiles: [ConnectionProfile], limit: Int = 4) -> [ConnectionProfile] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let scored: [(ConnectionProfile, Int)] = profiles.compactMap { p in
            let name = p.name.lowercased(), host = p.host.lowercased(), target = p.target.lowercased()
            if name == q { return (p, 0) }
            if name.hasPrefix(q) { return (p, 1) }
            if host.hasPrefix(q) { return (p, 2) }
            if name.contains(q) || host.contains(q) || target.contains(q) { return (p, 3) }
            return nil
        }
        return scored.sorted { $0.1 < $1.1 }.prefix(limit).map(\.0)
    }

    static func suggestions(query: String, profiles: [ConnectionProfile]) -> [OmniSuggestion] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }

        var out: [OmniSuggestion] = []
        let question = isQuestion(q)
        let matches = matchingProfiles(q, profiles)

        // Strongest host match leads unless the text is clearly a question.
        if question {
            out.append(.init(kind: .askAI(q), title: "Ask Barq AI", subtitle: "\u{201C}\(q)\u{201D}"))
        }
        for p in matches {
            out.append(.init(kind: .connect(p.id),
                             title: "Connect to \(p.name.isEmpty ? p.target : p.name)",
                             subtitle: "\(p.kind.label) \u{00B7} \(p.target)"))
        }
        if !question {
            out.append(.init(kind: .runLocal(q), title: "Run in a new shell", subtitle: q))
            out.append(.init(kind: .askAI(q), title: "Ask Barq AI", subtitle: "\u{201C}\(q)\u{201D}"))
        }
        out.append(.init(kind: .search(q), title: "Search all sessions", subtitle: "for \u{201C}\(q)\u{201D}"))
        return out
    }
}
