import AppKit
import CoreText

/// Registers the bundled monospace faces (Geist Mono, IBM Plex Mono, JetBrains Mono) for this process.
enum FontLoader {
    /// Families offered in Settings, bundled first; any installed monospace font also works.
    static let bundledFamilies = ["Geist Mono", "IBM Plex Mono", "JetBrains Mono"]
    private static var registered = false

    static func registerBundledFonts() {
        guard !registered else { return }
        registered = true
        let urls = (Bundle.tethera.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.tethera.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Every installed fixed-pitch family, for the font picker.
    static var monospacedFamilies: [String] {
        let manager = NSFontManager.shared
        let fixed = manager.availableFontFamilies.filter { family in
            guard let font = manager.font(withFamily: family, traits: [], weight: 5, size: 12) else { return false }
            return font.isFixedPitch || family.localizedCaseInsensitiveContains("mono")
        }
        return Array(Set(fixed + bundledFamilies + ["SF Mono"])).sorted()
    }

    /// A font for a family name; SF Mono and unknown families fall back to the system monospace.
    /// Ligatures and contextual alternates are off: a terminal draws exactly the characters
    /// it was sent, one per cell (`->` stays two characters, `--` doesn't shift).
    static func font(family: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        var font = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        if family != "SF Mono", let named = NSFontManager.shared.font(withFamily: family, traits: [], weight: weight == .regular ? 5 : 7, size: size) {
            font = named
        }
        let features: [[NSFontDescriptor.FeatureKey: Int]] = [
            [.typeIdentifier: kLigaturesType, .selectorIdentifier: kCommonLigaturesOffSelector],
            [.typeIdentifier: kLigaturesType, .selectorIdentifier: kRareLigaturesOffSelector],
            [.typeIdentifier: kContextualAlternatesType, .selectorIdentifier: kContextualAlternatesOffSelector],
        ]
        let descriptor = font.fontDescriptor.addingAttributes([.featureSettings: features])
        return NSFont(descriptor: descriptor, size: size) ?? font
    }
}
