import AppKit
import SwiftUI

/// Chrome colors. Neutral greys and a single amber accent that only ever means
/// "this needs you", focus, or the cursor. No gradients, no glows.
struct Theme: Equatable {
    let isDark: Bool
    let bg: RGB
    let surface: RGB
    let raised: RGB
    let hairline: RGB
    let text: RGB
    let text2: RGB
    let text3: RGB
    let accent: RGB
    let success: RGB
    let danger: RGB

    static let graphite = Theme(
        isDark: true,
        bg: RGB(hex: "#0E0E0F"), surface: RGB(hex: "#141416"), raised: RGB(hex: "#1D1D20"),
        hairline: RGB(hex: "#26262A"), text: RGB(hex: "#E8E6E3"), text2: RGB(hex: "#9A9792"),
        text3: RGB(hex: "#66645F"), accent: RGB(hex: "#F5A524"), success: RGB(hex: "#4FB477"),
        danger: RGB(hex: "#E5484D"))

    static let paper = Theme(
        isDark: false,
        bg: RGB(hex: "#F7F6F3"), surface: RGB(hex: "#EFEDE8"), raised: RGB(hex: "#E6E3DC"),
        hairline: RGB(hex: "#DCD8D0"), text: RGB(hex: "#1A1A1A"), text2: RGB(hex: "#5E5B55"),
        text3: RGB(hex: "#8F8B84"), accent: RGB(hex: "#B86E00"), success: RGB(hex: "#2E7D4F"),
        danger: RGB(hex: "#C62828"))
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.graphite
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// Type scale: SF Pro for chrome, SF Mono for numbers that change (timers, counts).
enum TypeScale {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Small uppercase section labels.
    static let label = Font.system(size: 10, weight: .semibold)
}

/// Spacing and shape tokens.
enum Metrics {
    static let titlebarHeight: CGFloat = 38
    static let paneHeaderHeight: CGFloat = 30
    static let statusBarHeight: CGFloat = 24
    static let rowHeight: CGFloat = 38
    static let panelRadius: CGFloat = 6
    static let controlRadius: CGFloat = 4
    static let terminalPadding: CGFloat = 10
    static let inspectorWidth: CGFloat = 300
}
