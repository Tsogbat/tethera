import XCTest
@testable import TetheraKit

/// A real `tethera daemon` process hands its sessions to a new image of itself
/// (`tethera handover`): same daemon pid, same shells, same screens, still typing.
final class HandoverTests: XCTestCase {
    private var home: URL!
    private var daemon: Process!
    private var cli: URL { Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("tethera-cli") }

    override func setUpWithError() throws {
        home = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("th-\(getpid())", isDirectory: true)
        try? FileManager.default.removeItem(at: home)
        setenv("TETHERA_HOME", home.path, 1)
        daemon = Process()
        daemon.executableURL = cli
        daemon.arguments = ["daemon"]
        try daemon.run()
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: TetheraPaths.socket.path) && Date() < deadline { usleep(50_000) }
    }

    override func tearDown() {
        if let probe = try? Probe() { probe.socket.send(ControlMessage(.shutdown)); usleep(500_000) }
        daemon.terminate()
        try? FileManager.default.removeItem(at: home)
        unsetenv("TETHERA_HOME")
    }

    func testSessionsSurviveTheDaemonBecomingANewImage() throws {
        let probe = try Probe()
        probe.hello()
        XCTAssertTrue(probe.wait { $0.messages.contains { $0.type == .welcome } })
        let daemonPID = try XCTUnwrap(probe.messages.first { $0.type == .welcome }?.pid)

        func create(_ name: String) throws -> UUID {
            var create = ControlMessage(.create)
            create.spec = SessionSpec(name: name, cwd: NSTemporaryDirectory(), shell: "/bin/zsh", cols: 80, rows: 24)
            probe.socket.send(create)
            XCTAssertTrue(probe.wait { $0.messages.contains { $0.type == .created && $0.info?.name == name } })
            let id = try XCTUnwrap(probe.messages.first { $0.type == .created && $0.info?.name == name }?.info?.id)
            // Type only once the shell's first prompt is up; startup files can drop earlier typing.
            XCTAssertTrue(probe.wait(15) { $0.messages.contains { $0.type == .updated && $0.info?.id == id && $0.info?.foreground == "zsh" } })
            return id
        }
        let shell = try create("shell")
        let editor = try create("editor")
        probe.attach(shell)
        probe.socket.send(.input(session: shell, bytes: Data("echo before-$((40+2))\r".utf8)))
        XCTAssertTrue(probe.wait { $0.text.contains("before-42") }, probe.text)
        func vimStarted(_ timeout: TimeInterval) -> Bool {
            probe.socket.send(.input(session: editor, bytes: Data("vim -u NONE -N\r".utf8)))
            return probe.wait(timeout) { $0.messages.contains { $0.info?.id == editor && $0.info?.foreground == "vim" } }
        }
        XCTAssertTrue(vimStarted(6) || vimStarted(10), "vim started")
        let shellPID = try XCTUnwrap(probe.latest(shell)?.pid)
        let editorPID = try XCTUnwrap(probe.latest(editor)?.pid)

        // Hand over to the same binary: a new image of the daemon in the same process.
        let handover = Process()
        handover.executableURL = cli
        handover.arguments = ["handover"]
        let output = Pipe()
        handover.standardOutput = output
        handover.standardError = output
        try handover.run()
        handover.waitUntilExit()
        let said = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(handover.terminationStatus, 0, said)
        XCTAssertTrue(said.contains("2 session(s) kept"), said)
        XCTAssertTrue(probe.wait { $0.closed }, "the old connection drops at the exec")

        // Reconnect: same daemon process, same shells, still alive.
        let after = try Probe()
        after.hello()
        XCTAssertTrue(after.wait { $0.messages.contains { $0.type == .sessions } })
        XCTAssertEqual(after.messages.first { $0.type == .welcome }?.pid, daemonPID)
        let sessions = after.messages.first { $0.type == .sessions }?.sessions ?? []
        XCTAssertEqual(sessions.first { $0.id == shell }?.pid, shellPID)
        XCTAssertEqual(sessions.first { $0.id == editor }?.pid, editorPID)
        XCTAssertTrue(sessions.allSatisfy(\.isAlive))
        XCTAssertEqual(kill(shellPID, 0), 0, "the shell never stopped")

        // The screen came across, and the PTY still carries input and output.
        after.attach(shell)
        XCTAssertTrue(after.wait { $0.snapshots.count == 1 })
        XCTAssertTrue(String(decoding: after.snapshots[0], as: UTF8.self).contains("before-42"))
        after.socket.send(.input(session: shell, bytes: Data("echo after-$((6*7))\r".utf8)))
        XCTAssertTrue(after.wait { $0.text.contains("after-42") }, after.text)

        // The full-screen program is still on its alternate screen, and still answers.
        after.attach(editor)
        XCTAssertTrue(after.wait { $0.snapshots.count == 2 })
        XCTAssertTrue(String(decoding: after.snapshots[1], as: UTF8.self).contains("\u{1b}[?1049h"), "vim's screen is restored")
        after.socket.send(.input(session: editor, bytes: Data("\u{1b}:q!\r".utf8)))
        XCTAssertTrue(after.wait(10) { $0.messages.contains { $0.info?.id == editor && $0.info?.foreground == "zsh" } }, "vim quit normally")
    }

    private final class Probe {
        let socket: FramedSocket
        var messages: [ControlMessage] = []
        var output = Data()
        var snapshots: [Data] = []
        var closed = false
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
            socket.onClose = { [unowned self] _ in lock.lock(); closed = true; lock.unlock() }
            socket.start()
        }

        func hello() {
            var hello = ControlMessage(.hello)
            hello.protocolVersion = tetheraProtocolVersion
            socket.send(hello)
            socket.send(ControlMessage(.subscribe))
        }

        func attach(_ id: UUID) {
            var attach = ControlMessage(.attach, session: id)
            attach.cols = 80
            attach.rows = 24
            socket.send(attach)
        }

        func latest(_ id: UUID) -> SessionInfo? {
            lock.lock(); defer { lock.unlock() }
            return messages.last { $0.info?.id == id }?.info
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
}
