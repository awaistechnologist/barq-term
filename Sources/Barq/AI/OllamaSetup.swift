import Foundation

/// Locates and drives the `ollama` (and `llm-checker`) CLIs from a GUI app,
/// whose PATH is minimal — so we search the usual install locations.
enum OllamaSetup {

    struct RunResult { let exitCode: Int32; let stdout: String; let stderr: String }

    /// Candidate directories where Homebrew / npm / node tools live.
    private static var searchDirs: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
                    "\(home)/.volta/bin", "\(home)/.npm-global/bin", "\(home)/bin"]
        // node/nvm versioned bin dirs
        let nvm = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm) {
            dirs += versions.map { "\(nvm)/\($0)/bin" }
        }
        return dirs
    }

    /// Find an executable by name, or nil if not installed.
    static func locate(_ name: String) -> String? {
        for dir in searchDirs {
            let path = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    static var ollamaPath: String? { locate("ollama") }

    /// Run a command, capturing output, with a timeout.
    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 30) async throws -> RunResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
            process.terminationHandler = { proc in
                timer.cancel()
                let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: RunResult(exitCode: proc.terminationStatus, stdout: o, stderr: e))
            }
            do { try process.run() } catch { timer.cancel(); continuation.resume(throwing: error) }
        }
    }

    /// Is the Ollama server reachable?
    static func serverRunning() async -> Bool {
        guard let url = URL(string: "\(SettingsStore.shared.ollamaBaseURL)/api/tags") else { return false }
        var req = URLRequest(url: url); req.timeoutInterval = 2
        return (try? await URLSession.shared.data(for: req)) != nil
    }

    /// `ollama pull <model>`, streaming progress lines to `progress`.
    static func pull(_ model: String, progress: @escaping (String) -> Void, completion: @escaping (Bool, String) -> Void) {
        guard let ollama = ollamaPath else {
            completion(false, "Ollama isn't installed. Get it from ollama.com, then try again.")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ollama)
        process.arguments = ["pull", model]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            // Progress lines are \r-delimited; show the last non-empty token.
            let last = text.replacingOccurrences(of: "\r", with: "\n")
                .components(separatedBy: "\n").last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if let last { DispatchQueue.main.async { progress(last) } }
        }
        process.terminationHandler = { proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                completion(proc.terminationStatus == 0,
                           proc.terminationStatus == 0 ? "Installed \(model)" : "Failed to install \(model)")
            }
        }
        do { try process.run() } catch { completion(false, error.localizedDescription) }
    }
}
