import Foundation

struct ModelRecommendation: Equatable {
    let model: String       // ollama tag, e.g. "granite4:7b-a1b-h"
    let reason: String
    let source: String      // "llm-checker" or "Barq"
}

/// Recommends the best local Ollama model for this Mac. Prefers `llm-checker`
/// if it's installed (honoring its per-hardware decision); otherwise falls back
/// to a built-in RAM-tiered heuristic. The heuristic is pure and unit-tested.
enum ModelAdvisor {

    static var physicalRAMGB: Int {
        Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
    }

    /// Built-in decision, tiered by unified memory — coding/terminal focused,
    /// using models that are strong and responsive at each tier.
    static func heuristic(ramGB: Int) -> ModelRecommendation {
        let r: (String, String)
        switch ramGB {
        case ..<8:   r = ("qwen3:1.7b",         "Small and fast — best fit for limited memory.")
        case 8..<16: r = ("qwen3:4b-instruct",  "Fast, capable general + coding model for ~8–16 GB.")
        case 16..<64: r = ("granite4:7b-a1b-h", "A fast mixture-of-experts coder that fits comfortably and answers quickly.")
        default:     r = ("qwen3:30b",          "A high-quality reasoning model your memory can handle.")
        }
        return ModelRecommendation(model: r.0, reason: r.1, source: "Barq")
    }

    /// Async recommendation: tries llm-checker, else the heuristic.
    static func recommend() async -> ModelRecommendation {
        if let picked = await llmCheckerPick() {
            return picked
        }
        return heuristic(ramGB: physicalRAMGB)
    }

    /// Run `llm-checker recommend` and parse its coding pick, if installed.
    private static func llmCheckerPick() async -> ModelRecommendation? {
        guard let bin = OllamaSetup.locate("llm-checker") else { return nil }
        guard let out = try? await OllamaSetup.run(bin, ["recommend", "--optimize", "coding", "--no-verbose"], timeout: 40),
              out.exitCode == 0 else { return nil }
        // Find the first "ollama pull <model>" line under the Coding section.
        for line in out.stdout.components(separatedBy: "\n") {
            if let range = line.range(of: "ollama pull ") {
                let tag = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if !tag.isEmpty {
                    return ModelRecommendation(model: tag, reason: "Chosen by llm-checker for this hardware.", source: "llm-checker")
                }
            }
        }
        return nil
    }
}
