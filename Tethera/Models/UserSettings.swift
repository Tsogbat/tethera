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
        ThemePreset(id: "tethera-light", name: "Tethera Light", configuration: .defaultLight)
    ]
}
