import SwiftUI
import AppKit

/// Configures the hosting NSWindow for a seamless, edge-to-edge look:
/// transparent hidden title bar with full-size content, so Barq's own top bar
/// spans the whole width and the terminal reaches every edge.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }
    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        // Keep the standard traffic lights; they float over our top bar.
        window.standardWindowButton(.closeButton)?.superview?.needsLayout = true
    }
}

/// A transparent AppKit region that lets the user drag the window from empty
/// space in the top bar (controls placed above it still receive clicks).
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            // Double-click the title area to zoom, matching macOS convention.
            if event.clickCount == 2 { window?.performZoom(nil) }
            super.mouseDown(with: event)
        }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
