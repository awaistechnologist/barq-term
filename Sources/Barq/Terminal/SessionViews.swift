import Foundation
import AppKit
import SwiftTerm
import UniformTypeIdentifiers

// MARK: - Tab tear-off drop

/// Decodes the `io.barq.tab` pasteboard payload that SwiftUI's `.draggable`
/// writes for a dragged tab. Used to accept tear-off drops at the AppKit level —
/// SwiftUI `.dropDestination` doesn't fire reliably over the terminal because
/// the SwiftTerm NSView is frontmost and captures the drag.
enum TabTearOff {
    static let pasteboardType = NSPasteboard.PasteboardType(UTType.barqTab.identifier)

    private struct Payload: Codable { let id: UUID }

    static func tabID(from pasteboard: NSPasteboard) -> UUID? {
        guard let data = pasteboard.data(forType: pasteboardType) else { return nil }
        if let p = try? JSONDecoder().decode(Payload.self, from: data) { return p.id }
        if let p = try? PropertyListDecoder().decode(Payload.self, from: data) { return p.id }
        return nil
    }
}


// MARK: - Process-backed terminal (local shell, ssh)

/// LocalProcessTerminalView subclass that taps the raw output stream so the
/// vault/AI/MCP layers can read it, without interfering with rendering.
final class ProcessTerminalView: LocalProcessTerminalView {
    var sessionID: String?
    var onData: ((ArraySlice<UInt8>) -> Void)?
    var onExit: ((Int32?) -> Void)?
    /// Called with dropped file paths (used for SCP upload on SSH sessions).
    var onFilesDropped: (([String]) -> Void)?

    /// Accept file drops for SCP upload (SSH sessions).
    func enableFileDrops() {
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onFilesDropped != nil ? .copy : super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let onFilesDropped,
              let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              !urls.isEmpty else {
            return super.performDragOperation(sender)
        }
        onFilesDropped(urls.map(\.path))
        return true
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        onData?(slice)
        super.dataReceived(slice: slice)
    }

    override func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        super.processTerminated(source, exitCode: exitCode)
        onExit?(exitCode)
    }

    // MARK: Right-click quick actions

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "")
        menu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "")
        menu.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "")
        menu.addItem(.separator())
        addAction(menu, "New Tab Here", "newTabHere")
        addAction(menu, "Save Directory as a Host…", "saveDirAsProfile")
        addAction(menu, "Copy Working Directory", "copyCwd")
        return menu
    }

    private func addAction(_ menu: NSMenu, _ title: String, _ key: String) {
        let item = NSMenuItem(title: title, action: #selector(barqAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = key
        menu.addItem(item)
    }

    @objc private func barqAction(_ sender: NSMenuItem) {
        guard let sessionID, let key = sender.representedObject as? String else { return }
        NotificationCenter.default.post(name: .barqTerminalAction, object: sessionID, userInfo: ["action": key])
    }

    // SwiftTerm's validateUserInterfaceItem returns false for actions it doesn't
    // know, which greys out our custom menu items. Whitelist ours.
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(barqAction(_:)) { return true }
        return super.validateUserInterfaceItem(item)
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
        // Force CoreGraphics rendering. SwiftTerm's Metal path currently paints
        // a blank view on some GPUs (the buffer fills but nothing draws), which
        // made terminals appear empty. CG is reliable; revisit Metal later.
        try? setUseMetal(false)
    }
}
