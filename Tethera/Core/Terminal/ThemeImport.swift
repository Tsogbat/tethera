import AppKit
import Foundation

/// A terminal palette you imported, kept in preferences.
struct CustomPalette: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var palette: TerminalPalette
}

/// Reads iTerm2 color presets (`.itermcolors`) and Ghostty theme files into palettes.
enum ThemeImport {
    enum Failure: LocalizedError {
        case unreadable, incomplete(Int)
        var errorDescription: String? {
            switch self {
            case .unreadable: return "That file isn't an iTerm2 color preset or a Ghostty theme."
            case .incomplete(let count): return "The theme defines \(count) of the 16 ANSI colors; Tethera needs all 16."
            }
        }
    }

    static func load(_ url: URL) throws -> CustomPalette {
        let data = try Data(contentsOf: url)
        let name = url.deletingPathExtension().lastPathComponent
        let palette = url.pathExtension.lowercased() == "itermcolors" ? try iTerm(data) : try ghostty(String(decoding: data, as: UTF8.self))
        return CustomPalette(id: "custom-" + name.lowercased().replacingOccurrences(of: " ", with: "-"), name: name, palette: palette)
    }

    /// iTerm2: a plist of "Ansi 0 Color" … "Ansi 15 Color", "Foreground Color", "Background
    /// Color", each with Red/Green/Blue components from 0 to 1.
    static func iTerm(_ data: Data) throws -> TerminalPalette {
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw Failure.unreadable }
        func color(_ key: String) -> String? {
            guard let entry = plist[key] as? [String: Any] else { return nil }
            func component(_ name: String) -> UInt8 {
                UInt8(max(0, min(255, ((entry[name] as? NSNumber)?.doubleValue ?? 0) * 255 + 0.5)))
            }
            return RGB(component("Red Component"), component("Green Component"), component("Blue Component")).hex
        }
        let ansi = (0..<16).compactMap { color("Ansi \($0) Color") }
        guard ansi.count == 16 else { throw ansi.isEmpty ? Failure.unreadable : Failure.incomplete(ansi.count) }
        return TerminalPalette(ansi, foreground: color("Foreground Color") ?? ansi[7], background: color("Background Color") ?? ansi[0])
    }

    /// Ghostty: `palette = N=#rrggbb` lines plus `foreground` and `background`.
    static func ghostty(_ text: String) throws -> TerminalPalette {
        var ansi = [String?](repeating: nil, count: 16)
        var foreground: String?, background: String?
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            func hex(_ value: String) -> String { value.hasPrefix("#") ? value : "#" + value }
            switch parts[0] {
            case "palette":
                let entry = parts[1].split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if entry.count == 2, let index = Int(entry[0]), (0..<16).contains(index) { ansi[index] = hex(entry[1]) }
            case "foreground": foreground = hex(parts[1])
            case "background": background = hex(parts[1])
            default: break
            }
        }
        let found = ansi.compactMap { $0 }
        guard found.count == 16 else { throw found.isEmpty ? Failure.unreadable : Failure.incomplete(found.count) }
        return TerminalPalette(found, foreground: foreground ?? found[7], background: background ?? found[0])
    }

    /// Asks for a theme file and adds it; returns the new palette's id.
    @MainActor
    static func chooseAndImport() -> String? {
        let panel = NSOpenPanel()
        panel.message = "Choose an iTerm2 color preset (.itermcolors) or a Ghostty theme file."
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let custom = try load(url)
            let store = PreferencesStore.shared
            store.value.customPalettes.removeAll { $0.id == custom.id }
            store.value.customPalettes.append(custom)
            store.value.terminalPalette = custom.id
            return custom.id
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't import that theme"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return nil
        }
    }
}
