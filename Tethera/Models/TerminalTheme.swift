import SwiftUI

struct TerminalTheme {
    var background: SwiftUI.Color
    var foreground: SwiftUI.Color
    var prompt: SwiftUI.Color
    var error: SwiftUI.Color
    var link: SwiftUI.Color
    var blockDivider: SwiftUI.Color
    var secondary: SwiftUI.Color
    var accent: SwiftUI.Color
    var fontSize: Double
    var fontFamily: String
    var lineSpacing: Double
    var padding: Double
    var cornerRadius: Double
    
    // Initialize from UserSettings
    init(from config: ThemeConfiguration) {
        self.background = config.backgroundColor.color
        self.foreground = config.textColor.color
        self.prompt = SwiftUI.Color(red: 0.4, green: 0.95, blue: 0.6)
        self.error = SwiftUI.Color(red: 0.95, green: 0.4, blue: 0.4)
        self.link = config.accentColor.color
        self.blockDivider = config.isDarkMode ? SwiftUI.Color.white.opacity(0.05) : SwiftUI.Color.black.opacity(0.05)
        self.secondary = config.secondaryColor.color
        self.accent = config.accentColor.color
        self.fontSize = config.fontSize
        self.fontFamily = config.fontFamily
        self.lineSpacing = config.lineSpacing
        self.padding = config.padding
        self.cornerRadius = config.cornerRadius
    }
    
    public static let defaultTheme = TerminalTheme(from: ThemeConfiguration())
}
