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
    /// Look for a new release once a day.
    var checkForUpdates = true
    /// The first-run "Get started" strip on Home was dismissed.
    var dismissedGetStarted = false
    /// Warn when agents' spend today passes this (USD); nil is off.
    var dailyBudgetUSD: Double?
    /// Also interrupt working agents at the daily budget.
    var pauseAgentsOverBudget = false
    /// Warn when a session's context use passes this percent; nil is off.
    var contextAlertPercent: Double?
    /// Terminal color themes imported from iTerm2 or Ghostty.
    var customPalettes: [CustomPalette] = []
    /// Shortcuts you changed, by command id (the rest keep their defaults).
    var keyBindings: [String: KeyBinding] = [:]
    /// Other Macs whose sessions show here too, reached with `ssh <address> tethera bridge`.
    var remoteHosts: [RemoteHost] = []
    /// The phone dashboard (Settings → Remote); off until turned on.
    var phoneEnabled = false
    var phoneReach: PhoneReach = .tailscale
    var phonePort = Int(PhoneServer.defaultPort)
    /// The phone's pairing token; a new one unpairs every phone.
    var phoneToken: String?
    /// ntfy push while you're away; the topic is random and the server can be your own.
    var pushEnabled = false
    var pushTopic: String?
    var pushServer: String?
    /// The team's GitHub repository (owner/name), when you've joined one.
    var teamRepository: String?
    /// Ghost text from your history at the prompt, and the ⌃Space list.
    var suggestCommands = true

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
        checkForUpdates = (try? c.decode(Bool.self, forKey: .checkForUpdates)) ?? d.checkForUpdates
        dismissedGetStarted = (try? c.decode(Bool.self, forKey: .dismissedGetStarted)) ?? d.dismissedGetStarted
        dailyBudgetUSD = try? c.decodeIfPresent(Double.self, forKey: .dailyBudgetUSD)
        pauseAgentsOverBudget = (try? c.decode(Bool.self, forKey: .pauseAgentsOverBudget)) ?? d.pauseAgentsOverBudget
        contextAlertPercent = try? c.decodeIfPresent(Double.self, forKey: .contextAlertPercent)
        customPalettes = (try? c.decode([CustomPalette].self, forKey: .customPalettes)) ?? d.customPalettes
        keyBindings = (try? c.decode([String: KeyBinding].self, forKey: .keyBindings)) ?? d.keyBindings
        remoteHosts = (try? c.decode([RemoteHost].self, forKey: .remoteHosts)) ?? d.remoteHosts
        phoneEnabled = (try? c.decode(Bool.self, forKey: .phoneEnabled)) ?? d.phoneEnabled
        phoneReach = (try? c.decode(PhoneReach.self, forKey: .phoneReach)) ?? d.phoneReach
        phonePort = (try? c.decode(Int.self, forKey: .phonePort)) ?? d.phonePort
        phoneToken = try? c.decodeIfPresent(String.self, forKey: .phoneToken)
        pushEnabled = (try? c.decode(Bool.self, forKey: .pushEnabled)) ?? d.pushEnabled
        pushTopic = try? c.decodeIfPresent(String.self, forKey: .pushTopic)
        pushServer = try? c.decodeIfPresent(String.self, forKey: .pushServer)
        teamRepository = try? c.decodeIfPresent(String.self, forKey: .teamRepository)
        suggestCommands = (try? c.decode(Bool.self, forKey: .suggestCommands)) ?? d.suggestCommands
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
        if let custom = value.customPalettes.first(where: { $0.id == value.terminalPalette }) { return custom.palette }
        return isDark ? .graphite : .paper
    }

    var terminalFont: NSFont {
        FontLoader.font(family: value.fontFamily, size: CGFloat(value.fontSize))
    }

    func adjustFontSize(by delta: Double) {
        value.fontSize = min(28, max(9, value.fontSize + delta))
    }
}
