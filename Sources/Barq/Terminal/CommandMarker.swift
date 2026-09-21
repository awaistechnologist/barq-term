import Foundation

/// Marker-based command completion detection for `run_command`: the command
/// is suffixed with a `printf` that emits a unique token plus the exit code,
/// and we scan the output stream for it. Pure logic — unit tested.
enum CommandMarker {
    static func makeToken() -> String {
        String(format: "%08x%08x", UInt32.random(in: .min ... .max), UInt32.random(in: .min ... .max))
    }

    static func marker(token: String) -> String {
        "__BARQ_\(token)"
    }

    /// Shell line that runs `command` and then prints the marker + exit code.
    ///
    /// The command is run via `eval` on a single-quoted, quote-escaped payload.
    /// This lets multi-line scripts and heredocs execute **atomically in the
    /// current shell** (so `cd`/env changes still persist between calls) instead
    /// of being fed line-by-line over the PTY — which submitted partial commands
    /// and left the exit-code marker unmatched (`exit_code: unknown`).
    /// `printf` keeps the marker POSIX-portable (BusyBox, dash, bash, zsh).
    static func wrap(command: String, token: String) -> String {
        let escaped = command.replacingOccurrences(of: "'", with: "'\\''")
        return "eval '\(escaped)'; printf '\\n\(marker(token: token))_%s__\\n' \"$?\""
    }

    /// Scan accumulated output for the *executed* marker. The echoed command
    /// line also contains the marker text (as `..._%s__`), so only a marker
    /// followed by a numeric exit code counts as completion.
    static func extract(output: String, token: String, sentCommand: String) -> (done: Bool, payload: String, exitCode: Int?) {
        let pattern = "\(marker(token: token))_(-?[0-9]+)__"
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
            let matchRange = Range(match.range, in: output),
            let codeRange = Range(match.range(at: 1), in: output)
        else {
            return (false, cleanEcho(output, sentCommand: sentCommand, token: token), nil)
        }
        let payload = String(output[..<matchRange.lowerBound])
        let exitCode = Int(output[codeRange])
        return (true, cleanEcho(payload, sentCommand: sentCommand, token: token), exitCode)
    }

    /// Remove the echoed command line (and any line containing the marker
    /// token, e.g. the echoed printf) from captured output.
    static func cleanEcho(_ output: String, sentCommand: String, token: String) -> String {
        let lines = output.components(separatedBy: "\n")
        let filtered = lines.filter { line in
            if line.contains(token) { return false }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !sentCommand.isEmpty, trimmed.hasSuffix(sentCommand.trimmingCharacters(in: .whitespaces)) && trimmed.count <= sentCommand.count + 80 {
                return false
            }
            return true
        }
        return filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
