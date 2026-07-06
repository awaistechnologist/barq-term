import Testing
import Foundation
@testable import Barq

@Suite struct SnippetTests {

    @Test func placeholderExtraction() {
        let snippet = Snippet(title: "deploy", command: "ssh ${HOST} 'systemctl restart ${SERVICE}'")
        #expect(snippet.placeholders == ["HOST", "SERVICE"])
    }

    @Test func placeholderIgnoresVaultRefs() {
        let snippet = Snippet(title: "x", command: "curl -H 'Auth: ${BARQ:TOKEN}' ${URL}")
        #expect(snippet.placeholders == ["URL"], "vault refs are not fill-in placeholders")
    }

    @Test func placeholderDeduplicates() {
        let snippet = Snippet(command: "cp ${F} ${F}.bak")
        #expect(snippet.placeholders == ["F"])
    }

    @Test func fillingSubstitutes() {
        let snippet = Snippet(command: "ssh ${HOST} -p ${PORT}")
        let filled = snippet.filled(with: ["HOST": "box", "PORT": "2222"])
        #expect(filled == "ssh box -p 2222")
    }

    @Test func fillingLeavesVaultRefsIntact() {
        let snippet = Snippet(command: "curl -H 'Auth: ${BARQ:TOKEN}' ${URL}")
        let filled = snippet.filled(with: ["URL": "http://x"])
        #expect(filled == "curl -H 'Auth: ${BARQ:TOKEN}' http://x")
    }

    @Test func storeCRUDAndSearch() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("barq-snips-\(UUID().uuidString).json")
        let store = SnippetStore(fileURL: url)
        store.upsert(Snippet(title: "restart nginx", command: "systemctl restart nginx", tags: ["ops"]))
        store.upsert(Snippet(title: "disk usage", command: "df -h", tags: ["diag"]))
        #expect(store.snippets.count == 2)
        #expect(store.search("nginx").count == 1)
        #expect(store.search("ops").count == 1)
        #expect(store.search("").count == 2)

        let reloaded = SnippetStore(fileURL: url)
        #expect(reloaded.snippets.count == 2, "snippets persist to disk")
    }
}

@Suite struct GlobalSearchTests {

    let sources = [
        GlobalSearch.Source(sessionID: "1", title: "web", text: "line one\nerror: connection refused\nline three"),
        GlobalSearch.Source(sessionID: "2", title: "db", text: "starting up\nquery OK\nERROR: deadlock detected")
    ]

    @Test func findsAcrossSessions() {
        let hits = GlobalSearch.search("error", in: sources)
        #expect(hits.count == 2, "matches in both sessions, case-insensitive")
        #expect(hits.contains { $0.sessionID == "1" && $0.lineNumber == 2 })
        #expect(hits.contains { $0.sessionID == "2" && $0.lineNumber == 3 })
    }

    @Test func caseSensitiveMode() {
        let hits = GlobalSearch.search("ERROR", in: sources, caseSensitive: true)
        #expect(hits.count == 1)
        #expect(hits[0].sessionID == "2")
    }

    @Test func matchRangeIsCorrect() {
        let hits = GlobalSearch.search("refused", in: sources)
        #expect(hits.count == 1)
        let hit = hits[0]
        let line = hit.line
        let start = line.index(line.startIndex, offsetBy: hit.matchRange.lowerBound)
        let end = line.index(line.startIndex, offsetBy: hit.matchRange.upperBound)
        #expect(String(line[start..<end]) == "refused")
    }

    @Test func emptyQueryReturnsNothing() {
        #expect(GlobalSearch.search("", in: sources).isEmpty)
    }

    @Test func respectsMaxHits() {
        let spammy = GlobalSearch.Source(sessionID: "x", title: "x",
            text: Array(repeating: "match", count: 500).joined(separator: "\n"))
        let hits = GlobalSearch.search("match", in: [spammy], maxHits: 50)
        #expect(hits.count == 50)
    }
}
