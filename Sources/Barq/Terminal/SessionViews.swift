import Foundation
import AppKit
import SwiftTerm

// MARK: - Process-backed terminal (local shell, ssh)

/// LocalProcessTerminalView subclass that taps the raw output stream so the
/// vault/AI/MCP layers can read it, without interfering with rendering.
final class ProcessTerminalView: LocalProcessTerminalView {
    var sessionID: String?
    var onData: ((ArraySlice<UInt8>) -> Void)?
    var onExit: ((Int32?) -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        onData?(slice)
        super.dataReceived(slice: slice)
    }

    override func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        super.processTerminated(source, exitCode: exitCode)
        onExit?(exitCode)
    }
}

// MARK: - Stream-backed terminal (serial, telnet)

protocol StreamBackend: AnyObject {
    var onData: ((ArraySlice<UInt8>) -> Void)? { get set }
    var onClosed: ((String?) -> Void)? { get set }
    func open() throws
    func write(_ data: Data)
    func close()
}

/// TerminalView wired to an arbitrary byte-stream backend (serial port, raw
/// TCP/telnet). Keyboard input goes to the backend; backend data is fed to
/// the emulator and the tap.
final class StreamTerminalView: TerminalView, TerminalViewDelegate {
    var sessionID: String?
    var backend: StreamBackend?
    var onData: ((ArraySlice<UInt8>) -> Void)?
    var onExit: ((Int32?) -> Void)?
    var onTitle: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        terminalDelegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        terminalDelegate = self
    }

    func attach(backend: StreamBackend) {
        self.backend = backend
        backend.onData = { [weak self] slice in
            self?.onData?(slice)
            DispatchQueue.main.async {
                self?.feed(byteArray: slice)
            }
        }
        backend.onClosed = { [weak self] message in
            DispatchQueue.main.async {
                if let message {
                    self?.feed(text: "\r\n\u{1B}[31m\(message)\u{1B}[0m\r\n")
                }
                self?.onExit?(nil)
            }
        }
    }

    // MARK: TerminalViewDelegate

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        backend?.write(Data(data))
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: TerminalView, title: String) {
        onTitle?(title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func scrolled(source: TerminalView, position: Double) {}

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }

    func bell(source: TerminalView) {
        NSSound.beep()
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        if let str = String(bytes: content, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([str as NSString])
        }
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

// MARK: - Theming

extension TerminalView {
    func applyBarqStyle(theme: BarqTheme, settings: SettingsStore) {
        installColors(theme.termColors)
        nativeBackgroundColor = theme.backgroundColor
        nativeForegroundColor = theme.foregroundColor
        caretColor = theme.cursorColor
        if let font = NSFont(name: settings.fontName, size: settings.fontSize) {
            self.font = font
        } else {
            self.font = NSFont.monospacedSystemFont(ofSize: settings.fontSize, weight: .regular)
        }
        if settings.useMetalRenderer {
            try? setUseMetal(true)
        }
    }
}
