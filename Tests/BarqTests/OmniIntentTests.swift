import Testing
import Foundation
@testable import Barq

@Suite struct OmniIntentTests {

    func profiles() -> [ConnectionProfile] {
        func p(_ name: String, _ host: String, _ kind: ProfileKind = .ssh) -> ConnectionProfile {
            var x = ConnectionProfile(); x.name = name; x.host = host; x.kind = kind; x.username = "me"; return x
        }
        return [p("web-1", "10.0.0.11"), p("db-primary", "10.0.0.20"), p("lab-router", "192.168.2.1"),
                { var l = ConnectionProfile(); l.name = "Local"; l.kind = .local; return l }()]
    }

    @Test func emptyQueryYieldsNothing() {
        #expect(OmniIntent.suggestions(query: "  ", profiles: profiles()).isEmpty)
    }

    @Test func detectsQuestions() {
        #expect(OmniIntent.isQuestion("why is the disk full?"))
        #expect(OmniIntent.isQuestion("how do I restart nginx"))
        #expect(OmniIntent.isQuestion("what is my ip"))
        #expect(OmniIntent.isQuestion("explain this error"))
        #expect(OmniIntent.isQuestion("df -h?"))
        #expect(!OmniIntent.isQuestion("ls -la"))
        #expect(!OmniIntent.isQuestion("web-1"))
    }

    @Test func hostNameMatchLeadsWithConnect() {
        let s = OmniIntent.suggestions(query: "web", profiles: profiles())
        guard case .connect = s.first?.kind else { Issue.record("expected connect first for 'web'"); return }
        #expect(s.first?.title.contains("web-1") == true)
    }

    @Test func matchesByHostAndSubstring() {
        #expect(OmniIntent.matchingProfiles("192.168", profiles()).contains { $0.name == "lab-router" })
        #expect(OmniIntent.matchingProfiles("primary", profiles()).contains { $0.name == "db-primary" })
    }

    @Test func exactNameOutranksSubstring() {
        var ps = profiles()
        var db = ConnectionProfile(); db.name = "web"; db.host = "x"; ps.append(db)
        let matched = OmniIntent.matchingProfiles("web", ps)
        #expect(matched.first?.name == "web", "exact match should sort first over web-1")
    }

    @Test func questionRoutesToAIFirst() {
        let s = OmniIntent.suggestions(query: "why is disk full?", profiles: profiles())
        guard case .askAI(let q) = s.first?.kind else { Issue.record("expected askAI first"); return }
        #expect(q == "why is disk full?")
    }

    @Test func plainCommandOffersRunLocal() {
        let s = OmniIntent.suggestions(query: "ls -la", profiles: profiles())
        #expect(s.contains { if case .runLocal(let c) = $0.kind { return c == "ls -la" }; return false })
        // Not a question → askAI still offered, but runLocal present and search last.
        if case .search = s.last?.kind {} else { Issue.record("search should be last") }
    }

    @Test func alwaysOffersSearchAndAI() {
        let s = OmniIntent.suggestions(query: "randomstring", profiles: profiles())
        #expect(s.contains { if case .search = $0.kind { return true }; return false })
        #expect(s.contains { if case .askAI = $0.kind { return true }; return false })
    }

    @Test func connectCarriesProfileID() {
        let ps = profiles()
        let web = ps.first { $0.name == "web-1" }!
        let s = OmniIntent.suggestions(query: "web-1", profiles: ps)
        #expect(s.contains { if case .connect(let id) = $0.kind { return id == web.id }; return false })
    }
}
