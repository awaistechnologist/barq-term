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

/// How an SSH profile's session is launched.
enum SessionLaunch {
    case shell   // interactive ssh shell (default)
    case sftp    // interactive sftp subsystem
}

/// One live terminal session: a SwiftTerm view + backend + output tap.
/// Created and used on the main thread; `runCommand` is async.
@MainActor
final class TerminalSession: ObservableObject, Identifiable {
    nonisolated let id: String
    let profile: ConnectionProfile
    let origin: SessionOrigin
    let launch: SessionLaunch
    let buffer = OutputBuffer()

    @Published var title: String
    @Published var status: SessionStatus = .connecting
    @Published var currentDirectory: String?
    @Published var isRecording = false

    let recorder = SessionRecorder()

    private(set) var terminalView: TerminalView!
    private var streamBackend: StreamBackend?
    private var pendingPassword: String?
    private var processAdapter: ProcessEventAdapter?

    init(id: String, profile: ConnectionProfile, origin: SessionOrigin, launch: SessionLaunch = .shell, settings: SettingsStore) {
        self.id = id
        self.profile = profile
        self.origin = origin
        self.launch = launch
        let baseTitle = profile.name.isEmpty ? profile.target : profile.name
        self.title = launch == .sftp ? "SFTP · \(baseTitle)" : baseTitle
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
                self?.recordSlice(slice)
                self?.autoTypePasswordIfPrompted()
            }
            view.onExit = { [weak self] code in
                Task { @MainActor in
                    self?.status = .exited(code)
                    self?.streamBackend = nil
                }
            }
            let adapter = ProcessEventAdapter(session: self)
            view.processDelegate = adapter
            processAdapter = adapter
            if profile.kind == .ssh {
                view.enableFileDrops()
                view.onFilesDropped = { [weak self] paths in
                    Task { @MainActor in self?.handleDroppedFiles(paths) }
                }
            }
            terminalView = view
        case .serial, .telnet:
            let view = StreamTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
            view.sessionID = id
            view.applyBarqStyle(theme: theme, settings: settings)
            view.onData = { [weak self] slice in
                self?.buffer.append(slice)
                self?.recordSlice(slice)
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
            // Materialize a pasted key to a temp file so ssh can `-i` it.
            let connectProfile = SSHKeyMaterializer.resolvedForConnect(profile)
            var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
            env.append("TERM_PROGRAM=Barq")
            let executable = launch == .sftp ? "/usr/bin/sftp" : "/usr/bin/ssh"
            let args = launch == .sftp
                ? SSHCommandBuilder.sftpArguments(for: connectProfile)
                : SSHCommandBuilder.sshArguments(for: connectProfile)
            view.startProcess(executable: executable, args: args, environment: env)
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
    ///
    /// For POSIX-shell targets (local/ssh) we always wait for the exit-code
    /// marker, so a command that is merely slow or quiet (`sleep 2 && ls`) is
    /// never cut short. Only serial/telnet devices — which lack `$?`/`printf`
    /// and never emit a marker — use the quiet-period fallback.
    func runCommand(_ command: String, timeout: TimeInterval = 30) async -> (output: String, exitCode: Int?) {
        let token = CommandMarker.makeToken()
        let startOffset = buffer.totalReceived
        send(CommandMarker.wrap(command: command, token: token) + "\r")

        let usesQuietFallback = (profile.kind == .serial || profile.kind == .telnet)
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
            // Quiet-period fallback for marker-less devices only. Never applied
            // to shells, where silence just means the command is still running.
            if usesQuietFallback {
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
        }
        let (raw, _) = buffer.since(offset: startOffset)
        return (CommandMarker.cleanEcho(raw, sentCommand: command, token: token), nil)
    }

    func readOutput(maxBytes: Int = 8192) -> String {
        buffer.tail(maxBytes)
    }

    /// Upload dropped files to the remote working directory over SCP.
    private func handleDroppedFiles(_ paths: [String]) {
        let remoteDir = currentDirectory ?? "."
        for path in paths {
            let name = (path as NSString).lastPathComponent
            terminalView.feed(text: "\r\n\u{1B}[36m⇡ Uploading \(name) → \(remoteDir)…\u{1B}[0m\r\n")
            SCPUploader.upload(localPath: path, remoteDir: remoteDir, profile: profile) { [weak self] ok, err in
                let msg = ok
                    ? "\u{1B}[32m✓ Uploaded \(name)\u{1B}[0m"
                    : "\u{1B}[31m✗ Upload failed: \(err.trimmingCharacters(in: .whitespacesAndNewlines))\u{1B}[0m"
                self?.terminalView.feed(text: "\(msg)\r\n")
            }
        }
    }

    private nonisolated func recordSlice(_ slice: ArraySlice<UInt8>) {
        // No unlocked `isRecording` fast-path: record() re-checks under its own
        // lock, so this is safe when called from the serial/telnet IO queue
        // while the main thread toggles recording.
        recorder.record(String(decoding: slice, as: UTF8.self))
    }

    /// Toggle asciinema recording; returns the .cast URL when stopping.
    @discardableResult
    func toggleRecording() -> URL? {
        if recorder.isRecording {
            let url = recorder.stop()
            isRecording = false
            if let url {
                terminalView.feed(text: "\r\n\u{1B}[32m● Recording saved: \(url.path)\u{1B}[0m\r\n")
            }
            return url
        } else {
            let dir = AppPaths.supportDirectory.appendingPathComponent("recordings", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = recorder.start(title: title, to: dir)
            isRecording = recorder.isRecording
            terminalView.feed(text: "\r\n\u{1B}[31m● Recording started\u{1B}[0m\r\n")
            return url
        }
    }

    /// Show SwiftTerm's built-in find bar (⌘F).
    func showFindBar() {
        let item = NSMenuItem()
        item.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        terminalView.performFindPanelAction(item)
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

/// Routes LocalProcessTerminalView delegate callbacks (title, OSC7 cwd)
/// back into the session.
final class ProcessEventAdapter: LocalProcessTerminalViewDelegate {
    private weak var session: TerminalSession?

    init(session: TerminalSession) {
        self.session = session
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor [weak session] in
            guard let session, !title.isEmpty else { return }
            if session.profile.kind == .local || session.profile.name.isEmpty {
                session.title = title
            }
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        let path = OSC7.parsePath(directory)
        Task { @MainActor [weak session] in
            guard let session, let path else { return }
            session.currentDirectory = path
            if session.profile.kind == .local {
                session.title = (path as NSString).lastPathComponent
            }
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        // Handled by ProcessTerminalView.onExit.
    }
}
