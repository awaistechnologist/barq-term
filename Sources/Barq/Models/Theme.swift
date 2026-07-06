import Foundation
import SwiftTerm
import AppKit

struct BarqTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let isDark: Bool
    let background: String
    let foreground: String
    let cursor: String
    let selection: String
    let accent: String
    /// 16 ANSI colors as hex strings.
    let ansi: [String]

    static func hexToNSColor(_ hex: String) -> NSColor {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return .black }
        return NSColor(
            srgbRed: CGFloat((v >> 16) & 0xFF) / 255.0,
            green: CGFloat((v >> 8) & 0xFF) / 255.0,
            blue: CGFloat(v & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    static func hexToTermColor(_ hex: String) -> SwiftTerm.Color {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else {
            return SwiftTerm.Color(red: 0, green: 0, blue: 0)
        }
        // SwiftTerm colors are 16-bit per channel.
        let r = UInt16((v >> 16) & 0xFF) &* 257
        let g = UInt16((v >> 8) & 0xFF) &* 257
        let b = UInt16(v & 0xFF) &* 257
        return SwiftTerm.Color(red: r, green: g, blue: b)
    }

    var termColors: [SwiftTerm.Color] { ansi.map { Self.hexToTermColor($0) } }
    var backgroundColor: NSColor { Self.hexToNSColor(background) }
    var foregroundColor: NSColor { Self.hexToNSColor(foreground) }
    var cursorColor: NSColor { Self.hexToNSColor(cursor) }
    var accentColor: NSColor { Self.hexToNSColor(accent) }
}

enum Themes {
    static let catppuccinMocha = BarqTheme(
        id: "catppuccin-mocha", name: "Catppuccin Mocha", isDark: true,
        background: "#1e1e2e", foreground: "#cdd6f4", cursor: "#f5e0dc",
        selection: "#585b70", accent: "#89b4fa",
        ansi: ["#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
               "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8"]
    )

    static let catppuccinLatte = BarqTheme(
        id: "catppuccin-latte", name: "Catppuccin Latte", isDark: false,
        background: "#eff1f5", foreground: "#4c4f69", cursor: "#dc8a78",
        selection: "#acb0be", accent: "#1e66f5",
        ansi: ["#5c5f77", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#acb0be",
               "#6c6f85", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#bcc0cc"]
    )

    static let dracula = BarqTheme(
        id: "dracula", name: "Dracula", isDark: true,
        background: "#282a36", foreground: "#f8f8f2", cursor: "#f8f8f2",
        selection: "#44475a", accent: "#bd93f9",
        ansi: ["#21222c", "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
               "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5", "#d6acff", "#ff92df", "#a4ffff", "#ffffff"]
    )

    static let nord = BarqTheme(
        id: "nord", name: "Nord", isDark: true,
        background: "#2e3440", foreground: "#d8dee9", cursor: "#d8dee9",
        selection: "#434c5e", accent: "#88c0d0",
        ansi: ["#3b4252", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0",
               "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4"]
    )

    static let tokyoNight = BarqTheme(
        id: "tokyo-night", name: "Tokyo Night", isDark: true,
        background: "#1a1b26", foreground: "#c0caf5", cursor: "#c0caf5",
        selection: "#33467c", accent: "#7aa2f7",
        ansi: ["#15161e", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6",
               "#414868", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5"]
    )

    static let solarizedDark = BarqTheme(
        id: "solarized-dark", name: "Solarized Dark", isDark: true,
        background: "#002b36", foreground: "#839496", cursor: "#839496",
        selection: "#073642", accent: "#268bd2",
        ansi: ["#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
               "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"]
    )

    static let all: [BarqTheme] = [catppuccinMocha, catppuccinLatte, dracula, nord, tokyoNight, solarizedDark]

    static func theme(id: String) -> BarqTheme {
        all.first { $0.id == id } ?? catppuccinMocha
    }
}
