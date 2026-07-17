import Foundation

/// Normalizes the raw `wait()` status SwiftTerm hands back into a conventional
/// exit code. SwiftTerm passes the value straight from `waitpid`, so a remote
/// shell that exits 2 arrives as 512 (`2 << 8`). This applies the standard
/// POSIX decoding: `WEXITSTATUS` for a normal exit, or `128 + signal` (shell
/// convention) when the process was killed by a signal.
enum ExitStatus {
    static func normalize(_ raw: Int32?) -> Int32? {
        guard let raw else { return nil }
        // A raw wait() status encodes exit-vs-signal in its low 7 bits; normal
        // exits are always shifted left 8, so a small value is a signal, not an
        // already-normalized code.
        let signal = raw & 0x7f
        if signal == 0 {
            return (raw >> 8) & 0xff        // WIFEXITED → WEXITSTATUS
        }
        return 128 + signal                 // killed by signal (shell convention)
    }
}
