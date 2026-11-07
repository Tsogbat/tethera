import XCTest
@testable import Tethera

/// Spawns a real login shell with Tethera's integration and checks the block protocol.
@MainActor
final class ShellSessionTests: XCTestCase {
    private final class Recorder: ShellSessionDelegate {
        var events: [OSC133Splitter.Event] = []
        var output: [UInt8] = []
        var onEvent: (() -> Void)?

        func shellSession(_ session: ShellSession, didReceive event: OSC133Splitter.Event) {
            if case .bytes(.output, let bytes) = event {
                output += bytes
            } else if case .bytes = event {
                // prompt / startup noise
            } else {
                events.append(event)
            }
            onEvent?()
        }

        func shellSessionDidExit(_ session: ShellSession, status: Int32?) {}

        var promptCount: Int { events.filter { $0 == .promptStart }.count }
        var exitCodes: [Int32?] {
            events.compactMap { if case .commandEnd(let code) = $0 { return code } else { return nil } }
        }
    }

    private func waitUntil(_ timeout: TimeInterval = 15, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func runCycle(shell: String) throws {
        guard FileManager.default.isExecutableFile(atPath: shell) else { throw XCTSkip("\(shell) not available") }
        let recorder = Recorder()
        let session = ShellSession(shellPath: shell)
        session.delegate = recorder
        session.start(workingDirectory: NSTemporaryDirectory(), columns: 100, rows: 30)
        defer { session.terminate() }

        waitUntil { recorder.promptCount >= 1 }
        XCTAssertGreaterThanOrEqual(recorder.promptCount, 1, "\(shell): integration never reported a prompt")

        session.submit("printf 'hello\\nworld\\n'")
        waitUntil { recorder.exitCodes.count >= 1 }
        XCTAssertEqual(recorder.exitCodes.first ?? nil, 0)
        let text = String(decoding: recorder.output, as: UTF8.self)
        XCTAssertTrue(text.contains("hello"), "output was: \(text.debugDescription)")
        XCTAssertTrue(text.contains("world"))
        XCTAssertFalse(text.contains("printf"), "the echoed command line leaked into output")

        recorder.output.removeAll()
        session.submit("false")
        waitUntil { recorder.exitCodes.count >= 2 }
        XCTAssertEqual(recorder.exitCodes.last ?? nil, 1)

        session.submit("cd /usr")
        waitUntil { recorder.events.contains(.workingDirectory("/usr")) }
        XCTAssertTrue(recorder.events.contains(.workingDirectory("/usr")))

        // A command whose output has no trailing newline.
        recorder.output.removeAll()
        session.submit("printf done")
        waitUntil { recorder.exitCodes.count >= 4 }
        XCTAssertEqual(String(decoding: recorder.output, as: UTF8.self), "done")
    }

    func testZshCommandCycle() throws {
        try runCycle(shell: "/bin/zsh")
    }

    func testBashCommandCycle() throws {
        try runCycle(shell: "/bin/bash")
    }

    func testInterruptReportsExitCode() throws {
        let recorder = Recorder()
        let session = ShellSession(shellPath: "/bin/zsh")
        session.delegate = recorder
        session.start(workingDirectory: NSTemporaryDirectory(), columns: 100, rows: 30)
        defer { session.terminate() }
        waitUntil { recorder.promptCount >= 1 }
        session.submit("sleep 30")
        waitUntil(5) { recorder.events.contains(.outputStart) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        session.interrupt()
        waitUntil { !recorder.exitCodes.isEmpty }
        XCTAssertEqual(recorder.exitCodes.first ?? nil, 130)
    }
}
