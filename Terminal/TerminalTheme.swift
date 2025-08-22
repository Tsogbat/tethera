import SwiftUI

struct TerminalTheme {
    var background: SwiftUI.Color
    var foreground: SwiftUI.Color
    var prompt: SwiftUI.Color
    var error: SwiftUI.Color
    var link: SwiftUI.Color
    var blockDivider: SwiftUI.Color
    
    public static let defaultTheme = TerminalTheme(
        background: SwiftUI.Color(red: 0.10, green: 0.12, blue: 0.16),
        foreground: SwiftUI.Color.white,
        prompt: SwiftUI.Color(red: 0.4, green: 0.95, blue: 0.6),
        error: SwiftUI.Color.red,
        link: SwiftUI.Color.blue,
        blockDivider: SwiftUI.Color.gray.opacity(0.18)
    )
}
