import CoreText
import Foundation
import SwiftTerm

/// Draws Nerd Font icons (prompt glyphs from starship, powerlevel10k, lazygit…) from the bundled
/// Symbols Nerd Font when the terminal font lacks them. A patched font the user picks still wins.
final class SymbolFallback: TerminalGlyphFallbackProvider, @unchecked Sendable {
    static let shared = SymbolFallback()

    let generation: UInt64 = 1
    private let descriptor: CTFontDescriptor?
    private var fonts: [CGFloat: CTFont] = [:]
    private let lock = NSLock()

    private init() {
        let url = Bundle.tethera.url(forResource: "SymbolsNerdFontMono-Regular", withExtension: "ttf", subdirectory: "Symbols")
        let descriptors = url.flatMap { CTFontManagerCreateFontDescriptorsFromURL($0 as CFURL) as? [CTFontDescriptor] }
        descriptor = descriptors?.first
    }

    /// Nerd Fonts live in the Private Use Areas; Powerline separators stretch to fill their cell.
    func placementPolicy(for scalar: Unicode.Scalar) -> TerminalGlyphPlacementPolicy? {
        let value = scalar.value
        switch value {
        case 0xE0B0...0xE0BF, 0xE0D6, 0xE0D7:
            return TerminalGlyphPlacementPolicy(placement: .stretch)
        case 0xE000...0xF8FF, 0xF0000...0xFFFFD:
            return TerminalGlyphPlacementPolicy(placement: .icon)
        default:
            return nil
        }
    }

    func fallbackFont(forPointSize size: CGFloat) -> CTFont? {
        guard let descriptor else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let font = fonts[size] { return font }
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        fonts[size] = font
        return font
    }
}
