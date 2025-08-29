import Foundation
import Combine

class TerminalBuffer: ObservableObject {
    @Published var cursorPosition = Position(x: 0, y: 0)
    @Published var scrollbackLines: [TerminalLine] = []
    @Published var visibleLines: [TerminalLine] = []
    
    private var columns: Int = 80
    private var rows: Int = 24
    private var scrollbackSize: Int = 1000
    
    private var currentLine: TerminalLine
    private var currentAttributes = CharacterAttributes()
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        currentLine = TerminalLine(columns: columns)
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
        
        // Resize current line
        currentLine = currentLine.resize(columns: columns)
        
        // Ensure cursor is within bounds
        cursorPosition.x = min(cursorPosition.x, columns - 1)
        cursorPosition.y = min(cursorPosition.y, rows - 1)
    }
    
    private func processData(_ data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return }
        
        for char in string {
            processCharacter(char)
        }
    }
    
    private func processCharacter(_ char: Character) {
        switch char {
        case "\r":
            // Carriage return - move cursor to beginning of line
            cursorPosition.x = 0
            
        case "\n":
            // Line feed - move cursor to next line
            newLine()
            
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
                    newLine()
                }
            }
        }
    }
    
    private func newLine() {
        cursorPosition.x = 0
        cursorPosition.y += 1
        
        if cursorPosition.y >= rows {
            // Scroll up
            scrollUp()
            cursorPosition.y = rows - 1
        }
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
        
        for i in 0..<copyCount {
            newLine.cells[i] = cells[i]
        }
        
        return newLine
    }
}
