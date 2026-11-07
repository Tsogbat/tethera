import SwiftUI
import Foundation
import SwiftTerm

// MARK: - Theme Configuration

struct ThemeConfiguration: Codable, Equatable {
    var isDarkMode: Bool = true
    var primaryColor: CodableColor = CodableColor(hex: "#7E86FF")
    var secondaryColor: CodableColor = CodableColor(hex: "#8A8F99")
    var backgroundColor: CodableColor = CodableColor(hex: "#0D0F14")
    var accentColor: CodableColor = CodableColor(hex: "#8C93FF")
    var textColor: CodableColor = CodableColor(hex: "#E4E6EE")
    var fontFamily: String = "JetBrains Mono"
    var fontSize: Double = 13.0
    var lineSpacing: Double = 1.2
    var padding: Double = 8.0
    var cornerRadius: Double = 8.0
    var palette: TerminalPalette? = .tetheraDark

    init() {}

    init(isDarkMode: Bool, accent: String, palette: TerminalPalette, fontFamily: String = "JetBrains Mono", fontSize: Double = 13) {
        self.isDarkMode = isDarkMode
        self.accentColor = CodableColor(hex: accent)
        self.primaryColor = CodableColor(hex: accent)
        self.backgroundColor = CodableColor(rgb: palette.background)
        self.textColor = CodableColor(rgb: palette.foreground)
        self.secondaryColor = CodableColor(rgb: palette.ansi[8])
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.palette = palette
    }

    /// The ANSI palette, derived from the basic colors for themes saved before palettes existed.
    var effectivePalette: TerminalPalette {
        if let palette { return palette }
        var base = isDarkMode ? TerminalPalette.tetheraDark : TerminalPalette.tetheraLight
        base.background = backgroundColor.rgb
        base.foreground = textColor.rgb
        return base
    }

    // Older saved settings lack newer keys; decode each one leniently.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ThemeConfiguration()
        isDarkMode = (try? c.decodeIfPresent(Bool.self, forKey: .isDarkMode)) ?? d.isDarkMode
        primaryColor = (try? c.decodeIfPresent(CodableColor.self, forKey: .primaryColor)) ?? d.primaryColor
        secondaryColor = (try? c.decodeIfPresent(CodableColor.self, forKey: .secondaryColor)) ?? d.secondaryColor
        backgroundColor = (try? c.decodeIfPresent(CodableColor.self, forKey: .backgroundColor)) ?? d.backgroundColor
        accentColor = (try? c.decodeIfPresent(CodableColor.self, forKey: .accentColor)) ?? d.accentColor
        textColor = (try? c.decodeIfPresent(CodableColor.self, forKey: .textColor)) ?? d.textColor
        fontFamily = (try? c.decodeIfPresent(String.self, forKey: .fontFamily)) ?? d.fontFamily
        fontSize = (try? c.decodeIfPresent(Double.self, forKey: .fontSize)) ?? d.fontSize
        lineSpacing = (try? c.decodeIfPresent(Double.self, forKey: .lineSpacing)) ?? d.lineSpacing
        padding = (try? c.decodeIfPresent(Double.self, forKey: .padding)) ?? d.padding
        cornerRadius = (try? c.decodeIfPresent(Double.self, forKey: .cornerRadius)) ?? d.cornerRadius
        palette = try? c.decodeIfPresent(TerminalPalette.self, forKey: .palette)
    }

    static let defaultDark = ThemeConfiguration(isDarkMode: true, accent: "#8C93FF", palette: .tetheraDark)
    static let defaultLight = ThemeConfiguration(isDarkMode: false, accent: "#5A5FE0", palette: .tetheraLight)
}

// MARK: - Terminal Preferences

enum CursorShape: String, Codable, CaseIterable, Identifiable {
    case bar, block, underline
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    func swiftTermStyle(blink: Bool) -> CursorStyle {
        switch self {
        case .bar: return blink ? .blinkBar : .steadyBar
        case .block: return blink ? .blinkBlock : .steadyBlock
        case .underline: return blink ? .blinkUnderline : .steadyUnderline
        }
    }
}

struct TerminalPreferences: Codable, Equatable {
    var cursorShape: CursorShape = .bar
    var cursorBlink = true
    var optionAsMeta = true
    var scrollbackLines = 10_000
    var collapseThreshold = 300
    var windowOpacity = 0.9
    var shellPath = ""
    var autocompletion = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TerminalPreferences()
        cursorShape = (try? c.decodeIfPresent(CursorShape.self, forKey: .cursorShape)) ?? d.cursorShape
        cursorBlink = (try? c.decodeIfPresent(Bool.self, forKey: .cursorBlink)) ?? d.cursorBlink
        optionAsMeta = (try? c.decodeIfPresent(Bool.self, forKey: .optionAsMeta)) ?? d.optionAsMeta
        scrollbackLines = (try? c.decodeIfPresent(Int.self, forKey: .scrollbackLines)) ?? d.scrollbackLines
        collapseThreshold = (try? c.decodeIfPresent(Int.self, forKey: .collapseThreshold)) ?? d.collapseThreshold
        windowOpacity = (try? c.decodeIfPresent(Double.self, forKey: .windowOpacity)) ?? d.windowOpacity
        shellPath = (try? c.decodeIfPresent(String.self, forKey: .shellPath)) ?? d.shellPath
        autocompletion = (try? c.decodeIfPresent(Bool.self, forKey: .autocompletion)) ?? d.autocompletion
    }

    var resolvedShell: String {
        let trimmed = shellPath.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, ShellEnvironment.isSupported(trimmed), FileManager.default.isExecutableFile(atPath: trimmed) {
            return trimmed
        }
        return ShellEnvironment.loginShell
    }
}

// MARK: - AI Settings

struct ProviderModels: Codable, Equatable {
    /// Used for quick tasks: command generation and fix suggestions.
    var fast = ""
    /// Used for chat answers and explanations.
    var chat = ""
}

struct AISettings: Codable, Equatable {
    var isEnabled = true
    var provider: AgentCLI = .opencode
    var models: [String: ProviderModels] = [:]
    var autoFixOnFailure = true
    var includeOutputContext = true
    var contextBlockCount = 4
    var warnOnDestructiveOps = true
    var destructiveCommands: [String] = ["rm", "sudo", "rmdir", "kill", "killall", "dd", "mkfs", "shutdown", "reboot", "chmod", "chown"]

    init() {}

    enum Role { case fast, chat }

    func model(for provider: AgentCLI, role: Role) -> String? {
        let configured = models[provider.rawValue]
        let value = role == .fast ? configured?.fast : configured?.chat
        if let value, !value.trimmingCharacters(in: .whitespaces).isEmpty {
            return value.trimmingCharacters(in: .whitespaces)
        }
        return role == .fast ? provider.defaultFastModel : provider.defaultChatModel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AISettings()
        isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? d.isEnabled
        provider = (try? c.decodeIfPresent(AgentCLI.self, forKey: .provider)) ?? d.provider
        models = (try? c.decodeIfPresent([String: ProviderModels].self, forKey: .models)) ?? d.models
        autoFixOnFailure = (try? c.decodeIfPresent(Bool.self, forKey: .autoFixOnFailure)) ?? d.autoFixOnFailure
        includeOutputContext = (try? c.decodeIfPresent(Bool.self, forKey: .includeOutputContext)) ?? d.includeOutputContext
        contextBlockCount = (try? c.decodeIfPresent(Int.self, forKey: .contextBlockCount)) ?? d.contextBlockCount
        warnOnDestructiveOps = (try? c.decodeIfPresent(Bool.self, forKey: .warnOnDestructiveOps)) ?? d.warnOnDestructiveOps
        destructiveCommands = (try? c.decodeIfPresent([String].self, forKey: .destructiveCommands)) ?? d.destructiveCommands
    }
}

// MARK: - Theme Preset

struct ThemePreset: Identifiable, Equatable {
    let id: String
    let name: String
    let configuration: ThemeConfiguration
}

// MARK: - Codable Color

struct CodableColor: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(_ color: SwiftUI.Color) {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.red = Double(nsColor.redComponent)
        self.green = Double(nsColor.greenComponent)
        self.blue = Double(nsColor.blueComponent)
        self.alpha = Double(nsColor.alphaComponent)
    }

    init(hex: String) {
        self.init(rgb: RGB(hex: hex))
    }

    init(rgb: RGB) {
        self.red = Double(rgb.r) / 255
        self.green = Double(rgb.g) / 255
        self.blue = Double(rgb.b) / 255
        self.alpha = 1
    }

    var color: SwiftUI.Color {
        SwiftUI.Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var rgb: RGB {
        RGB(UInt8(clamping: Int((red * 255).rounded())), UInt8(clamping: Int((green * 255).rounded())), UInt8(clamping: Int((blue * 255).rounded())))
    }
}

// MARK: - User Settings

@MainActor
final class UserSettings: ObservableObject {
    static let shared = UserSettings()

    @Published var themeConfiguration = ThemeConfiguration() {
        didSet { if themeConfiguration != oldValue { theme = DesignTheme(themeConfiguration); persist() } }
    }
    @Published var terminal = TerminalPreferences() {
        didSet { if terminal != oldValue { persist() } }
    }
    @Published var aiSettings = AISettings() {
        didSet { if aiSettings != oldValue { persist() } }
    }
    @Published var selectedThemeId: String? = "tethera-dark" {
        didSet { if selectedThemeId != oldValue { persist() } }
    }
    /// Semantic colors derived from the active theme.
    @Published private(set) var theme = DesignTheme(ThemeConfiguration())

    private let defaults = UserDefaults.standard
    private var isLoading = false

    private enum Keys {
        static let theme = "TetheraThemeConfiguration"
        static let themeId = "TetheraSelectedThemeId"
        static let terminal = "TetheraTerminalPreferences"
        static let ai = "TetheraAISettings.v2"
    }

    init() {
        load()
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: Keys.theme), let value = try? decoder.decode(ThemeConfiguration.self, from: data) {
            themeConfiguration = value
        } else {
            themeConfiguration = .defaultDark
        }
        if let id = defaults.string(forKey: Keys.themeId) {
            selectedThemeId = id
        }
        // Saved themes from before ANSI palettes existed: pick up the preset's palette.
        if themeConfiguration.palette == nil, let id = selectedThemeId, let preset = Self.presets.first(where: { $0.id == id }) {
            themeConfiguration.palette = preset.configuration.palette
        }
        if let data = defaults.data(forKey: Keys.terminal), let value = try? decoder.decode(TerminalPreferences.self, from: data) {
            terminal = value
        }
        if let data = defaults.data(forKey: Keys.ai), let value = try? decoder.decode(AISettings.self, from: data) {
            aiSettings = value
        }
        theme = DesignTheme(themeConfiguration)
    }

    private func persist() {
        guard !isLoading else { return }
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(themeConfiguration) { defaults.set(data, forKey: Keys.theme) }
        defaults.set(selectedThemeId, forKey: Keys.themeId)
        if let data = try? encoder.encode(terminal) { defaults.set(data, forKey: Keys.terminal) }
        if let data = try? encoder.encode(aiSettings) { defaults.set(data, forKey: Keys.ai) }
    }

    func applyPreset(_ preset: ThemePreset) {
        var configuration = preset.configuration
        configuration.fontFamily = themeConfiguration.fontFamily
        configuration.fontSize = themeConfiguration.fontSize
        themeConfiguration = configuration
        selectedThemeId = preset.id
    }

    func adjustFontSize(by delta: Double) {
        themeConfiguration.fontSize = min(28, max(9, themeConfiguration.fontSize + delta))
    }

    func resetFontSize() {
        themeConfiguration.fontSize = 13
    }

    // MARK: Options

    static let fontOptions = [
        "JetBrains Mono",
        "SF Mono",
        "Menlo",
        "Monaco",
        "Source Code Pro",
        "Fira Code"
    ]

    static let presets: [ThemePreset] = [
        ThemePreset(id: "tethera-dark", name: "Tethera Dark", configuration: .defaultDark),
        ThemePreset(id: "tethera-light", name: "Tethera Light", configuration: .defaultLight),
        ThemePreset(id: "catppuccin-mocha", name: "Catppuccin", configuration: ThemeConfiguration(isDarkMode: true, accent: "#CBA6F7", palette: .catppuccinMocha)),
        ThemePreset(id: "dracula", name: "Dracula", configuration: ThemeConfiguration(isDarkMode: true, accent: "#BD93F9", palette: .dracula)),
        ThemePreset(id: "nord", name: "Nord", configuration: ThemeConfiguration(isDarkMode: true, accent: "#88C0D0", palette: .nord)),
        ThemePreset(id: "one-dark", name: "One Dark", configuration: ThemeConfiguration(isDarkMode: true, accent: "#61AFEF", palette: .oneDark)),
        ThemePreset(id: "solarized-dark", name: "Solarized", configuration: ThemeConfiguration(isDarkMode: true, accent: "#268BD2", palette: .solarizedDark)),
        ThemePreset(id: "gruvbox-dark", name: "Gruvbox", configuration: ThemeConfiguration(isDarkMode: true, accent: "#FABD2F", palette: .gruvboxDark)),
        ThemePreset(id: "monokai", name: "Monokai", configuration: ThemeConfiguration(isDarkMode: true, accent: "#A6E22E", palette: .monokai)),
    ]
}
