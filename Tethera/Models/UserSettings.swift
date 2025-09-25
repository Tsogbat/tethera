import SwiftUI
import Foundation

// MARK: - Theme Configuration
struct ThemeConfiguration: Codable, Equatable {
    var isDarkMode: Bool = true
    var primaryColor: CodableColor = CodableColor(.blue)
    var secondaryColor: CodableColor = CodableColor(.gray)
    var backgroundColor: CodableColor = CodableColor(.black)
    var accentColor: CodableColor = CodableColor(.blue)
    var textColor: CodableColor = CodableColor(.white)
    var fontFamily: String = "JetBrains Mono"
    var fontSize: Double = 14.0
    var lineSpacing: Double = 1.2
    var padding: Double = 8.0
    var cornerRadius: Double = 8.0
    
    static let defaultLight = ThemeConfiguration(
        isDarkMode: false,
        primaryColor: CodableColor(.blue),
        secondaryColor: CodableColor(.gray),
        backgroundColor: CodableColor(.white),
        accentColor: CodableColor(.blue),
        textColor: CodableColor(.black)
    )
    
    static let defaultDark = ThemeConfiguration(
        isDarkMode: true,
        primaryColor: CodableColor(.blue),
        secondaryColor: CodableColor(.gray),
        backgroundColor: CodableColor(.black),
        accentColor: CodableColor(.blue),
        textColor: CodableColor(.white)
    )
}

// MARK: - Developer Settings
struct DeveloperSettings: Codable, Equatable {
    var autocompletionEnabled: Bool = true
    var showLineNumbers: Bool = true
    var enableCodeFolding: Bool = true
    var syntaxHighlighting: Bool = true
    var showInvisibleCharacters: Bool = false
    var enableVimMode: Bool = false
    var tabSize: Int = 4
    var autoIndent: Bool = true
    var wordWrap: Bool = false
    var showMinimap: Bool = false
}

// MARK: - Theme Preset Model
struct ThemePreset: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let configuration: ThemeConfiguration
}

// MARK: - Codable Color Wrapper
struct CodableColor: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
    
    init(_ color: SwiftUI.Color) {
        #if canImport(AppKit)
        let nsColor = NSColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.red = Double(r)
        self.green = Double(g)
        self.blue = Double(b)
        self.alpha = Double(a)
        #else
        // Fallback for other platforms
        self.red = 0.5
        self.green = 0.5
        self.blue = 0.5
        self.alpha = 1.0
        #endif
    }
    
    var color: SwiftUI.Color {
        SwiftUI.Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

// MARK: - User Settings Manager
@MainActor
class UserSettings: ObservableObject, @unchecked Sendable {
    @Published var themeConfiguration = ThemeConfiguration()
    @Published var developerSettings = DeveloperSettings()
    @Published var selectedThemeId: String? = nil
    
    
    private let userDefaults = UserDefaults.standard
    private let userSettingsKey = "TetheraUserSettings"
    
    init() {
        loadSettings()
    }
    
    // MARK: - Persistence
    func saveSettings() {
        // Save theme configuration
        if let themeData = try? JSONEncoder().encode(themeConfiguration) {
            userDefaults.set(themeData, forKey: "TetheraThemeConfiguration")
        }
        // Save selected theme id
        userDefaults.set(selectedThemeId, forKey: "TetheraSelectedThemeId")
        
        // Save developer settings
        if let devData = try? JSONEncoder().encode(developerSettings) {
            userDefaults.set(devData, forKey: "TetheraDeveloperSettings")
        }
        
        // Notify other components that settings have changed
        NotificationCenter.default.post(name: NSNotification.Name("SettingsChanged"), object: nil)
    }
    
    func loadSettings() {
        // Load theme configuration
        if let themeData = userDefaults.data(forKey: "TetheraThemeConfiguration"),
           let theme = try? JSONDecoder().decode(ThemeConfiguration.self, from: themeData) {
            themeConfiguration = theme
        }
        // Load selected theme id
        if let themeId = userDefaults.string(forKey: "TetheraSelectedThemeId") {
            selectedThemeId = themeId
        }
        
        // Load developer settings
        if let devData = userDefaults.data(forKey: "TetheraDeveloperSettings"),
           let dev = try? JSONDecoder().decode(DeveloperSettings.self, from: devData) {
            developerSettings = dev
        }
    }
    
    // MARK: - Theme Presets
    func applyLightTheme() {
        themeConfiguration = ThemeConfiguration.defaultLight
        selectedThemeId = "tethera-light"
        saveSettings()
    }
    
    func applyDarkTheme() {
        themeConfiguration = ThemeConfiguration.defaultDark
        selectedThemeId = "tethera-dark"
        saveSettings()
    }
    
    func applyPreset(_ preset: ThemePreset) {
        themeConfiguration = preset.configuration
        selectedThemeId = preset.id
        saveSettings()
    }
    
    func resetToDefaults() {
        themeConfiguration = ThemeConfiguration()
        developerSettings = DeveloperSettings()
        selectedThemeId = nil
        saveSettings()
    }
    
    // MARK: - Color Presets
    static let colorPresets: [(String, SwiftUI.Color)] = [
        ("Blue", .blue),
        ("Purple", .purple),
        ("Green", .green),
        ("Orange", .orange),
        ("Red", .red),
        ("Pink", .pink),
        ("Teal", .teal),
        ("Indigo", .indigo),
        ("Mint", .mint),
        ("Cyan", .cyan)
    ]
    
    static let fontOptions = [
        "JetBrains Mono",
        "SF Mono",
        "Menlo",
        "Monaco",
        "Courier New",
        "Source Code Pro",
        "Fira Code"
    ]
    
    // MARK: - Built-in Theme Presets
    static let presets: [ThemePreset] = [
        ThemePreset(id: "tethera-dark", name: "Tethera Dark", configuration: .defaultDark),
        ThemePreset(id: "tethera-light", name: "Tethera Light", configuration: .defaultLight),
        // Add your new themes here:
        ThemePreset(id: "solarized-dark", name: "Solarized Dark", configuration: ThemeConfiguration(
            isDarkMode: true,
            primaryColor: CodableColor(SwiftUI.Color(red: 0.027, green: 0.212, blue: 0.259)),
            secondaryColor: CodableColor(SwiftUI.Color(red: 0.345, green: 0.431, blue: 0.459)),
            backgroundColor: CodableColor(SwiftUI.Color(red: 0.000, green: 0.168, blue: 0.212)),
            accentColor: CodableColor(SwiftUI.Color(red: 0.149, green: 0.545, blue: 0.824)),
            textColor: CodableColor(SwiftUI.Color(red: 0.933, green: 0.910, blue: 0.835)),
            fontFamily: "JetBrains Mono",
            fontSize: 14.0,
            lineSpacing: 1.2,
            padding: 8.0
        )),
        ThemePreset(id: "dracula", name: "Dracula", configuration: ThemeConfiguration(
            isDarkMode: true,
            primaryColor: CodableColor(.purple),
            secondaryColor: CodableColor(SwiftUI.Color(red: 0.161, green: 0.157, blue: 0.216)),
            backgroundColor: CodableColor(SwiftUI.Color(red: 0.090, green: 0.086, blue: 0.125)),
            accentColor: CodableColor(SwiftUI.Color(red: 0.678, green: 0.498, blue: 0.659)),
            textColor: CodableColor(SwiftUI.Color(red: 0.937, green: 0.937, blue: 0.937)),
            fontFamily: "JetBrains Mono",
            fontSize: 14.0,
            lineSpacing: 1.2,
            padding: 8.0
        )),
        ThemePreset(id: "nord", name: "Nord", configuration: ThemeConfiguration(
            isDarkMode: true,
            primaryColor: CodableColor(SwiftUI.Color(red: 0.180, green: 0.204, blue: 0.251)), // Polar Night
            secondaryColor: CodableColor(SwiftUI.Color(red: 0.282, green: 0.310, blue: 0.361)), // Snow Storm contrast
            backgroundColor: CodableColor(SwiftUI.Color(red: 0.153, green: 0.169, blue: 0.204)),
            accentColor: CodableColor(SwiftUI.Color(red: 0.529, green: 0.745, blue: 0.831)), // Frost
            textColor: CodableColor(SwiftUI.Color(red: 0.925, green: 0.933, blue: 0.949)),
            fontFamily: "JetBrains Mono",
            fontSize: 14.0,
            lineSpacing: 1.2,
            padding: 8.0
        )),

        ThemePreset(id: "gruvbox-dark", name: "Gruvbox Dark", configuration: ThemeConfiguration(
            isDarkMode: true,
            primaryColor: CodableColor(SwiftUI.Color(red: 0.251, green: 0.212, blue: 0.165)), // Dark background
            secondaryColor: CodableColor(SwiftUI.Color(red: 0.400, green: 0.325, blue: 0.239)),
            backgroundColor: CodableColor(SwiftUI.Color(red: 0.157, green: 0.141, blue: 0.110)),
            accentColor: CodableColor(SwiftUI.Color(red: 0.800, green: 0.600, blue: 0.000)), // Yellow
            textColor: CodableColor(SwiftUI.Color(red: 0.933, green: 0.910, blue: 0.835)),
            fontFamily: "JetBrains Mono",
            fontSize: 14.0,
            lineSpacing: 1.2,
            padding: 8.0
        )),

        ThemePreset(id: "monokai", name: "Monokai", configuration: ThemeConfiguration(
            isDarkMode: true,
            primaryColor: CodableColor(SwiftUI.Color(red: 0.192, green: 0.204, blue: 0.169)), // Background
            secondaryColor: CodableColor(SwiftUI.Color(red: 0.275, green: 0.290, blue: 0.243)),
            backgroundColor: CodableColor(SwiftUI.Color(red: 0.118, green: 0.118, blue: 0.118)),
            accentColor: CodableColor(SwiftUI.Color(red: 0.980, green: 0.910, blue: 0.310)), // Yellow
            textColor: CodableColor(SwiftUI.Color(red: 0.933, green: 0.933, blue: 0.933)),
            fontFamily: "JetBrains Mono",
            fontSize: 14.0,
            lineSpacing: 1.2,
            padding: 8.0
        )),

        ThemePreset(id: "one-dark", name: "One Dark", configuration: ThemeConfiguration(
            isDarkMode: true,
            primaryColor: CodableColor(SwiftUI.Color(red: 0.173, green: 0.212, blue: 0.247)),
            secondaryColor: CodableColor(SwiftUI.Color(red: 0.259, green: 0.298, blue: 0.341)),
            backgroundColor: CodableColor(SwiftUI.Color(red: 0.153, green: 0.173, blue: 0.204)),
            accentColor: CodableColor(SwiftUI.Color(red: 0.600, green: 0.753, blue: 0.478)), // Green
            textColor: CodableColor(SwiftUI.Color(red: 0.898, green: 0.898, blue: 0.898)),
            fontFamily: "JetBrains Mono",
            fontSize: 14.0,
            lineSpacing: 1.2,
            padding: 8.0
        )),

        ThemePreset(id: "catppuccin-mocha", name: "Catppuccin Mocha", configuration: ThemeConfiguration(
            isDarkMode: true,
            primaryColor: CodableColor(SwiftUI.Color(red: 0.172, green: 0.145, blue: 0.200)),
            secondaryColor: CodableColor(SwiftUI.Color(red: 0.286, green: 0.251, blue: 0.353)),
            backgroundColor: CodableColor(SwiftUI.Color(red: 0.106, green: 0.086, blue: 0.133)),
            accentColor: CodableColor(SwiftUI.Color(red: 0.757, green: 0.510, blue: 0.922)), // Lavender
            textColor: CodableColor(SwiftUI.Color(red: 0.925, green: 0.925, blue: 0.949)),
            fontFamily: "JetBrains Mono",
            fontSize: 14.0,
            lineSpacing: 1.2,
            padding: 8.0
        ))
    ]
}
