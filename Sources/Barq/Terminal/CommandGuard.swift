import Foundation

/// Classifies commands an AI agent wants to run, so Barq can gate destructive
/// operations behind a human approval prompt. Pure logic — unit tested.
enum CommandGuard {
    enum Risk: Equatable {
        case safe
        case dangerous(reason: String)
    }

    /// Patterns that warrant a confirmation prompt before an agent runs them.
    private static let rules: [(pattern: String, reason: String)] = [
        (#"\brm\s+(-[a-zA-Z]*\s+)*(-[a-zA-Z]*r[a-zA-Z]*|--recursive)"#, "recursive delete (rm -r)"),
        (#"\brm\s+-[a-zA-Z]*f"#, "forced delete (rm -f)"),
        (#"\bmkfs\b"#, "filesystem format (mkfs)"),
        (#"\bdd\b.*\bof=/dev/"#, "raw write to a device (dd of=/dev/…)"),
        (#">\s*/dev/(sd|disk|nvme|hd)"#, "overwrite of a block device"),
        (#":\(\)\s*\{.*\|.*&.*\}"#, "fork bomb"),
        (#"\bshutdown\b|\breboot\b|\bhalt\b|\bpoweroff\b"#, "power state change"),
        (#"\b(chmod|chown)\s+-[a-zA-Z]*R[a-zA-Z]*\s+.*/(\s|$)"#, "recursive permission change on root"),
        (#"\bgit\s+push\b.*(--force|-f)\b"#, "force push"),
        (#"\bdrop\s+(database|table)\b"#, "database drop"),
        (#"\btruncate\b.*\btable\b"#, "table truncate"),
        (#"\bkill(all)?\s+-9\b"#, "force kill"),
        (#"/etc/(passwd|shadow|sudoers)"#, "edit of a sensitive system file"),
        (#"\bcurl\b.*\|\s*(sudo\s+)?(sh|bash)\b"#, "pipe-to-shell from the network"),
        (#"\bwget\b.*\|\s*(sudo\s+)?(sh|bash)\b"#, "pipe-to-shell from the network")
    ]

    static func classify(_ command: String) -> Risk {
        let lower = command.lowercased()
        for rule in rules {
            if lower.range(of: rule.pattern, options: .regularExpression) != nil {
                return .dangerous(reason: rule.reason)
            }
        }
        return .safe
    }

    static func isDangerous(_ command: String) -> Bool {
        if case .dangerous = classify(command) { return true }
        return false
    }
}
