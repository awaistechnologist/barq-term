import Darwin
import Foundation

/// Reads a process's live current working directory straight from the kernel.
///
/// Local shells under Barq don't emit OSC 7 (macOS only wires that up for
/// Apple Terminal), so `hostCurrentDirectoryUpdate` never fires. But the PTY
/// child's cwd is authoritative and always available via `proc_pidinfo`, so we
/// query it on demand for "New Tab Here" / "Copy Working Directory" / "Save
/// Directory as a Host".
enum ProcessCwd {
    static func of(pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let n = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size)
        guard n >= size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw -> String in
            guard let base = raw.bindMemory(to: CChar.self).baseAddress else { return "" }
            return String(cString: base)
        }
        return path.isEmpty ? nil : path
    }
}
