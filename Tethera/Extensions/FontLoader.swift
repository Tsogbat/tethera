import Foundation
import CoreText
import SwiftUI
import AppKit

class FontLoader {
    static let shared = FontLoader()
    
    private init() {}
    
    /// Load and register the JetBrains Mono font family
    func loadJetBrainsMono() {
        let fontNames = [
            ("JetBrainsMono-Medium", "ttf"),
            ("JetBrainsMono-Bold", "ttf"),
            ("JetBrainsMono-Regular", "ttf")
        ]
        
        for fontTuple in fontNames {
            let fontName = fontTuple.0
            let fontExtension = fontTuple.1
            
            if let fontURL = Bundle.main.url(forResource: fontName, withExtension: fontExtension, subdirectory: "Fonts") {
                loadFont(from: fontURL, name: fontName)
            } else if let fontURL = Bundle.main.url(forResource: fontName, withExtension: fontExtension) {
                loadFont(from: fontURL, name: fontName)
            }
        }
    }
    
    /// Load a specific font from URL
    private func loadFont(from url: URL, name: String) {
        guard let fontDataProvider = CGDataProvider(url: url as CFURL) else { return }
        guard let font = CGFont(fontDataProvider) else { return }
        
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterGraphicsFont(font, &error)
    }
    
    /// Check if a font is available
    func isFontAvailable(_ fontName: String) -> Bool {
        return NSFont(name: fontName, size: 16) != nil
    }
    
    /// Get a fallback font if JetBrains Mono is not available
    func getFallbackFont() -> Font {
        if isFontAvailable("JetBrainsMono-Medium") {
            return .custom("JetBrainsMono-Medium", size: 15)
        } else if isFontAvailable("JetBrainsMono-Regular") {
            return .custom("JetBrainsMono-Regular", size: 15)
        } else if isFontAvailable("JetBrainsMono-Bold") {
            return .custom("JetBrainsMono-Bold", size: 15)
        } else {
            return .system(.body, design: .monospaced)
        }
    }
}
