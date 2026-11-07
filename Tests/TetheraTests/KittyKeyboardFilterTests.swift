import XCTest
import SwiftTerm
@testable import Tethera

private final class NullDelegate: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}

final class KittyKeyboardFilterTests: XCTestCase {
    private func run(_ chunks: [String]) -> String {
        var filter = KittyKeyboardFilter()
        var out: [UInt8] = []
        for chunk in chunks {
            out += filter.filter(Array(chunk.utf8)[...])
        }
        return String(decoding: out, as: UTF8.self)
    }

    func testPassesOrdinaryOutputAndSequences() {
        let text = "plain \u{1b}[31mred\u{1b}[0m \u{1b}[?2004h\u{1b}[1;2H\u{1b}[?1049l\u{1b}[s\u{1b}[u\u{1b}7\u{1b}8 ❯ done"
        XCTAssertEqual(run([text]), text)
    }

    func testDropsKittyKeyboardSequences() {
        XCTAssertEqual(run(["a\u{1b}[?ub"]), "ab")
        XCTAssertEqual(run(["a\u{1b}[>1ub"]), "ab")
        XCTAssertEqual(run(["a\u{1b}[<ub"]), "ab")
        XCTAssertEqual(run(["a\u{1b}[<2ub"]), "ab")
        XCTAssertEqual(run(["a\u{1b}[=5;1ub"]), "ab")
    }

    func testHandlesSequencesSplitAcrossReads() {
        XCTAssertEqual(run(["x\u{1b}", "[", "?", "u", "y"]), "xy")
        XCTAssertEqual(run(["x\u{1b}[?", "2004h"]), "x\u{1b}[?2004h")
        XCTAssertEqual(run(["\u{1b}", "\u{1b}[?u", "z"]), "\u{1b}z")
    }

    /// The bug this guards against: Claude Code's startup query made SwiftTerm restore the
    /// cursor, so its relative redraws landed rows above where they belong.
    func testQueryNoLongerMovesTheCursor() {
        let terminal = Terminal(delegate: NullDelegate(), options: TerminalOptions(cols: 20, rows: 6, scrollback: 10))
        var filter = KittyKeyboardFilter()
        let stream = "\u{1b}7\r\nline1\r\nline2\r\nline3\u{1b}[?u\u{1b}[cX"
        terminal.feed(byteArray: filter.filter(Array(stream.utf8)[...]))
        XCTAssertEqual(terminal.getLine(row: 3)?.translateToString(trimRight: true), "line3X")
        XCTAssertEqual(terminal.getLine(row: 0)?.translateToString(trimRight: true), "")
    }
}
