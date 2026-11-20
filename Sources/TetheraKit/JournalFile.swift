import Foundation

/// The journal's files: one JSON object per line, one file per day, in
/// `TETHERA_HOME/journal/YYYY-MM-DD.jsonl`. The app and the `tethera` hook both append, so each
/// line goes out in a single `O_APPEND` write and lines never interleave.
public enum JournalFile {
    public static var directory: URL { TetheraPaths.home.appendingPathComponent("journal", isDirectory: true) }

    public static func dayName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    public static func url(for date: Date) -> URL {
        directory.appendingPathComponent(dayName(date) + ".jsonl")
    }

    /// Appends one line (a newline is added).
    public static func append(_ line: Data, at date: Date = Date()) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(url(for: date).path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var data = line
        data.append(0x0A)
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    }

    /// An approval decided without asking anyone, by a rule.
    public static func appendPolicyDecision(_ decision: ApprovalPolicies.Decision, agent: String, tool: String, subject: String,
                                            session: String?, cwd: String?) {
        var event: [String: Any] = [
            "at": ISO8601DateFormatter().string(from: Date()),
            "kind": "approval",
            "agent": agent,
            "tool": tool,
            "detail": subject,
            "decision": decision.rule.action.rawValue,
            "by": decision.fromTeam ? "team policy" : "policy",
            "message": decision.rule.summary,
        ]
        if let session { event["session"] = session }
        if let cwd { event["repo"] = cwd }
        if let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]) { append(data) }
    }
}
