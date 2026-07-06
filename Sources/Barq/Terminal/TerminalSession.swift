import Foundation
import AppKit
import SwiftTerm
import Combine

enum SessionStatus: Equatable {
    case connecting
    case connected
    case exited(Int32?)

    var label: String {
        switch self {
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .exited(let code): return "exited(\(code.map(String.init) ?? "-"))"
        }
    }
}

enum SessionOrigin: String {
    case user
    case agent
}

/// One live terminal session: a SwiftTerm view + backend + output tap.
/// Created and used on the main thread; `runCommand` is async.
@MainActor
final class TerminalSession: ObservableObject, Identifiable {
    nonisolated let id: String
    let profile: ConnectionProfile
    let origin: SessionOrigin
    let buffer = OutputBuffer()

    @Published var title: String
    @Published var status: SessionStatus = .connecting
    @Published var currentDirectory: String?

    private(set) var terminalView: TerminalView!
    private var streamBackend: StreamBackend?
    private var pendingPassword: String?

    init(id: String, profile: ConnectionProfile, origin: SessionOrigin, settings: SettingsStore) {
        self.id = id
        self.profile = profile
        self.origin = origin
        self.title = profile.name.isEmpty ? profile.target : profile.name
        buildView(settings: settings)
    }

    private func buildView(settings: SettingsStore) {
        let theme = settings.theme
        switch profile.kind {
        case .local, .ssh:
            let view = ProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            view.sessionID = id
            view.applyBarqStyle(theme: theme, settings: settings)
            view.onData = { [weak self] slice in
                self?.buffer.append(slice)
                self?.autoTypePasswordIfPrompted()
            }
            view.onExit = { [weak self] code in
                Task { @MainActor in
                    self?.status = .exited(code)
                    self?.streamBackend = nil
                }
            }
            terminalView = view
        case .serial, .telnet:
            let view = StreamTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            view.sessionID = id
            view.applyBarqStyle(theme: theme, settings: settings)
            view.onData = { [weak self] slice in
                self?.buffer.append(slice)
            }
            view.onExit = { [weak self] code in
                Task { @MainActor in
                    self?.status = .exited(code)
                }
            }
            view.onTitle = { [weak self] title in
                Task { @MainActor in
                    if let self, self.profile.name.isEmpty { self.title = title }
                }
            }
            terminalView = view
        }
    }

    func start() {
        switch profile.kind {
        case .local:
            let view = terminalView as! ProcessTerminalView
            let shell = SettingsStore.shared.shellPath
            let cwd = profile.workingDirectory.isEmpty
                ? FileManager.default.homeDirectoryForCurrentUser.path
                : SSHCommandBuilder.expandTilde(profile.workingDirectory)
            var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
            env.append("TERM_PROGRAM=Barq")
            view.startProcess(
                executable: shell,
                args: ["-l"],
                environment: env,
                execName: "-\((shell as NSString).lastPathComponent)",
                currentDirectory: cwd
            )
            status = .connected
        case .ssh:
            let view = terminalView as! ProcessTerminalView
            if profile.authType == .password {
                pendingPassword = ProfileStore.sharedPassword(for: profile)
            }
            var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
            env.append("TERM_PROGRAM=Barq")
            view.startProcess(
                executable: "/usr/bin/ssh",
                args: SSHCommandBuilder.sshArguments(for: profile),
                environment: env
            )
            status = .connected
        case .serial:
            let backend = SerialBackend(
                path: profile.serialDevice,
                baudRate: profile.baudRate,
                dataBits: profile.dataBits,
                stopBits: profile.stopBits,
                parity: profile.parity
            )
            attachStream(backend)
        case .telnet:
            let backend = TelnetBackend(host: profile.host, port: profile.port == 22 ? 23 : profile.port)
            attachStream(backend)
        }
    }

    private func attachStream(_ backend: StreamBackend) {
        let view = terminalView as! StreamTerminalView
        view.attach(backend: backend)
        streamBackend = backend
        do {
            try backend.open()
            status = .connected
        } catch {
            status = .exited(nil)
            view.feed(text: "\r\n\u{1B}[31m\(error.localizedDescription)\u{1B}[0m\r\n")
        }
    }

    /// One-shot password auto-type for password-auth SSH sessions.
    private func autoTypePasswordIfPrompted() {
        guard let password = pendingPassword else { return }
        let tail = buffer.tail(256).lowercased()
        guard tail.contains("password") || tail.contains("passphrase") else { return }
        // Clear before sending so a wrong-password re-prompt never loops.
        pendingPassword = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self.send(password + "\n")
        }
    }

    // MARK: I/O

    func send(_ text: String) {
        let bytes = Array(text.utf8)
        switch terminalView {
        case let view as ProcessTerminalView:
            view.process.send(data: bytes[...])
        case let view as StreamTerminalView:
            view.backend?.write(Data(bytes))
        default:
            break
        }
    }

    /// Paste text through the emulator (honors bracketed paste mode).
    func paste(_ text: String) {
        send(text)
    }

    /// Run a command and await its output using the marker technique.
    /// Falls back to a quiet-period capture for targets without a POSIX shell.
    func runCommand(_ command: String, timeout: TimeInterval = 30) async -> (output: String, exitCode: Int?) {
        let token = CommandMarker.makeToken()
        let startOffset = buffer.totalReceived
        send(CommandMarker.wrap(command: command, token: token) + "\r")

        let deadline = Date().addingTimeInterval(timeout)
        var lastTotal = buffer.totalReceived
        var quietTicks = 0

        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 120_000_000)
            let (raw, _) = buffer.since(offset: startOffset)
            let result = CommandMarker.extract(output: raw, token: token, sentCommand: command)
            if result.done {
                return (result.payload, result.exitCode)
            }
            // Fallback: if output has been quiet for ~1.5s and we got *something*,
            // return it (devices without $?/printf, e.g. some network gear).
            if buffer.totalReceived == lastTotal {
                quietTicks += 1
                if quietTicks > 12, buffer.totalReceived > startOffset {
                    return (result.payload, nil)
                }
            } else {
                quietTicks = 0
                lastTotal = buffer.totalReceived
            }
        }
        let (raw, _) = buffer.since(offset: startOffset)
        return (CommandMarker.cleanEcho(raw, sentCommand: command, token: token), nil)
    }

    func readOutput(maxBytes: Int = 8192) -> String {
        buffer.tail(maxBytes)
    }

    func terminate() {
        switch terminalView {
        case let view as ProcessTerminalView:
            view.terminate()
        case let view as StreamTerminalView:
            view.backend?.close()
        default:
            break
        }
        status = .exited(nil)
    }
}

extension ProfileStore {
    /// Password lookup usable from session construction without plumbing the
    /// store through — passwords are keyed by profile id in the Keychain.
    static func sharedPassword(for profile: ConnectionProfile) -> String? {
        Keychain.get(profile.passwordKeychainKey)
    }
}
