import Foundation
import CoreText
import AppKit

/// Registers the bundled JetBrains Mono faces for this process.
final class FontLoader {
    static let shared = FontLoader()
    private var registered = false

    private init() {}

    func registerBundledFonts() {
        guard !registered else { return }
        registered = true
        let names = ["JetBrainsMono-Regular", "JetBrainsMono-Medium", "JetBrainsMono-Bold"]
        for name in names {
            guard NSFont(name: name, size: 12) == nil else { continue }
            let url = Bundle.tethera.url(forResource: name, withExtension: "ttf")
                ?? Bundle.tethera.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
            guard let url else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    func isFontAvailable(_ fontName: String) -> Bool {
        NSFont(name: fontName, size: 12) != nil
    }
}
