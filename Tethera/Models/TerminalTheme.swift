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
    
    public static let defaultTheme = TerminalTheme(
        background: SwiftUI.Color(red: 0.06, green: 0.07, blue: 0.10),
        foreground: SwiftUI.Color.white,
        prompt: SwiftUI.Color(red: 0.4, green: 0.95, blue: 0.6),
        error: SwiftUI.Color(red: 0.95, green: 0.4, blue: 0.4),
        link: SwiftUI.Color(red: 0.4, green: 0.7, blue: 0.95),
        blockDivider: SwiftUI.Color.white.opacity(0.05),
        secondary: SwiftUI.Color(red: 0.7, green: 0.7, blue: 0.7),
        accent: SwiftUI.Color(red: 0.4, green: 0.95, blue: 0.6)
    )
}
