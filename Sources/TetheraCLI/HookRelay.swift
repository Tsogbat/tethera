import Foundation
import TetheraKit

/// Relays agent hook payloads to the daemon that owns the session they ran in.
enum HookRelay {
    /// Reads the hook payload, giving up quickly if nothing arrives.
    static func readStdin(limit: Int = 1_048_576) -> String {
        guard isatty(STDIN_FILENO) == 0 else { return "{}" }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var poll = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        while data.count < limit, Darwin.poll(&poll, 1, 500) > 0 {
            let count = read(STDIN_FILENO, &buffer, buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer[0..<count])
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Sends the payload to the session's daemon. Does nothing outside a Tethera session.
    static func forward(source: String, payload: String) {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["TETHERA_SESSION_ID"], let session = UUID(uuidString: raw) else { return }
        let socketPath = env["TETHERA_SOCKET"] ?? TetheraPaths.socket.path
        guard let fd = try? UnixSocket.connect(path: socketPath) else { return }
        defer { close(fd) }
        var message = ControlMessage(.hook, session: session)
        message.agent = source
        message.payload = payload
        message.sentAt = Date().timeIntervalSince1970
        let frame = Frame.control(message).encoded()
        _ = frame.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    }

    /// Adds the event name (passed as an argument) to a payload that doesn't carry one.
    static func injecting(event: String, into payload: String) -> String {
        guard var json = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any] else {
            return "{\"hook_event_name\":\"\(event)\"}"
        }
        if json["hook_event_name"] == nil { json["hook_event_name"] = event }
        return (try? JSONSerialization.data(withJSONObject: json)).map { String(decoding: $0, as: UTF8.self) } ?? payload
    }

    /// Runs the status line command the user had before Tethera wrapped it, passing the same
    /// JSON, and prints its output so Claude Code shows it unchanged.
    static func runSavedStatusLine(for source: String, input: String) {
        let saved = TetheraPaths.home.appendingPathComponent("integrations/\(source)-statusline.json")
        guard let data = try? Data(contentsOf: saved),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let command = object["command"] as? String, !command.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        do {
            try process.run()
        } catch {
            return
        }
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try? stdin.fileHandleForWriting.close()
        process.waitUntilExit()
    }
}
