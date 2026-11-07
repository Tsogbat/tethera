import AppKit
import SwiftTerm
import SwiftUI

/// User preferences, stored as one JSON value. Unknown or missing keys fall back to defaults,
/// so adding a setting never resets the others.
struct Preferences: Codable, Equatable {
    enum Appearance: String, Codable, CaseIterable, Identifiable {
        case system, dark, light
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    enum Cursor: String, Codable, CaseIterable, Identifiable {
        case bar, block, underline
        var id: String { rawValue }
        var label: String { rawValue.capitalized }

        func style(blink: Bool) -> CursorStyle {
            switch self {
            case .bar: return blink ? .blinkBar : .steadyBar
            case .block: return blink ? .blinkBlock : .steadyBlock
            case .underline: return blink ? .blinkUnderline : .steadyUnderline
            }
        }
    }

    var appearance: Appearance = .dark
    /// A `TerminalPalette.named` id, or "auto" to follow the appearance.
    var terminalPalette = "auto"
    var fontFamily = "Geist Mono"
    var fontSize: Double = 13
    var cursor: Cursor = .bar
    var cursorBlink = true
    var optionAsMeta = true
    var useMetal = true
    /// Shell for new sessions; the login shell when nil.
    var shell: String?
    /// Folder for new sessions when there's nothing to inherit from; home when nil.
    var startDirectory: String?
    var notifyWhenAgentsNeedYou = true
    var showInspector = false
    var sidebarWidth: Double = 236
    /// Open to Home instead of the last layout.
    var openHomeOnLaunch = false
    /// Music or Spotify's current track in the status bar.
    var showNowPlaying = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        appearance = (try? c.decode(Appearance.self, forKey: .appearance)) ?? d.appearance
        terminalPalette = (try? c.decode(String.self, forKey: .terminalPalette)) ?? d.terminalPalette
        fontFamily = (try? c.decode(String.self, forKey: .fontFamily)) ?? d.fontFamily
        fontSize = (try? c.decode(Double.self, forKey: .fontSize)) ?? d.fontSize
        cursor = (try? c.decode(Cursor.self, forKey: .cursor)) ?? d.cursor
        cursorBlink = (try? c.decode(Bool.self, forKey: .cursorBlink)) ?? d.cursorBlink
        optionAsMeta = (try? c.decode(Bool.self, forKey: .optionAsMeta)) ?? d.optionAsMeta
        useMetal = (try? c.decode(Bool.self, forKey: .useMetal)) ?? d.useMetal
        shell = try? c.decodeIfPresent(String.self, forKey: .shell)
        startDirectory = try? c.decodeIfPresent(String.self, forKey: .startDirectory)
        notifyWhenAgentsNeedYou = (try? c.decode(Bool.self, forKey: .notifyWhenAgentsNeedYou)) ?? d.notifyWhenAgentsNeedYou
        showInspector = (try? c.decode(Bool.self, forKey: .showInspector)) ?? d.showInspector
        sidebarWidth = (try? c.decode(Double.self, forKey: .sidebarWidth)) ?? d.sidebarWidth
        openHomeOnLaunch = (try? c.decode(Bool.self, forKey: .openHomeOnLaunch)) ?? d.openHomeOnLaunch
        showNowPlaying = (try? c.decode(Bool.self, forKey: .showNowPlaying)) ?? d.showNowPlaying
    }
}

@MainActor
final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()
    private static let key = "tethera.preferences.v4"

    @Published var value: Preferences {
        didSet { save() }
    }

    private init() {
        if let data = AppDefaults.store.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(Preferences.self, from: data) {
            value = decoded
        } else {
            value = Preferences()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(value) {
            AppDefaults.store.set(data, forKey: Self.key)
        }
    }

    /// Whether the chrome is dark right now (resolving "system").
    var isDark: Bool {
        switch value.appearance {
        case .dark: return true
        case .light: return false
        case .system: return NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) != .aqua
        }
    }

    var theme: Theme { isDark ? .graphite : .paper }

    var terminalPalette: TerminalPalette {
        if let named = TerminalPalette.named.first(where: { $0.id == value.terminalPalette }) { return named.palette }
        return isDark ? .graphite : .paper
    }

    var terminalFont: NSFont {
        FontLoader.font(family: value.fontFamily, size: CGFloat(value.fontSize))
    }

    func adjustFontSize(by delta: Double) {
        value.fontSize = min(28, max(9, value.fontSize + delta))
    }
}
