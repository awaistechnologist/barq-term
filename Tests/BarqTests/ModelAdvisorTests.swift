import Testing
import Foundation
@testable import Barq

@Suite struct ModelAdvisorTests {

    @Test func tiersByMemory() {
        #expect(ModelAdvisor.heuristic(ramGB: 4).model == "qwen3:1.7b")
        #expect(ModelAdvisor.heuristic(ramGB: 12).model == "qwen3:4b-instruct")
        #expect(ModelAdvisor.heuristic(ramGB: 36).model == "granite4:7b-a1b-h")
        #expect(ModelAdvisor.heuristic(ramGB: 128).model == "qwen3:30b")
    }

    @Test func boundariesPickTheRightTier() {
        #expect(ModelAdvisor.heuristic(ramGB: 8).model == "qwen3:4b-instruct")
        #expect(ModelAdvisor.heuristic(ramGB: 16).model == "granite4:7b-a1b-h")
        #expect(ModelAdvisor.heuristic(ramGB: 64).model == "qwen3:30b")
    }

    @Test func everyRecommendationHasReasonAndSource() {
        for ram in [4, 12, 36, 128] {
            let r = ModelAdvisor.heuristic(ramGB: ram)
            #expect(!r.reason.isEmpty)
            #expect(r.source == "Barq")
            #expect(r.model.contains(":"), "should be a valid ollama tag")
        }
    }
}
