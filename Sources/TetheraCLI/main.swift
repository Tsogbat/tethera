import Foundation
import TetheraDaemon
import TetheraKit

/// `tethera` — the session daemon and its command-line client.
///
///     tethera daemon                     run the session daemon (the app starts it on demand)
///     tethera list                       list sessions
///     tethera new [--name N] [--cwd D] [--attach] [command…]
///     tethera attach <name|id>           attach this terminal; ⌃\ detaches
///     tethera rename <name|id> <new>     rename a session
///     tethera close <name|id>            end a session
///     tethera shutdown                   end every session and stop the daemon

let version = "0.4.0"
var arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.isEmpty ? "help" : arguments.removeFirst()

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("tethera: \(message)\n".utf8))
    exit(1)
}

/// This executable's path, so `tethera list` can start the daemon if it isn't running.
var selfPath: String {
    Bundle.main.executablePath ?? CommandLine.arguments[0]
}

/// A blocking request/response exchange for the one-shot commands.
struct BlockingClient {
    let fd: Int32
    private var decoder = FrameDecoder()

    init() {
        do {
            fd = try DaemonLauncher.connect(executable: selfPath)
        } catch {
            fail("can't reach the session daemon: \(error.localizedDescription)")
        }
    }

    func send(_ message: ControlMessage) {
        let data = Frame.control(message).encoded()
        _ = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
    }

    mutating func receive(until match: (ControlMessage) -> Bool) -> ControlMessage {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = read(fd, &buffer, buffer.count)
            guard count > 0 else { fail("the daemon closed the connection") }
            let frames = (try? decoder.append(Data(buffer[0..<count]))) ?? []
            for frame in frames {
                guard let message = frame.controlMessage else { continue }
                if message.type == .error { fail(message.message ?? "error") }
                if match(message) { return message }
            }
        }
    }

    mutating func sessions() -> [SessionInfo] {
        send(ControlMessage(.list))
        return receive { $0.type == .sessions }.sessions ?? []
    }
}

func resolve(_ query: String, in sessions: [SessionInfo]) -> SessionInfo {
    if let exact = sessions.first(where: { $0.name == query || $0.id.uuidString.lowercased() == query.lowercased() }) {
        return exact
    }
    let matches = sessions.filter { $0.id.uuidString.lowercased().hasPrefix(query.lowercased()) || $0.name.lowercased().hasPrefix(query.lowercased()) }
    guard matches.count == 1 else { fail(matches.isEmpty ? "no session matches “\(query)”" : "“\(query)” matches several sessions") }
    return matches[0]
}

func terminalSize() -> (cols: Int, rows: Int) {
    var size = winsize()
    if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 {
        return (Int(size.ws_col), Int(size.ws_row))
    }
    return (100, 30)
}

/// Relays this terminal to a session until ⌃\ or the session ends.
func attach(to session: UUID) -> Never {
    let fd: Int32
    do { fd = try DaemonLauncher.connect(executable: selfPath) } catch { fail("can't reach the session daemon") }
    let socket = FramedSocket(fd: fd, queue: .main)

    var original = termios()
    tcgetattr(STDIN_FILENO, &original)
    var raw = original
    cfmakeraw(&raw)
    tcsetattr(STDIN_FILENO, TCSANOW, &raw)
    func restore(_ message: String) -> Never {
        tcsetattr(STDIN_FILENO, TCSANOW, &original)
        FileHandle.standardError.write(Data("\r\n[\(message)]\r\n".utf8))
        exit(0)
    }

    socket.onFrame = { frame in
        switch frame {
        case .output(_, _, let bytes), .snapshot(_, _, let bytes):
            FileHandle.standardOutput.write(bytes)
        case .control:
            guard let message = frame.controlMessage else { return }
            if message.type == .removed && message.session == session { restore("session ended") }
            if message.type == .error { restore(message.message ?? "error") }
        case .input:
            break
        }
    }
    socket.onClose = { _ in restore("daemon disconnected") }
    socket.start()
    socket.send(ControlMessage(.subscribe))
    let size = terminalSize()
    var attach = ControlMessage(.attach, session: session)
    attach.cols = size.cols
    attach.rows = size.rows
    socket.send(attach)

    let stdin = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
    stdin.setEventHandler {
        var buffer = [UInt8](repeating: 0, count: 4_096)
        let count = read(STDIN_FILENO, &buffer, buffer.count)
        guard count > 0 else { restore("detached") }
        let bytes = buffer[0..<count]
        if let split = bytes.firstIndex(of: 0x1c) { // ⌃\ detaches
            if split > 0 { socket.send(.input(session: session, bytes: Data(bytes[..<split]))) }
            restore("detached — `tethera attach` to return")
        }
        socket.send(.input(session: session, bytes: Data(bytes)))
    }
    stdin.resume()

    signal(SIGWINCH, SIG_IGN)
    let winch = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: .main)
    winch.setEventHandler {
        let size = terminalSize()
        var resize = ControlMessage(.resize, session: session)
        resize.cols = size.cols
        resize.rows = size.rows
        socket.send(resize)
    }
    winch.resume()
    withExtendedLifetime((stdin, winch, socket)) { dispatchMain() }
}

switch command {
case "daemon":
    Daemon.runForever(version: version)

case "list", "ls":
    var client = BlockingClient()
    let sessions = client.sessions()
    if sessions.isEmpty { print("No sessions.") }
    for session in sessions {
        var state = session.isAlive ? (session.foreground ?? "") : "restored"
        if let agent = session.agent { state = "\(agent.kind.displayName) · \(agent.state.rawValue)" }
        let id = String(session.id.uuidString.prefix(8)).lowercased()
        print("\(id)  \(session.name.padding(toLength: 18, withPad: " ", startingAt: 0))  \(state.padding(toLength: 24, withPad: " ", startingAt: 0))  \(session.cwd)")
    }

case "new":
    var spec = SessionSpec()
    var attachAfter = false
    var rest: [String] = []
    var iterator = arguments.makeIterator()
    while let argument = iterator.next() {
        switch argument {
        case "--name": spec.name = iterator.next()
        case "--cwd": spec.cwd = iterator.next().map { ($0 as NSString).expandingTildeInPath }
        case "--attach", "-a": attachAfter = true
        default: rest.append(argument)
        }
    }
    if spec.cwd == nil { spec.cwd = FileManager.default.currentDirectoryPath }
    if !rest.isEmpty { spec.initialInput = rest.joined(separator: " ") + "\r" }
    let size = terminalSize()
    spec.cols = size.cols
    spec.rows = size.rows
    var client = BlockingClient()
    var create = ControlMessage(.create)
    create.spec = spec
    client.send(create)
    let created = client.receive { $0.type == .created }
    guard let info = created.info else { fail("no session created") }
    if attachAfter { attach(to: info.id) }
    print("\(String(info.id.uuidString.prefix(8)).lowercased())  \(info.name)")

case "attach", "a":
    guard let query = arguments.first else { fail("usage: tethera attach <name|id>") }
    var client = BlockingClient()
    attach(to: resolve(query, in: client.sessions()).id)

case "rename":
    guard arguments.count >= 2 else { fail("usage: tethera rename <name|id> <new name>") }
    var client = BlockingClient()
    var message = ControlMessage(.rename, session: resolve(arguments[0], in: client.sessions()).id)
    message.name = arguments.dropFirst().joined(separator: " ")
    client.send(message)

case "close", "kill":
    guard let query = arguments.first else { fail("usage: tethera close <name|id>") }
    var client = BlockingClient()
    client.send(ControlMessage(.close, session: resolve(query, in: client.sessions()).id))

case "shutdown":
    guard let fd = try? UnixSocket.connect(path: TetheraPaths.socket.path) else { print("The daemon isn't running."); exit(0) }
    let data = Frame.control(ControlMessage(.shutdown)).encoded()
    _ = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
    var buffer = [UInt8](repeating: 0, count: 1_024)
    _ = read(fd, &buffer, buffer.count)

case "hook":
    // Called by agents' hooks: `tethera hook <source> [event]`. Fast and always exits 0: a hook
    // must never slow or break the agent, and global hooks also fire outside Tethera.
    let source = arguments.first ?? "unknown"
    let event = arguments.count > 1 ? arguments[1] : nil
    // Codex `notify` passes its JSON as the argument; everyone else uses stdin.
    var payload = source == "codex-notify" ? (event ?? "{}") : HookRelay.readStdin()
    if let event, source != "codex-notify" { payload = HookRelay.injecting(event: event, into: payload) }
    HookRelay.forward(source: source, payload: payload)
    // Antigravity requires a decision from PreToolUse and Stop; allow and stop change nothing.
    if source == "agy" {
        print(event == "PreToolUse" ? #"{"decision":"allow"}"# : (event == "Stop" ? #"{"decision":"stop"}"# : "{}"))
    }
    exit(0)

case "title":
    // Antigravity's title command runs on every state change; report it, then print a title.
    let source = arguments.first ?? "agy"
    let payload = HookRelay.readStdin()
    HookRelay.forward(source: "\(source)-status", payload: payload)
    let json = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any]
    print((json?["conversation_title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Antigravity")
    exit(0)

case "statusline":
    // Claude Code's status line: report the JSON to Tethera, then run the user's own status line.
    let source = arguments.first ?? "claude"
    let payload = HookRelay.readStdin()
    HookRelay.forward(source: "\(source)-statusline", payload: payload)
    HookRelay.runSavedStatusLine(for: source, input: payload)
    exit(0)

case "version", "--version":
    print("tethera \(version)")

default:
    print("""
    tethera \(version) — persistent sessions for Tethera

      tethera list                        list sessions
      tethera new [--name N] [--cwd DIR] [--attach] [command…]
      tethera attach <name|id>            attach this terminal (⌃\\ detaches)
      tethera rename <name|id> <new name>
      tethera close <name|id>
      tethera shutdown                    end every session and stop the daemon
    """)
}
