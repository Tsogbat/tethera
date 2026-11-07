import SwiftUI
import SwiftTerm

/// A color as the terminal reported it, resolved against a palette at render time
/// so finished blocks follow theme changes.
enum TermColor: Hashable {
    case `default`
    case indexed(UInt8)
    case rgb(UInt8, UInt8, UInt8)
}

struct CellStyle: Hashable {
    struct Flags: OptionSet, Hashable {
        let rawValue: UInt8
        static let bold = Flags(rawValue: 1 << 0)
        static let italic = Flags(rawValue: 1 << 1)
        static let underline = Flags(rawValue: 1 << 2)
        static let inverse = Flags(rawValue: 1 << 3)
        static let dim = Flags(rawValue: 1 << 4)
        static let strikethrough = Flags(rawValue: 1 << 5)
        static let invisible = Flags(rawValue: 1 << 6)
    }

    var foreground: TermColor = .default
    var background: TermColor = .default
    var flags: Flags = []

    static let plain = CellStyle()
}

struct StyledRun: Hashable {
    var text: String
    var style: CellStyle
}

/// Terminal output captured as styled lines.
struct StyledText: Hashable {
    var lines: [[StyledRun]]
    /// Lines dropped from the top because the output exceeded the capture limit.
    var truncatedLineCount: Int = 0

    static let empty = StyledText(lines: [])

    var isEmpty: Bool { lines.isEmpty }
    var lineCount: Int { lines.count }

    var plainText: String {
        lines.map { $0.map(\.text).joined() }.joined(separator: "\n")
    }

    /// Plain text without styling (used for system and fallback output).
    init(plain: String) {
        self.lines = plain.components(separatedBy: "\n").map { [StyledRun(text: $0, style: .plain)] }
    }

    init(lines: [[StyledRun]], truncatedLineCount: Int = 0) {
        self.lines = lines
        self.truncatedLineCount = truncatedLineCount
    }

    func attributedString(palette: TerminalPalette, lineRange: Range<Int>? = nil) -> AttributedString {
        let range = lineRange ?? 0..<lines.count
        var result = AttributedString()
        for index in range where index < lines.count {
            for run in lines[index] where !run.text.isEmpty {
                var piece = AttributedString(run.text)
                apply(run.style, to: &piece, palette: palette)
                result.append(piece)
            }
            if index < range.upperBound - 1 {
                result.append(AttributedString("\n"))
            }
        }
        return result
    }

    private func apply(_ style: CellStyle, to piece: inout AttributedString, palette: TerminalPalette) {
        guard style != .plain else { return }
        var fg = resolve(style.foreground, palette: palette, isForeground: true)
        var bg = resolve(style.background, palette: palette, isForeground: false)
        if style.flags.contains(.inverse) {
            let swappedFg = bg ?? palette.background
            bg = fg ?? palette.foreground
            fg = swappedFg
        }
        if style.flags.contains(.bold), case .indexed(let i) = style.foreground, i < 8 {
            fg = palette.ansi[Int(i) + 8] // classic "bold is bright"
        }
        if let fg {
            piece.foregroundColor = style.flags.contains(.dim) ? fg.color.opacity(0.6) : fg.color
        } else if style.flags.contains(.dim) {
            piece.foregroundColor = palette.foreground.color.opacity(0.6)
        }
        if let bg {
            piece.backgroundColor = bg.color
        }
        var intent: InlinePresentationIntent = []
        if style.flags.contains(.bold) { intent.insert(.stronglyEmphasized) }
        if style.flags.contains(.italic) { intent.insert(.emphasized) }
        if !intent.isEmpty { piece.inlinePresentationIntent = intent }
        if style.flags.contains(.underline) { piece.underlineStyle = .single }
        if style.flags.contains(.strikethrough) { piece.strikethroughStyle = .single }
        if style.flags.contains(.invisible) { piece.foregroundColor = .clear }
    }

    private func resolve(_ color: TermColor, palette: TerminalPalette, isForeground: Bool) -> RGB? {
        switch color {
        case .default: return nil
        case .indexed(let i): return palette.color(index: Int(i))
        case .rgb(let r, let g, let b): return RGB(r, g, b)
        }
    }
}

// MARK: - Capture from SwiftTerm

extension StyledText {
    /// Captures the active buffer (scrollback + screen), trimming blank edges.
    static func capture(from terminal: Terminal, maxLines: Int) -> StyledText {
        guard let first = firstScrollInvariantRow(terminal) else { return .empty }
        var bufferLines: [BufferLine] = []
        var row = first
        while let line = terminal.getScrollInvariantLine(row: row) {
            bufferLines.append(line)
            row += 1
        }
        while let last = bufferLines.last, last.getTrimmedLength() == 0 { bufferLines.removeLast() }
        while let firstLine = bufferLines.first, firstLine.getTrimmedLength() == 0 { bufferLines.removeFirst() }

        var truncated = 0
        if bufferLines.count > maxLines {
            truncated = bufferLines.count - maxLines
            bufferLines.removeFirst(truncated)
        }
        return StyledText(lines: bufferLines.map(runs(for:)), truncatedLineCount: truncated)
    }

    /// Number of screen rows currently holding content (used to size live blocks).
    static func usedRows(in terminal: Terminal) -> Int {
        if terminal.isCurrentBufferAlternate || terminal.buffer.yDisp > 0 {
            return terminal.rows
        }
        var last = 0
        for row in stride(from: terminal.rows - 1, through: 0, by: -1) {
            if let line = terminal.getLine(row: row), line.getTrimmedLength() > 0 {
                last = row + 1
                break
            }
        }
        let cursorRow = terminal.buffer.y + 1
        return max(1, max(last, cursorRow))
    }

    private static func runs(for line: BufferLine) -> [StyledRun] {
        let length = line.getTrimmedLength()
        var runs: [StyledRun] = []
        var currentStyle = CellStyle.plain
        var currentText = ""
        for col in 0..<length {
            let cell = line[col]
            if cell.width == 0 { continue } // trailing half of a wide glyph
            var character = cell.getCharacter()
            if character == "\u{0}" { character = " " }
            let style = CellStyle(cell.attribute)
            if style != currentStyle && !currentText.isEmpty {
                runs.append(StyledRun(text: currentText, style: currentStyle))
                currentText = ""
            }
            currentStyle = style
            currentText.append(character)
        }
        if !currentText.isEmpty {
            runs.append(StyledRun(text: currentText, style: currentStyle))
        }
        return runs
    }

    /// SwiftTerm hides the buffer's top offset, so find the first addressable row:
    /// step by a screenful (the window is always at least that tall), then bisect.
    private static func firstScrollInvariantRow(_ terminal: Terminal) -> Int? {
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
            if terminal.getScrollInvariantLine(row: mid) != nil {
                high = mid
            } else {
                low = mid + 1
            }
        }
        return low
    }
}

extension CellStyle {
    init(_ attribute: Attribute) {
        self.foreground = TermColor(attribute.fg)
        self.background = TermColor(attribute.bg)
        var flags: Flags = []
        let style = attribute.style
        if style.contains(.bold) { flags.insert(.bold) }
        if style.contains(.italic) { flags.insert(.italic) }
        if style.contains(.underline) { flags.insert(.underline) }
        if style.contains(.inverse) { flags.insert(.inverse) }
        if style.contains(.dim) { flags.insert(.dim) }
        if style.contains(.crossedOut) { flags.insert(.strikethrough) }
        if style.contains(.invisible) { flags.insert(.invisible) }
        self.flags = flags
    }
}

extension TermColor {
    init(_ color: Attribute.Color) {
        switch color {
        case .ansi256(let code): self = .indexed(code)
        case .trueColor(let r, let g, let b): self = .rgb(r, g, b)
        default: self = .default
        }
    }
}
