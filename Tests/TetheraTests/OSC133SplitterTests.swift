import XCTest
@testable import Tethera

final class OSC133SplitterTests: XCTestCase {
    private func bytes(_ string: String) -> [UInt8] { Array(string.utf8) }

    func testFullCommandCycle() {
        var splitter = OSC133Splitter()
        let stream = "\u{1b}]133;A\u{07}prompt% ls\r\n\u{1b}]133;B\u{07}\u{1b}]133;C\u{07}file.txt\r\n\u{1b}]133;D;0\u{07}\u{1b}]7;file://host/Users/me\u{07}\u{1b}]133;A\u{07}"
        let events = splitter.feed(bytes(stream))
        XCTAssertEqual(events, [
            .promptStart,
            .bytes(.prompt, bytes("prompt% ls\r\n")),
            .commandStart,
            .outputStart,
            .bytes(.output, bytes("file.txt\r\n")),
            .commandEnd(exitCode: 0),
            .workingDirectory("/Users/me"),
            .promptStart,
        ])
        XCTAssertEqual(splitter.region, .prompt)
    }

    func testSequenceSplitAcrossReads() {
        var splitter = OSC133Splitter()
        var events = splitter.feed(bytes("\u{1b}]13"))
        XCTAssertTrue(events.isEmpty)
        events = splitter.feed(bytes("3;C\u{07}hello"))
        XCTAssertEqual(events, [.outputStart, .bytes(.output, bytes("hello"))])
        events = splitter.feed(bytes("\u{1b}"))
        XCTAssertTrue(events.isEmpty)
        events = splitter.feed(bytes("]133;D;127\u{1b}\\"))
        XCTAssertEqual(events, [.commandEnd(exitCode: 127)])
    }

    func testOtherEscapesPassThroughToOutput() {
        var splitter = OSC133Splitter()
        _ = splitter.feed(bytes("\u{1b}]133;C\u{07}"))
        let colored = "\u{1b}[31mred\u{1b}[0m \u{1b}]8;;https://x.dev\u{07}link\u{1b}]8;;\u{07} \u{1b}]0;title\u{07}"
        let events = splitter.feed(bytes(colored))
        XCTAssertEqual(events, [.bytes(.output, bytes(colored))])
    }

    func testUTF8IsUntouched() {
        var splitter = OSC133Splitter()
        _ = splitter.feed(bytes("\u{1b}]133;C\u{07}"))
        let text = "héllo ✓ 你好 🚀\n"
        XCTAssertEqual(splitter.feed(bytes(text)), [.bytes(.output, bytes(text))])
    }

    func testBracketedPasteTracking() {
        var splitter = OSC133Splitter()
        let events = splitter.feed(bytes("\u{1b}[?2004h% \u{1b}[?2004l"))
        XCTAssertTrue(events.contains(.bracketedPaste(true)))
        XCTAssertTrue(events.contains(.bracketedPaste(false)))
    }

    func testNotifications() {
        var splitter = OSC133Splitter()
        let events = splitter.feed(bytes("\u{1b}]9;Claude needs input\u{07}\u{1b}]777;notify;Codex;Done\u{07}\u{1b}]9;4;1;50\u{07}"))
        XCTAssertEqual(events, [.notification("Claude needs input"), .notification("Codex: Done")])
    }

    func testCommandEndWithoutExitCode() {
        var splitter = OSC133Splitter()
        XCTAssertEqual(splitter.feed(bytes("\u{1b}]133;D\u{07}")), [.commandEnd(exitCode: nil)])
    }

    func testFileURLParsing() {
        XCTAssertEqual(OSC133Splitter.parseFileURL("file://mac.local/Users/me/My%20Folder"), "/Users/me/My Folder")
        XCTAssertEqual(OSC133Splitter.parseFileURL("file://mac.local/Users/me/raw space"), "/Users/me/raw space")
        XCTAssertEqual(OSC133Splitter.parseFileURL("file:///tmp"), "/tmp")
        XCTAssertNil(OSC133Splitter.parseFileURL("http://x/y"))
    }

    func testLoneEscapeBeforeText() {
        var splitter = OSC133Splitter()
        _ = splitter.feed(bytes("\u{1b}]133;C\u{07}"))
        XCTAssertEqual(splitter.feed(bytes("\u{1b}7saved\u{1b}8")), [.bytes(.output, bytes("\u{1b}7saved\u{1b}8"))])
    }
}
