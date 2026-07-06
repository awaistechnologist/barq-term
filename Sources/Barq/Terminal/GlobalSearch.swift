import Foundation

struct GlobalSearchHit: Identifiable, Hashable {
    let id = UUID()
    let sessionID: String
    let sessionTitle: String
    let lineNumber: Int
    let line: String
    /// Character range of the match within `line`, for highlighting.
    let matchRange: Range<Int>
}

/// Searches across many sessions' scrollback text. Pure over its inputs so it
/// can be unit tested without live terminals.
enum GlobalSearch {
    struct Source {
        let sessionID: String
        let title: String
        let text: String
    }

    static func search(_ query: String, in sources: [Source], caseSensitive: Bool = false, maxHits: Int = 200) -> [GlobalSearchHit] {
        let needle = caseSensitive ? query : query.lowercased()
        guard !needle.isEmpty else { return [] }
        var hits: [GlobalSearchHit] = []
        for source in sources {
            let lines = source.text.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let haystack = caseSensitive ? line : line.lowercased()
                guard let range = haystack.range(of: needle) else { continue }
                let start = haystack.distance(from: haystack.startIndex, to: range.lowerBound)
                hits.append(GlobalSearchHit(
                    sessionID: source.sessionID,
                    sessionTitle: source.title,
                    lineNumber: index + 1,
                    line: line.trimmingCharacters(in: .whitespaces),
                    matchRange: start..<(start + needle.count)
                ))
                if hits.count >= maxHits { return hits }
            }
        }
        return hits
    }
}
