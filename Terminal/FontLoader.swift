import Foundation
import CoreText
import SwiftUI
import AppKit

class FontLoader {
    static let shared = FontLoader()
    
    private init() {}
    
    /// Load and register the JetBrains Mono font family
    func loadJetBrainsMono() {
        let fontNames = ["JetBrainsMono-Regular", "JetBrainsMono-Medium", "JetBrainsMono-Bold"]
        
        for fontName in fontNames {
            if let fontURL = Bundle.main.url(forResource: fontName, withExtension: "ttf", subdirectory: "Fonts") {
                loadFont(from: fontURL, name: fontName)
            } else {
                print("Warning: \(fontName).ttf not found in bundle")
            }
        }
    }
    
    /// Load a specific font from URL
    private func loadFont(from url: URL, name: String) {
        guard let fontDataProvider = CGDataProvider(url: url as CFURL) else {
            print("Warning: Could not create font data provider for \(name)")
            return
        }
        
        guard let font = CGFont(fontDataProvider) else {
            print("Warning: Could not create font from data provider for \(name)")
            return
        }
        
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterGraphicsFont(font, &error) {
            if let error = error?.takeRetainedValue() {
                print("Warning: Could not register font \(name): \(error)")
            }
        } else {
            print("Successfully registered font: \(name)")
        }
    }
    
    /// Check if a font is available
    func isFontAvailable(_ fontName: String) -> Bool {
        return NSFont(name: fontName, size: 16) != nil
    }
    
    /// Get a fallback font if JetBrains Mono is not available
    func getFallbackFont() -> Font {
        if isFontAvailable("JetBrainsMono-Regular") {
            return .custom("JetBrainsMono-Regular", size: 15)
        } else if isFontAvailable("JetBrainsMono-Medium") {
            return .custom("JetBrainsMono-Medium", size: 15)
        } else {
            return .system(.body, design: .monospaced)
        }
    }
}
