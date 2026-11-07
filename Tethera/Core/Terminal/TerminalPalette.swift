import SwiftUI
import AppKit

/// 8-bit sRGB color with a hex Codable form ("#RRGGBB").
struct RGB: Hashable, Codable {
    var r: UInt8
    var g: UInt8
    var b: UInt8

    init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r; self.g = g; self.b = b
    }

    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))).scanHexInt64(&value)
        self.init(UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF))
    }

    var hex: String { String(format: "#%02X%02X%02X", r, g, b) }

    init(from decoder: Decoder) throws {
        self.init(hex: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }

    var color: SwiftUI.Color { SwiftUI.Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }
    var nsColor: NSColor { NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1) }

    /// Relative luminance (0…1), used to pick readable foregrounds.
    var luminance: Double {
        func channel(_ c: UInt8) -> Double {
            let v = Double(c) / 255
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }
}

/// The 16 ANSI colors plus the default foreground/background used by the emulator
/// and by rendered block output.
struct TerminalPalette: Hashable, Codable {
    var ansi: [RGB]
    var foreground: RGB
    var background: RGB

    init(_ hexes: [String], foreground: String, background: String) {
        precondition(hexes.count == 16, "A terminal palette needs 16 ANSI colors")
        self.ansi = hexes.map(RGB.init(hex:))
        self.foreground = RGB(hex: foreground)
        self.background = RGB(hex: background)
    }

    var red: RGB { ansi[1] }
    var green: RGB { ansi[2] }
    var yellow: RGB { ansi[3] }
    var blue: RGB { ansi[4] }

    /// Resolves an xterm-256 index.
    func color(index: Int) -> RGB {
        if index < 16 { return ansi[max(0, index)] }
        if index < 232 {
            let i = index - 16
            let steps: [UInt8] = [0, 95, 135, 175, 215, 255]
            return RGB(steps[i / 36], steps[(i % 36) / 6], steps[i % 6])
        }
        let level = UInt8(clamping: 8 + (min(index, 255) - 232) * 10)
        return RGB(level, level, level)
    }

    // MARK: Presets

    /// Graphite: neutral greys, colors that read on near-black without glowing.
    static let graphite = TerminalPalette(
        ["#1A1A1D", "#E5484D", "#4FB477", "#F5A524", "#6E9BD8", "#B48EAD", "#5FB3B3", "#C9C7C3",
         "#4A4A50", "#FF6369", "#6BD18F", "#FFC24B", "#8DB4EE", "#CDA6C6", "#7FCECE", "#EDEBE8"],
        foreground: "#E8E6E3", background: "#0E0E0F")

    /// Paper: warm off-white with ink-dark colors that keep AA contrast.
    static let paper = TerminalPalette(
        ["#1A1A1A", "#B3261E", "#2E7D4F", "#9A5B00", "#2457A5", "#8A3D8F", "#0F7470", "#6B6964",
         "#55524D", "#D03A30", "#36925D", "#B86E00", "#3168C2", "#A04FA6", "#178A85", "#8F8B84"],
        foreground: "#1A1A1A", background: "#F7F6F3")

    /// Palettes offered in Settings. "auto" follows the appearance (Graphite or Paper).
    static let named: [(id: String, name: String, palette: TerminalPalette)] = [
        ("graphite", "Graphite", .graphite),
        ("paper", "Paper", .paper),
        ("dracula", "Dracula", .dracula),
        ("nord", "Nord", .nord),
        ("gruvbox", "Gruvbox", .gruvboxDark),
        ("monokai", "Monokai", .monokai),
        ("one-dark", "One Dark", .oneDark),
        ("solarized", "Solarized Dark", .solarizedDark),
        ("catppuccin", "Catppuccin Mocha", .catppuccinMocha),
    ]

    static let tetheraDark = TerminalPalette(
        ["#1C1F27", "#FF6B70", "#7EE0A1", "#F5C66B", "#6CA8FF", "#C792FF", "#5FD7E8", "#C9CDD6",
         "#5B6170", "#FF8C8F", "#9BF0B9", "#FFD88A", "#8EBDFF", "#D8ADFF", "#84E6F2", "#F4F5F8"],
        foreground: "#E4E6EE", background: "#0D0F14")

    static let tetheraLight = TerminalPalette(
        ["#1D2027", "#D2343F", "#1A8E50", "#A86A10", "#2F6FDE", "#8B3FCC", "#0B8296", "#8A8F99",
         "#5D636E", "#E04E57", "#22A660", "#C07F17", "#4A85EC", "#A05BDE", "#139AB0", "#C9CCD3"],
        foreground: "#1D2027", background: "#F6F6F8")

    static let solarizedDark = TerminalPalette(
        ["#073642", "#DC322F", "#859900", "#B58900", "#268BD2", "#D33682", "#2AA198", "#EEE8D5",
         "#586E75", "#CB4B16", "#93A1A1", "#839496", "#657B83", "#6C71C4", "#93A1A1", "#FDF6E3"],
        foreground: "#93A1A1", background: "#002B36")

    static let dracula = TerminalPalette(
        ["#21222C", "#FF5555", "#50FA7B", "#F1FA8C", "#BD93F9", "#FF79C6", "#8BE9FD", "#F8F8F2",
         "#6272A4", "#FF6E6E", "#69FF94", "#FFFFA5", "#D6ACFF", "#FF92DF", "#A4FFFF", "#FFFFFF"],
        foreground: "#F8F8F2", background: "#282A36")

    static let nord = TerminalPalette(
        ["#3B4252", "#BF616A", "#A3BE8C", "#EBCB8B", "#81A1C1", "#B48EAD", "#88C0D0", "#E5E9F0",
         "#4C566A", "#BF616A", "#A3BE8C", "#EBCB8B", "#81A1C1", "#B48EAD", "#8FBCBB", "#ECEFF4"],
        foreground: "#D8DEE9", background: "#2E3440")

    static let gruvboxDark = TerminalPalette(
        ["#282828", "#CC241D", "#98971A", "#D79921", "#458588", "#B16286", "#689D6A", "#A89984",
         "#928374", "#FB4934", "#B8BB26", "#FABD2F", "#83A598", "#D3869B", "#8EC07C", "#EBDBB2"],
        foreground: "#EBDBB2", background: "#282828")

    static let monokai = TerminalPalette(
        ["#272822", "#F92672", "#A6E22E", "#F4BF75", "#66D9EF", "#AE81FF", "#A1EFE4", "#F8F8F2",
         "#75715E", "#F92672", "#A6E22E", "#F4BF75", "#66D9EF", "#AE81FF", "#A1EFE4", "#F9F8F5"],
        foreground: "#F8F8F2", background: "#272822")

    static let oneDark = TerminalPalette(
        ["#282C34", "#E06C75", "#98C379", "#E5C07B", "#61AFEF", "#C678DD", "#56B6C2", "#ABB2BF",
         "#5C6370", "#E06C75", "#98C379", "#E5C07B", "#61AFEF", "#C678DD", "#56B6C2", "#FFFFFF"],
        foreground: "#ABB2BF", background: "#282C34")

    static let catppuccinMocha = TerminalPalette(
        ["#45475A", "#F38BA8", "#A6E3A1", "#F9E2AF", "#89B4FA", "#F5C2E7", "#94E2D5", "#BAC2DE",
         "#585B70", "#F38BA8", "#A6E3A1", "#F9E2AF", "#89B4FA", "#F5C2E7", "#94E2D5", "#A6ADC8"],
        foreground: "#CDD6F4", background: "#1E1E2E")
}
