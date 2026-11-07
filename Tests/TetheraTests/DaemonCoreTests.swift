import XCTest
import SwiftTerm
@testable import TetheraDaemon
@testable import TetheraKit

private final class NullDelegate: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}

final class WireTests: XCTestCase {
    func testFramesRoundTripAcrossArbitrarySplits() throws {
        let id = UUID()
        var hello = ControlMessage(.hello)
        hello.protocolVersion = 1
        let frames: [Frame] = [
            .control(hello),
            .output(session: id, seq: 42, bytes: Data("hello \u{1b}[31mred\u{1b}[0m".utf8)),
            .snapshot(session: id, seq: 7, bytes: Data(repeating: 0x41, count: 100_000)),
            .input(session: id, bytes: Data([0x03])),
        ]
        let stream = frames.reduce(into: Data()) { $0.append($1.encoded()) }
        var decoder = FrameDecoder()
        var decoded: [Frame] = []
        var offset = 0
        for size in [1, 3, 7, 4_096, 1, 65_536, 200_000] where offset < stream.count {
            let end = min(stream.count, offset + size)
            decoded += try decoder.append(stream[offset..<end])
            offset = end
        }
        XCTAssertEqual(decoded, frames)
        XCTAssertEqual(decoded.first?.controlMessage?.protocolVersion, 1)
    }

    func testRejectsOversizedFrames() {
        var decoder = FrameDecoder()
        XCTAssertThrowsError(try decoder.append(Data([0xff, 0xff, 0xff, 0xff, 0x01])))
    }
}

final class QueryFilterTests: XCTestCase {
    private func run(_ chunks: [String]) -> String {
        var filter = QueryFilter()
        let out = chunks.flatMap { filter.filter(Array($0.utf8)) }
        return String(decoding: out, as: UTF8.self)
    }

    func testDropsQueriesTheDaemonAnswers() {
        let queries = [
            "\u{1b}[c", "\u{1b}[0c", "\u{1b}[>c", "\u{1b}[>0c", "\u{1b}[5n", "\u{1b}[6n", "\u{1b}[?6n",
            "\u{1b}[?25$p", "\u{1b}[2026$p", "\u{1b}[>q", "\u{1b}[>0q", "\u{1b}[?u", "\u{1b}[14t", "\u{1b}[18t",
            "\u{1b}]11;?\u{07}", "\u{1b}]10;?\u{1b}\\", "\u{1b}]4;1;?\u{07}", "\u{1b}]52;c;?\u{07}",
            "\u{1b}]7501;?\u{07}", "\u{1b}P$qr\u{1b}\\", "\u{1b}P+q544e\u{1b}\\",
        ]
        for query in queries {
            XCTAssertEqual(run(["a" + query + "b"]), "ab", "should drop \(query.debugDescription)")
        }
    }

    func testPassesEverythingElse() {
        let text = "x\u{1b}[31mred\u{1b}[0m\u{1b}[2 q\u{1b}[>1u\u{1b}[<u\u{1b}[=5;1u\u{1b}[?2004h\u{1b}[?1049h"
            + "\u{1b}]2;title\u{07}\u{1b}]8;;https://a.b\u{1b}\\link\u{1b}]8;;\u{1b}\\\u{1b}[8;40;120t\u{1b}[22t"
            + "\u{1b}]7501;state=working\u{07}\u{1b}]133;A\u{07}\u{1b}7\u{1b}8 ❯ done"
        XCTAssertEqual(run([text]), text)
    }

    func testHandlesSplitsAndLongStrings() {
        XCTAssertEqual(run(["a\u{1b}", "[", "6", "n", "b"]), "ab")
        XCTAssertEqual(run(["a\u{1b}]11", ";?", "\u{07}b"]), "ab")
        XCTAssertEqual(run(["\u{1b}[3", "1mx"]), "\u{1b}[31mx")
        let long = "\u{1b}]52;c;" + String(repeating: "QUJD", count: 3_000) + "\u{07}after"
        XCTAssertEqual(run([long]), long)
        let sixel = "\u{1b}P0;1q#0;2;0;0;0~-\u{1b}\\tail"
        XCTAssertEqual(run([sixel]), sixel)
    }
}

final class PromptScannerTests: XCTestCase {
    func testReadsPromptMarksAndExitCodes() {
        var scanner = PromptScanner()
        let stream = "\u{1b}]133;A\u{07}$ \u{1b}]133;B\u{07}ls\r\n\u{1b}]133;C\u{07}out\r\n\u{1b}]133;D;2\u{1b}\\"
        let events = scanner.scan(Array(stream.utf8.prefix(20))) + scanner.scan(Array(stream.utf8.dropFirst(20)))
        XCTAssertEqual(events, [.promptStart, .commandStart, .commandEnd(exitCode: 2)])
    }
}

final class VTSnapshotTests: XCTestCase {
    private func terminal(cols: Int = 30, rows: Int = 6) -> Terminal {
        Terminal(delegate: NullDelegate(), options: TerminalOptions(cols: cols, rows: rows, scrollback: 500))
    }

    private func cells(_ terminal: Terminal) -> [String] {
        var rows: [String] = []
        guard let first = VTSnapshot.firstLine(terminal) else { return rows }
        var row = first
        while let line = terminal.getScrollInvariantLine(row: row) {
            var text = ""
            for col in 0..<line.getTrimmedLength() {
                let cell = line[col]
                if cell.width == 0 { continue }
                text += "\(cell.getCharacter())|\(cell.attribute.fg)|\(cell.attribute.bg)|\(cell.attribute.style.rawValue) "
            }
            rows.append(text)
            row += 1
        }
        return rows
    }

    func testReplayReproducesScreenScrollbackCursorAndModes() {
        let a = terminal()
        for i in 1...12 { a.feed(text: "\u{1b}[3\(i % 8)mline \(i)\u{1b}[0m plain\r\n") }
        a.feed(text: "\u{1b}[1;4;38;2;10;20;30mstyled\u{1b}[0m " + String(repeating: "w", count: 40)) // wraps
        a.feed(text: "\r\n漢字 ok\u{1b}[48;5;200m bg \u{1b}[0m")
        a.feed(text: "\u{1b}[?2004h\u{1b}[?1h\u{1b}[?1002h\u{1b}[3;5H")

        let snapshot = VTSnapshot.capture(a, title: "t", cursorStyle: .steadyBar, modes: .init())
        let b = terminal()
        b.feed(byteArray: Array(snapshot))

        XCTAssertEqual(cells(b), cells(a))
        XCTAssertEqual(b.buffer.x, a.buffer.x)
        XCTAssertEqual(b.buffer.y, a.buffer.y)
        XCTAssertTrue(b.bracketedPasteMode)
        XCTAssertTrue(b.applicationCursor)
        XCTAssertEqual(b.mouseMode, a.mouseMode)
    }

    func testAlternateScreenIsRestoredOnTopOfHistory() {
        let a = terminal()
        a.feed(text: "history line\r\n$ vim\r\n")
        a.feed(text: "\u{1b}[?1049h\u{1b}[H\u{1b}[2J\u{1b}[7m TUI \u{1b}[0m\u{1b}[4;3Hcursor")
        let b = terminal()
        b.feed(byteArray: Array(VTSnapshot.capture(a, title: "", cursorStyle: nil, modes: .init())))
        XCTAssertTrue(b.isCurrentBufferAlternate)
        for row in 0..<a.rows {
            // Never-written cells are NUL in the source and spaces in the replay; they look the same.
            let expected = a.getLine(row: row)?.translateToString(trimRight: true).replacingOccurrences(of: "\0", with: " ")
            XCTAssertEqual(b.getLine(row: row)?.translateToString(trimRight: true), expected)
        }
        XCTAssertEqual(b.getLine(row: 3)?.translateToString(trimRight: true), "  cursor")
        XCTAssertEqual(b.buffer.y, a.buffer.y)
        b.feed(text: "\u{1b}[?1049l")
        XCTAssertTrue(String(decoding: b.getBufferAsData(), as: UTF8.self).contains("history line"))
    }
}

/// Runs a real daemon in-process against a private home and drives a zsh session through it.
final class DaemonIntegrationTests: XCTestCase {
    private var home: URL!
    private var daemon: Daemon!

    override func setUpWithError() throws {
        home = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tt-\(getpid())", isDirectory: true)
        setenv("TETHERA_HOME", home.path, 1)
        daemon = Daemon(version: "test")
        try daemon.start()
    }

    override func tearDown() {
        daemon.stop(endSessions: true)
        try? FileManager.default.removeItem(at: home)
        unsetenv("TETHERA_HOME")
    }

    private final class Probe {
        let socket: FramedSocket
        var messages: [ControlMessage] = []
        var output = Data()
        var snapshots: [Data] = []
        let lock = NSLock()

        init() throws {
            socket = FramedSocket(fd: try UnixSocket.connect(path: TetheraPaths.socket.path), queue: DispatchQueue(label: "probe"))
            socket.onFrame = { [unowned self] frame in
                lock.lock(); defer { lock.unlock() }
                switch frame {
                case .control: if let message = frame.controlMessage { messages.append(message) }
                case .output(_, _, let bytes): output.append(bytes)
                case .snapshot(_, _, let bytes): snapshots.append(bytes)
                case .input: break
                }
            }
            socket.start()
        }

        func wait(_ timeout: TimeInterval = 10, _ condition: (Probe) -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                lock.lock(); let done = condition(self); lock.unlock()
                if done { return true }
                usleep(20_000)
            }
            return false
        }

        var text: String { String(decoding: output, as: UTF8.self) }
    }

    func testCreateAttachTypeDetachReattach() throws {
        let probe = try Probe()
        var hello = ControlMessage(.hello)
        hello.protocolVersion = tetheraProtocolVersion
        probe.socket.send(hello)
        probe.socket.send(ControlMessage(.subscribe))
        XCTAssertTrue(probe.wait { $0.messages.contains { $0.type == .welcome } })

        var create = ControlMessage(.create)
        create.spec = SessionSpec(name: "it", cwd: NSTemporaryDirectory(), shell: "/bin/zsh", cols: 80, rows: 24)
        probe.socket.send(create)
        XCTAssertTrue(probe.wait { $0.messages.contains { $0.type == .created } })
        let id = try XCTUnwrap(probe.messages.first { $0.type == .created }?.info?.id)

        var attach = ControlMessage(.attach, session: id)
        attach.cols = 80
        attach.rows = 24
        probe.socket.send(attach)
        XCTAssertTrue(probe.wait { $0.snapshots.count == 1 })

        // Wait for the integration's first prompt mark, then run a command.
        XCTAssertTrue(probe.wait(15) { probe in
            probe.messages.contains { $0.type == .updated && $0.info?.foreground == "zsh" }
        })
        probe.socket.send(.input(session: id, bytes: Data("echo tethera-$((40+2))\r".utf8)))
        XCTAssertTrue(probe.wait { $0.text.contains("tethera-42") }, "output was: \(probe.text.debugDescription)")
        XCTAssertFalse(probe.text.contains("\u{1b}]7501;?"), "queries must not reach clients")

        // Foreground detection sees the running program.
        probe.socket.send(.input(session: id, bytes: Data("sleep 3\r".utf8)))
        XCTAssertTrue(probe.wait { $0.messages.contains { $0.type == .updated && $0.info?.foreground == "sleep" } })
        probe.socket.send(.input(session: id, bytes: Data([0x03])))

        // A second client attaching gets the history in its snapshot.
        let second = try Probe()
        var reattach = ControlMessage(.attach, session: id)
        reattach.cols = 80
        reattach.rows = 24
        second.socket.send(reattach)
        XCTAssertTrue(second.wait { $0.snapshots.count == 1 })
        XCTAssertTrue(String(decoding: second.snapshots[0], as: UTF8.self).contains("tethera-42"))

        // A program reporting OSC 7501 status turns into agent state, with no hooks configured.
        probe.socket.send(.input(session: id, bytes: Data("printf '\\033]7501;state=blocked:kind=permission:app=claude\\007'; sleep 2\r".utf8)))
        XCTAssertTrue(probe.wait { $0.messages.contains { $0.info?.agent?.state == .needsInput && $0.info?.agent?.reason == "permission" } },
                      "OSC 7501 should mark the session as needing permission")

        // The real `tethera hook` binary, run the way an agent's hook would run it, updates the session.
        let cli = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("tethera-cli")
        let hook = Process()
        hook.executableURL = cli
        hook.arguments = ["hook", "claude"]
        hook.environment = ["TETHERA_SESSION_ID": id.uuidString, "TETHERA_SOCKET": TetheraPaths.socket.path]
        let stdin = Pipe()
        hook.standardInput = stdin
        let stdout = Pipe()
        hook.standardOutput = stdout
        try hook.run()
        stdin.fileHandleForWriting.write(Data(#"{"hook_event_name":"Stop","last_assistant_message":"Refactor done."}"#.utf8))
        try stdin.fileHandleForWriting.close()
        hook.waitUntilExit()
        XCTAssertEqual(hook.terminationStatus, 0)
        XCTAssertTrue(stdout.fileHandleForReading.readDataToEndOfFile().isEmpty, "hooks must print nothing")
        XCTAssertTrue(probe.wait { $0.messages.contains { $0.info?.agent?.state == .done && $0.info?.agent?.message == "Refactor done." } })

        // Exiting the shell ends the session.
        probe.socket.send(.input(session: id, bytes: Data("exit\r".utf8)))
        XCTAssertTrue(probe.wait { $0.messages.contains { $0.type == .removed && $0.session == id } })
    }
}
