import SwiftUI
import AppKit

/// Barq's design tokens. Spacing/radii scale + the electric "lightning" accent.
/// Surface colors are derived from the *active terminal theme* (see the
/// `BarqTheme` extension below) so the whole app reads as one designed object
/// that shifts with the theme — not a gray shell around a colored terminal.
enum BarqDesign {
    // Spacing scale
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24

    // Corner radii
    static let rChip: CGFloat = 8
    static let rCard: CGFloat = 12
    static let rOverlay: CGFloat = 18

    static let topBarHeight: CGFloat = 44
    /// Leading inset that keeps content clear of the traffic-light buttons.
    /// The three lights end ~68px from the window edge; this sits the wordmark
    /// just past them with a small breath (this is the *total* left inset).
    static let trafficLightInset: CGFloat = 72

    /// The signature electric accent. Slightly deeper on light themes so it
    /// stays legible on a bright background.
    static func accent(dark: Bool) -> Color {
        dark
            ? Color(.sRGB, red: 1.0, green: 0.78, blue: 0.22)   // #FFC738
            : Color(.sRGB, red: 0.87, green: 0.56, blue: 0.02)  // #DE8F05
    }
}

extension BarqTheme {
    private func components(_ c: NSColor) -> (Double, Double, Double) {
        let s = c.usingColorSpace(.sRGB) ?? c
        return (Double(s.redComponent), Double(s.greenComponent), Double(s.blueComponent))
    }

    /// Blend `backgroundColor` toward `foregroundColor` by `t` — makes elevated
    /// surfaces that work in both light and dark themes.
    private func elevate(_ t: Double) -> Color {
        let (br, bg, bb) = components(backgroundColor)
        let (fr, fg, fb) = components(foregroundColor)
        let r = br + (fr - br) * t
        let g = bg + (fg - bg) * t
        let b = bb + (fb - bb) * t
        return Color(.sRGB, red: r, green: g, blue: b)
    }

    /// The electric accent for this theme's light/dark mode.
    var electric: Color { BarqDesign.accent(dark: isDark) }

    /// The terminal's own background (also the "hero card" color).
    var chrome: Color { Color(nsColor: backgroundColor) }
    /// App chrome behind the terminal cards (sidebar, top bar, gutters).
    /// Clearly distinct from the terminal so panes read as floating cards.
    var elevated: Color { elevate(isDark ? 0.12 : 0.06) }
    /// A second, stronger elevation for controls on the chrome.
    var elevatedStrong: Color { elevate(isDark ? 0.18 : 0.10) }
    /// Hover state for rows/chips.
    var hoverFill: Color { Color(nsColor: foregroundColor).opacity(0.08) }
    /// Selected surface tinted with the accent.
    var selectedFill: Color { electric.opacity(isDark ? 0.16 : 0.14) }
    /// Very subtle separators — used sparingly instead of hard dividers.
    var hairline: Color { Color(nsColor: foregroundColor).opacity(0.08) }
    /// Primary / secondary text tuned to the theme foreground.
    var textPrimary: Color { Color(nsColor: foregroundColor) }
    var textSecondary: Color { Color(nsColor: foregroundColor).opacity(0.55) }
    var textTertiary: Color { Color(nsColor: foregroundColor).opacity(0.35) }
}

/// The Barq lightning glyph — a custom angular bolt (not an SF Symbol), drawn
/// in a normalized box so it scales crisply at any size.
struct BarqBolt: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: p(0.60, 0.04))
        path.addLine(to: p(0.28, 0.54))
        path.addLine(to: p(0.46, 0.54))
        path.addLine(to: p(0.38, 0.96))
        path.addLine(to: p(0.74, 0.42))
        path.addLine(to: p(0.55, 0.42))
        path.addLine(to: p(0.66, 0.04))
        path.closeSubpath()
        return path
    }
}

/// The Barq brand mark: a bolt in an electric badge + the wordmark.
struct BarqLogo: View {
    let theme: BarqTheme
    var badge: CGFloat = 22
    var wordmark: CGFloat = 15
    var showWordmark: Bool = true

    private var amberTop: Color { Color(.sRGB, red: 1.0, green: 0.83, blue: 0.35) }
    private var amberBottom: Color { Color(.sRGB, red: 0.98, green: 0.62, blue: 0.08) }

    var body: some View {
        HStack(spacing: badge * 0.34) {
            ZStack {
                RoundedRectangle(cornerRadius: badge * 0.30, style: .continuous)
                    .fill(LinearGradient(colors: [amberTop, amberBottom],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                BarqBolt()
                    .fill(Color.black.opacity(0.82))
                    .frame(width: badge * 0.5, height: badge * 0.66)
            }
            .frame(width: badge, height: badge)
            .shadow(color: amberBottom.opacity(0.45), radius: badge * 0.18, y: badge * 0.04)

            if showWordmark {
                Text("Barq")
                    .font(.system(size: wordmark, weight: .heavy, design: .rounded))
                    .tracking(-0.3)
                    .foregroundStyle(theme.textPrimary)
            }
        }
    }
}

/// A small keycap chip (e.g. ⌘T) for hints and the welcome screen.
struct Keycap: View {
    let text: String
    let theme: BarqTheme
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(theme.elevated)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(theme.hairline))
            )
    }
}

/// Primary action button styled with the electric accent.
struct AccentButtonStyle: ButtonStyle {
    let theme: BarqTheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.isDark ? Color.black.opacity(0.85) : Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: BarqDesign.rChip)
                    .fill(theme.electric.opacity(configuration.isPressed ? 0.8 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
