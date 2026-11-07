import XCTest
import SwiftTerm
@testable import Tethera

private final class NullTerminalDelegate: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}

final class TerminalRenderingTests: XCTestCase {
    private func makeTerminal(cols: Int = 40, rows: Int = 10) -> Terminal {
        Terminal(delegate: NullTerminalDelegate(), options: TerminalOptions(cols: cols, rows: rows, scrollback: 1_000))
    }

    func testCaptureKeepsColorsAndTrimsBlankLines() {
        let terminal = makeTerminal()
        terminal.feed(text: "\r\n\u{1b}[31mred\u{1b}[0m plain\r\n\u{1b}[1;32mbold green\u{1b}[0m\r\n\r\n")
        let styled = StyledText.capture(from: terminal, maxLines: 100)
        XCTAssertEqual(styled.plainText, "red plain\nbold green")
        XCTAssertEqual(styled.lines[0].first?.style.foreground, .indexed(1))
        XCTAssertEqual(styled.lines[1].first?.style.flags.contains(.bold), true)
    }

    func testCarriageReturnRewritesLine() {
        let terminal = makeTerminal()
        terminal.feed(text: "50%\r100%\r\n")
        XCTAssertEqual(StyledText.capture(from: terminal, maxLines: 100).plainText, "100%")
    }

    func testCaptureIncludesScrollbackAndTruncates() {
        let terminal = makeTerminal(rows: 5)
        for i in 1...30 { terminal.feed(text: "line \(i)\r\n") }
        let all = StyledText.capture(from: terminal, maxLines: 100)
        XCTAssertEqual(all.lineCount, 30)
        XCTAssertEqual(all.lines.first?.first?.text, "line 1")
        let capped = StyledText.capture(from: terminal, maxLines: 10)
        XCTAssertEqual(capped.lineCount, 10)
        XCTAssertEqual(capped.truncatedLineCount, 20)
        XCTAssertEqual(capped.lines.first?.first?.text, "line 21")
    }

    func testCaptureAfterResetStartsFresh() {
        let terminal = makeTerminal(rows: 5)
        for i in 1...12 { terminal.feed(text: "old \(i)\r\n") }
        terminal.feed(text: "\u{1b}c")
        terminal.feed(text: "new\r\n")
        XCTAssertEqual(StyledText.capture(from: terminal, maxLines: 100).plainText, "new")
    }

    func testUsedRows() {
        let terminal = makeTerminal(rows: 10)
        XCTAssertEqual(StyledText.usedRows(in: terminal), 1)
        terminal.feed(text: "a\r\nb\r\nc")
        XCTAssertEqual(StyledText.usedRows(in: terminal), 3)
        for _ in 0..<20 { terminal.feed(text: "x\r\n") }
        XCTAssertEqual(StyledText.usedRows(in: terminal), 10)
    }

    func testAttributedStringUsesPalette() {
        let styled = StyledText(lines: [[StyledRun(text: "err", style: CellStyle(foreground: .indexed(1)))]])
        let attributed = styled.attributedString(palette: .dracula)
        let color = attributed.runs.first?.foregroundColor
        XCTAssertEqual(color, TerminalPalette.dracula.ansi[1].color)
    }

    func testPaletteIndexing() {
        let palette = TerminalPalette.tetheraDark
        XCTAssertEqual(palette.color(index: 196), RGB(255, 0, 0))
        XCTAssertEqual(palette.color(index: 232), RGB(8, 8, 8))
        XCTAssertEqual(palette.color(index: 3), palette.ansi[3])
    }

    func testThemeDecodingFromOldSettings() throws {
        let legacy = #"{"isDarkMode":true,"fontFamily":"Menlo","fontSize":15,"accentColor":{"red":1,"green":0,"blue":0,"alpha":1}}"#
        let decoded = try JSONDecoder().decode(ThemeConfiguration.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.fontFamily, "Menlo")
        XCTAssertEqual(decoded.fontSize, 15)
        XCTAssertNil(decoded.palette)
        XCTAssertEqual(decoded.effectivePalette.ansi.count, 16)
    }
}
