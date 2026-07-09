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
        // Disable automatic titlebar dragging entirely — otherwise dragging a
        // tab (which sits in the titlebar band) moves the window instead of
        // starting the tab drag. We re-add explicit dragging in WindowDragArea.
        window.isMovable = false
        window.backgroundColor = .clear
        // Keep the standard traffic lights; they float over our top bar.
        window.standardWindowButton(.closeButton)?.superview?.needsLayout = true
    }
}

/// A transparent AppKit region that lets the user drag the window from empty
/// space in the top bar (controls placed above it still receive clicks).
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        // The window has isMovable = false (so tabs don't drag it); we move it
        // explicitly here via performDrag from the empty top-bar region.
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)   // double-click title area to zoom
            } else {
                window?.performDrag(with: event)
            }
        }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
