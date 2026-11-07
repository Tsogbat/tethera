import Foundation
import SwiftTerm

/// Serializes a terminal's state as VT sequences, so a fresh emulator that plays them back shows
/// the same screen, scrollback, cursor and input modes. Sent to a client when it attaches.
enum VTSnapshot {
    struct Modes {
        var cursorVisible = true
        var focusReporting = false
        var sgrMouse = false
        var urxvtMouse = false
        var sgrPixelMouse = false
    }

    static func capture(_ terminal: Terminal, title: String, cursorStyle: CursorStyle?, modes: Modes) -> Data {
        var out = Output()
        // Leave any alternate screen, soft-reset, clear screen and scrollback.
        out.append("\u{1b}[?1049l\u{1b}[!p\u{1b}[0m\u{1b}[r\u{1b}[H\u{1b}[2J\u{1b}[3J")

        if terminal.isCurrentBufferAlternate {
            // SwiftTerm doesn't expose the normal buffer's cells while the alternate one is active,
            // so the history behind a full-screen program comes back as plain text.
            let normal = String(decoding: terminal.getBufferAsData(kind: .normal), as: UTF8.self)
            var lines = normal.components(separatedBy: "\n")
            while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
            out.append(lines.joined(separator: "\r\n"))
            out.append("\u{1b}[?1049h\u{1b}[H\u{1b}[2J")
            for row in 0..<terminal.rows {
                guard let line = terminal.getLine(row: row) else { continue }
                out.append("\u{1b}[\(row + 1);1H")
                out.appendCells(of: line, count: line.getTrimmedLength())
            }
        } else {
            var lines: [BufferLine] = []
            if let first = firstLine(terminal) {
                var row = first
                while let line = terminal.getScrollInvariantLine(row: row) {
                    lines.append(line)
                    row += 1
                }
            }
            for (index, line) in lines.enumerated() {
                let continues = index + 1 < lines.count && lines[index + 1].isWrapped
                // A line that wraps onto the next must fill the width so the emulator wraps too.
                out.appendCells(of: line, count: continues ? min(line.count, terminal.cols) : line.getTrimmedLength())
                if index + 1 < lines.count && !continues {
                    out.append("\u{1b}[0m\r\n")
                    out.resetAttribute()
                }
            }
        }

        let buffer = terminal.buffer
        if buffer.scrollTop != 0 || buffer.scrollBottom != terminal.rows - 1 {
            out.append("\u{1b}[\(buffer.scrollTop + 1);\(buffer.scrollBottom + 1)r")
        }
        out.append("\u{1b}[\(buffer.y + 1);\(min(buffer.x, terminal.cols - 1) + 1)H")
        out.resetAttribute()
        out.append("\u{1b}[0m")
        out.appendAttribute(terminal.currentAttribute)

        if terminal.applicationCursor { out.append("\u{1b}[?1h") }
        if terminal.bracketedPasteMode { out.append("\u{1b}[?2004h") }
        switch terminal.mouseMode {
        case .off: break
        case .x10: out.append("\u{1b}[?9h")
        case .vt200: out.append("\u{1b}[?1000h")
        case .buttonEventTracking: out.append("\u{1b}[?1002h")
        case .anyEvent: out.append("\u{1b}[?1003h")
        @unknown default: break
        }
        if modes.sgrMouse { out.append("\u{1b}[?1006h") }
        if modes.urxvtMouse { out.append("\u{1b}[?1015h") }
        if modes.sgrPixelMouse { out.append("\u{1b}[?1016h") }
        if modes.focusReporting { out.append("\u{1b}[?1004h") }
        let kitty = terminal.keyboardEnhancementFlags.rawValue
        if kitty != 0 { out.append("\u{1b}[=\(kitty);1u") }
        if let cursorStyle { out.append("\u{1b}[\(decscusr(cursorStyle)) q") }
        if !modes.cursorVisible { out.append("\u{1b}[?25l") }
        if !title.isEmpty { out.append("\u{1b}]2;\(title)\u{07}") }
        return Data(out.bytes)
    }

    private static func decscusr(_ style: CursorStyle) -> Int {
        switch style {
        case .blinkBlock: return 1
        case .steadyBlock: return 2
        case .blinkUnderline: return 3
        case .steadyUnderline: return 4
        case .blinkBar: return 5
        case .steadyBar: return 6
        @unknown default: return 0
        }
    }

    /// SwiftTerm hides the buffer's top offset, so find the first addressable row: step by a
    /// screenful (the window is always at least that tall), then bisect.
    static func firstLine(_ terminal: Terminal) -> Int? {
        let step = max(1, terminal.rows)
        var probe = 0
        var attempts = 0
        while terminal.getScrollInvariantLine(row: probe) == nil {
            probe += step
            attempts += 1
            if attempts > 5_000_000 { return nil }
        }
        var low = max(0, probe - step + 1)
        var high = probe
        while low < high {
            let mid = (low + high) / 2
            if terminal.getScrollInvariantLine(row: mid) != nil { high = mid } else { low = mid + 1 }
        }
        return low
    }

    /// Accumulates bytes, emitting SGR only when the attribute changes.
    private struct Output {
        var bytes: [UInt8] = []
        private var current: Attribute?

        mutating func append(_ string: String) {
            bytes.append(contentsOf: string.utf8)
        }

        mutating func resetAttribute() {
            current = nil
        }

        mutating func appendCells(of line: BufferLine, count: Int) {
            guard count > 0 else { return }
            for col in 0..<min(count, line.count) {
                let cell = line[col]
                if cell.width == 0 { continue } // trailing half of a wide glyph
                let attribute = cell.attribute
                if current != attribute {
                    append("\u{1b}[0m")
                    appendAttribute(attribute)
                    current = attribute
                }
                let character = cell.getCharacter()
                if character == "\u{0}" { bytes.append(0x20) } else { append(String(character)) }
            }
        }

        mutating func appendAttribute(_ attribute: Attribute) {
            var codes: [String] = []
            let style = attribute.style
            if style.contains(.bold) { codes.append("1") }
            if style.contains(.dim) { codes.append("2") }
            if style.contains(.italic) { codes.append("3") }
            if style.contains(.underline) { codes.append("4") }
            if style.contains(.blink) { codes.append("5") }
            if style.contains(.inverse) { codes.append("7") }
            if style.contains(.invisible) { codes.append("8") }
            if style.contains(.crossedOut) { codes.append("9") }
            codes.append(contentsOf: Self.color(attribute.fg, foreground: true))
            codes.append(contentsOf: Self.color(attribute.bg, foreground: false))
            guard !codes.isEmpty else { return }
            append("\u{1b}[\(codes.joined(separator: ";"))m")
        }

        private static func color(_ color: Attribute.Color, foreground: Bool) -> [String] {
            switch color {
            case .ansi256(let code):
                if code < 8 { return ["\((foreground ? 30 : 40) + Int(code))"] }
                if code < 16 { return ["\((foreground ? 90 : 100) + Int(code) - 8)"] }
                return [foreground ? "38" : "48", "5", "\(code)"]
            case .trueColor(let r, let g, let b):
                return [foreground ? "38" : "48", "2", "\(r)", "\(g)", "\(b)"]
            default:
                return []
            }
        }
    }
}
