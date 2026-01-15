import Foundation
import Combine

class TerminalBuffer: ObservableObject {
    @Published var cursorPosition = Position(x: 0, y: 0)
    @Published var scrollbackLines: [TerminalLine] = []
    @Published var visibleLines: [TerminalLine] = []
    @Published var renderVersion: Int = 0
    
    private var columns: Int = 80
    private var rows: Int = 24
    private var scrollbackSize: Int = 1000
    
    private var currentAttributes = CharacterAttributes()
    private var parserState: ParserState = .normal
    private var csiBuffer: [UInt8] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupBuffer()
        setupNotifications()
        
        // Initialize with default size
        resize(columns: columns, rows: rows)
    }
    
    private func setupBuffer() {
        // Initialize visible lines
        visibleLines = (0..<rows).map { _ in
            TerminalLine(columns: columns)
        }
        
        // Initialize scrollback
        scrollbackLines = []
    }
    
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .terminalDataReceived)
            .sink { [weak self] notification in
                if let data = notification.object as? Data {
                    self?.processData(data)
                }
            }
            .store(in: &cancellables)
    }
    
    func resize(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
        
        // Resize visible lines
        visibleLines = visibleLines.map { line in
            line.resize(columns: columns)
        }
        
        // Ensure cursor is within bounds
        cursorPosition.x = min(cursorPosition.x, columns - 1)
        cursorPosition.y = min(cursorPosition.y, rows - 1)
        markDirty()
    }
    
    private func processData(_ data: Data) {
        var didChange = false
        for byte in data {
            if processByte(byte) {
                didChange = true
            }
        }
        if didChange {
            markDirty()
        }
    }

    private enum ParserState {
        case normal
        case escape
        case csi
        case osc
        case oscEscape
    }

    private func processByte(_ byte: UInt8) -> Bool {
        switch parserState {
        case .normal:
            if byte == 0x1B { // ESC
                parserState = .escape
                return false
            }
            if byte < 0x20 {
                return processControlByte(byte)
            }
            if byte < 0x7F {
                let scalar = UnicodeScalar(byte)
                let char = Character(scalar)
                return processCharacter(char)
            }
            return false
        case .escape:
            if byte == 0x5B { // [
                parserState = .csi
                csiBuffer.removeAll(keepingCapacity: true)
            } else if byte == 0x5D { // ] - OSC
                parserState = .osc
            } else {
                parserState = .normal
            }
            return false
        case .csi:
            if byte >= 0x40 && byte <= 0x7E {
                handleCSISequence(finalByte: byte, parameters: csiBuffer)
                csiBuffer.removeAll(keepingCapacity: true)
                parserState = .normal
            } else {
                csiBuffer.append(byte)
            }
            return false
        case .osc:
            if byte == 0x07 { // BEL terminator
                parserState = .normal
            } else if byte == 0x1B { // ESC
                parserState = .oscEscape
            }
            return false
        case .oscEscape:
            if byte == 0x5C { // ST terminator
                parserState = .normal
            } else {
                parserState = .osc
            }
            return false
        }
    }
    
    private func processControlByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x0D: // CR
            cursorPosition.x = 0
            return false
        case 0x0A: // LF
            return newLine()
        case 0x09: // TAB
            let tabStop = 8
            cursorPosition.x = ((cursorPosition.x / tabStop) + 1) * tabStop
            if cursorPosition.x >= columns {
                cursorPosition.x = columns - 1
            }
            return false
        case 0x08: // Backspace
            if cursorPosition.x > 0 {
                cursorPosition.x -= 1
            }
            return false
        default:
            return false
        }
    }

    private func processCharacter(_ char: Character) -> Bool {
        switch char {
        case "\r":
            // Carriage return - move cursor to beginning of line
            cursorPosition.x = 0
            
        case "\n":
            // Line feed - move cursor to next line
            _ = newLine()
            
        case "\t":
            // Tab - move cursor to next tab stop
            let tabStop = 8
            cursorPosition.x = ((cursorPosition.x / tabStop) + 1) * tabStop
            if cursorPosition.x >= columns {
                cursorPosition.x = columns - 1
            }
            
        case "\u{08}": // Backspace
            if cursorPosition.x > 0 {
                cursorPosition.x -= 1
            }
            
        default:
            // Printable character
            if cursorPosition.x < columns {
                let cell = TerminalCell(
                    character: char,
                    attributes: currentAttributes
                )
                visibleLines[cursorPosition.y].setCell(at: cursorPosition.x, cell: cell)
                cursorPosition.x += 1
                
                // Wrap to next line if needed
                if cursorPosition.x >= columns {
                    _ = newLine()
                }
                return true
            }
        }
        return false
    }
    
    private func newLine() -> Bool {
        cursorPosition.x = 0
        cursorPosition.y += 1
        
        if cursorPosition.y >= rows {
            // Scroll up
            scrollUp()
            cursorPosition.y = rows - 1
            return true
        }
        return false
    }
    
    private func scrollUp() {
        // Move first visible line to scrollback
        if let firstLine = visibleLines.first {
            scrollbackLines.append(firstLine)
            
            // Limit scrollback size
            if scrollbackLines.count > scrollbackSize {
                scrollbackLines.removeFirst()
            }
        }
        
        // Shift visible lines up
        visibleLines.removeFirst()
        
        // Add new empty line at bottom
        visibleLines.append(TerminalLine(columns: columns))
    }
    
    func getCell(at position: Position) -> TerminalCell? {
        guard position.y >= 0 && position.y < visibleLines.count else { return nil }
        return visibleLines[position.y].getCell(at: position.x)
    }
    
    func setAttributes(_ attributes: CharacterAttributes) {
        currentAttributes = attributes
    }

    private func handleCSISequence(finalByte: UInt8, parameters: [UInt8]) {
        guard finalByte == 0x6D else { return } // 'm' SGR only
        let paramString = String(bytes: parameters, encoding: .utf8) ?? ""
        let parts = paramString.split(separator: ";")
        let values = parts.compactMap { Int($0) }
        applySGR(values.isEmpty ? [0] : values)
    }

    private func applySGR(_ params: [Int]) {
        var index = 0
        while index < params.count {
            let code = params[index]
            switch code {
            case 0:
                currentAttributes = CharacterAttributes()
            case 1:
                currentAttributes.isBold = true
            case 22:
                currentAttributes.isBold = false
            case 30...37:
                currentAttributes.foregroundColor = standardColor(code - 30, bright: false)
            case 90...97:
                currentAttributes.foregroundColor = standardColor(code - 90, bright: true)
            case 39:
                currentAttributes.foregroundColor = .white
            case 38:
                if index + 1 < params.count {
                    let mode = params[index + 1]
                    if mode == 5, index + 2 < params.count {
                        let colorIndex = params[index + 2]
                        currentAttributes.foregroundColor = colorFromAnsiIndex(colorIndex)
                        index += 2
                    } else if mode == 2, index + 4 < params.count {
                        let r = params[index + 2]
                        let g = params[index + 3]
                        let b = params[index + 4]
                        currentAttributes.foregroundColor = .custom(
                            r: UInt8(clamping: r),
                            g: UInt8(clamping: g),
                            b: UInt8(clamping: b)
                        )
                        index += 4
                    }
                }
            default:
                break
            }
            index += 1
        }
    }

    private func standardColor(_ index: Int, bright: Bool) -> Color {
        switch index {
        case 0: return bright ? .brightBlack : .black
        case 1: return bright ? .brightRed : .red
        case 2: return bright ? .brightGreen : .green
        case 3: return bright ? .brightYellow : .yellow
        case 4: return bright ? .brightBlue : .blue
        case 5: return bright ? .brightMagenta : .magenta
        case 6: return bright ? .brightCyan : .cyan
        case 7: return bright ? .brightWhite : .white
        default: return .white
        }
    }

    private func colorFromAnsiIndex(_ index: Int) -> Color {
        if index < 0 {
            return .white
        }
        if index < 8 {
            return standardColor(index, bright: false)
        }
        if index < 16 {
            return standardColor(index - 8, bright: true)
        }
        if index <= 231 {
            let idx = index - 16
            let r = idx / 36
            let g = (idx % 36) / 6
            let b = idx % 6
            let steps: [UInt8] = [0, 95, 135, 175, 215, 255]
            return .custom(r: steps[r], g: steps[g], b: steps[b])
        }
        if index <= 255 {
            let level = 8 + (index - 232) * 10
            let value = UInt8(clamping: level)
            return .custom(r: value, g: value, b: value)
        }
        return .white
    }

    private func markDirty() {
        renderVersion &+= 1
    }
}

struct Position: Equatable {
    var x: Int
    var y: Int
}

struct CharacterAttributes: Equatable {
    var foregroundColor: Color = .white
    var backgroundColor: Color = .black
    var isBold: Bool = false
    var isItalic: Bool = false
    var isUnderline: Bool = false
    var isInverse: Bool = false
}

enum Color: Equatable {
    case black
    case red
    case green
    case yellow
    case blue
    case magenta
    case cyan
    case white
    case brightBlack
    case brightRed
    case brightGreen
    case brightYellow
    case brightBlue
    case brightMagenta
    case brightCyan
    case brightWhite
    case custom(r: UInt8, g: UInt8, b: UInt8)
}

struct TerminalCell: Equatable {
    let character: Character
    let attributes: CharacterAttributes
}

class TerminalLine {
    private var cells: [TerminalCell?]
    
    init(columns: Int) {
        cells = Array(repeating: nil, count: columns)
    }
    
    func getCell(at index: Int) -> TerminalCell? {
        guard index >= 0 && index < cells.count else { return nil }
        return cells[index]
    }
    
    func setCell(at index: Int, cell: TerminalCell) {
        guard index >= 0 && index < cells.count else { return }
        cells[index] = cell
    }
    
    func resize(columns: Int) -> TerminalLine {
        let newLine = TerminalLine(columns: columns)
        let copyCount = min(columns, cells.count)
        
        // Bulk copy instead of element-by-element
        if copyCount > 0 {
            newLine.cells.replaceSubrange(0..<copyCount, with: cells.prefix(copyCount))
        }
        
        return newLine
    }
}
