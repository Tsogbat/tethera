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

    /// For a Claude Code `PermissionRequest`: asks the Tethera app and waits for Allow or Deny.
    /// Returns the decision JSON to print, or nil to leave the question to Claude's own dialog
    /// (Tethera isn't running, "Answer in terminal", or no answer before the hook's time runs out).
    static func askForApproval(payload: String, timeout: TimeInterval = 590) -> String? {
        let env = ProcessInfo.processInfo.environment
        guard let json = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any],
              json["hook_event_name"] as? String == "PermissionRequest" else { return nil }
        // Your rules and your team's answer first; only what they leave open reaches you.
        let tool = json["tool_name"] as? String ?? ""
        let input = json["tool_input"] as? [String: Any] ?? [:]
        if let decision = ApprovalPolicies.decide(agent: "claude", tool: tool, input: input), decision.rule.action != .ask {
            JournalFile.appendPolicyDecision(decision, agent: "claude", tool: tool, subject: ApprovalPolicies.subject(tool: tool, input: input),
                                             session: env["TETHERA_SESSION_ID"], cwd: json["cwd"] as? String)
            let why = decision.rule.note.map { " (\($0))" } ?? ""
            return ApprovalDecision.claude(decision.rule.action.rawValue,
                                           message: "Denied by \(decision.fromTeam ? "your team's" : "your") Tethera policy: \(decision.rule.summary)\(why)")
        }
        var params: [String: Any] = ["agent": "claude"]
        for key in ["tool_name", "tool_input", "cwd", "session_id", "transcript_path", "permission_mode"] {
            if let value = json[key] { params[key] = value }
        }
        guard let connection = try? AppChannel.Connection(),
              let response = try? connection.call("approval.request", params: params, session: env["TETHERA_SESSION_ID"], timeout: timeout),
              let answer = response.text else { return nil }
        return ApprovalDecision.claude(answer)
    }

    /// The current branch of a folder, read straight from `.git/HEAD` (no git process: the
    /// status line runs often and must be fast).
    static func gitBranch(in folder: String) -> String? {
        var current = (folder as NSString).standardizingPath
        let fm = FileManager.default
        while !current.isEmpty {
            var gitDir = (current as NSString).appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: gitDir, isDirectory: &isDirectory) {
                if !isDirectory.boolValue, let pointer = try? String(contentsOfFile: gitDir, encoding: .utf8),
                   pointer.hasPrefix("gitdir: ") {
                    // A worktree: .git is a file pointing at the real git dir.
                    gitDir = pointer.dropFirst(8).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard let head = try? String(contentsOfFile: (gitDir as NSString).appendingPathComponent("HEAD"), encoding: .utf8) else { return nil }
                let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.hasPrefix("ref: refs/heads/") ? String(trimmed.dropFirst(16)) : String(trimmed.prefix(7))
            }
            if current == "/" { break }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
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
