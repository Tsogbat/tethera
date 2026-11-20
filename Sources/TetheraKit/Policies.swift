import Foundation

/// A rule that answers an agent's permission request before it reaches you.
///
///     { "tool": "Bash", "pattern": "npm test*", "action": "allow" }
///
/// `tool` and `pattern` are globs (`*`, `?`, `[…]`); a pattern written `/like this/` is a
/// regular expression. The pattern is matched against what the tool acts on: the command, the
/// file path, the URL.
public struct ApprovalRule: Codable, Equatable, Hashable, Identifiable, Sendable {
    public enum Action: String, Codable, CaseIterable, Sendable {
        case allow, deny, ask
    }

    public var id: String
    /// An agent (`claude`, `codex`, …); nil for any.
    public var agent: String?
    /// The tool's name, or a glob such as `mcp__*`. `*` is any tool.
    public var tool: String
    /// What the tool acts on; nil or empty for anything.
    public var pattern: String?
    public var action: Action
    /// Shown when the rule denies, and in the audit log.
    public var note: String?

    public init(id: String = UUID().uuidString, agent: String? = nil, tool: String, pattern: String? = nil, action: Action, note: String? = nil) {
        self.id = id
        self.agent = agent
        self.tool = tool
        self.pattern = pattern
        self.action = action
        self.note = note
    }

    /// "Bash npm test* → allow", for lists and the audit log.
    public var summary: String {
        let what = [agent, tool == "*" ? "any tool" : tool, pattern?.isEmpty == false ? pattern : nil].compactMap { $0 }.joined(separator: " ")
        return "\(what) → \(action.rawValue)"
    }

    public func matches(agent: String, tool: String, subject: String) -> Bool {
        if let wanted = self.agent, !wanted.isEmpty, wanted != agent { return false }
        guard Self.glob(self.tool.isEmpty ? "*" : self.tool, tool) else { return false }
        guard let pattern, !pattern.isEmpty else { return true }
        if pattern.count > 2, pattern.hasPrefix("/"), pattern.hasSuffix("/") {
            let source = String(pattern.dropFirst().dropLast())
            guard let regex = try? NSRegularExpression(pattern: source) else { return false }
            return regex.firstMatch(in: subject, range: NSRange(subject.startIndex..., in: subject)) != nil
        }
        return Self.glob(pattern, subject)
    }

    static func glob(_ pattern: String, _ text: String) -> Bool {
        fnmatch(pattern, text, 0) == 0
    }
}

/// Approval rules: your own (`TETHERA_HOME/policies.json`) and your team's
/// (`TETHERA_HOME/team/policies.json`, synced from the team repository). The team's come first,
/// and the first rule that matches decides. No match, or `ask`, leaves it to you.
public enum ApprovalPolicies {
    public struct Decision: Equatable, Sendable {
        public let rule: ApprovalRule
        public let fromTeam: Bool
    }

    public static var localFile: URL { TetheraPaths.home.appendingPathComponent("policies.json") }
    public static var teamFile: URL { TetheraPaths.home.appendingPathComponent("team/policies.json") }

    public static func load(_ url: URL) -> [ApprovalRule] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        if let rules = try? JSONDecoder().decode([ApprovalRule].self, from: data) { return rules }
        // A team file may wrap its rules: { "rules": [...] }.
        struct Wrapped: Decodable { var rules: [ApprovalRule] }
        return (try? JSONDecoder().decode(Wrapped.self, from: data))?.rules ?? []
    }

    public static func save(_ rules: [ApprovalRule], to url: URL = localFile) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(rules).write(to: url, options: .atomic)
    }

    /// The rule that decides this request, if any.
    public static func decide(agent: String, tool: String, input: [String: Any],
                              team: [ApprovalRule] = load(teamFile), local: [ApprovalRule] = load(localFile)) -> Decision? {
        let subject = subject(tool: tool, input: input)
        let rules = team.map { ($0, true) } + local.map { ($0, false) }
        for (rule, fromTeam) in rules where rule.matches(agent: agent, tool: tool, subject: subject) {
            // Allowing `npm test*` must not allow `npm test && rm -rf ~`: a command that chains,
            // pipes, substitutes or redirects is never allowed by a rule, only asked about.
            if rule.action == .allow && isCompound(tool: tool, subject: subject) { continue }
            return Decision(rule: rule, fromTeam: fromTeam)
        }
        return nil
    }

    /// What a tool acts on: its command, file, URL or pattern.
    public static func subject(tool: String, input: [String: Any]) -> String {
        for key in ["command", "file_path", "path", "url", "pattern", "notebook_path", "query", "description"] {
            if let value = input[key] as? String, !value.isEmpty { return value }
        }
        guard !input.isEmpty, let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// A shell command doing more than one thing.
    public static func isCompound(tool: String, subject: String) -> Bool {
        guard ["Bash", "shell", "run_shell_command", "exec_command"].contains(tool) else { return false }
        return [";", "&", "|", "`", "$(", ">", "<", "\n"].contains { subject.contains($0) }
    }

    /// Starting points in Settings → Policies.
    public struct Preset: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let detail: String
        public let rules: [ApprovalRule]
    }

    public static let presets: [Preset] = [
        Preset(id: "read", title: "Allow reading files",
               detail: "Read, search and list files without asking.",
               rules: ["Read", "Glob", "Grep", "LS", "NotebookRead"].map { ApprovalRule(tool: $0, action: .allow) }),
        Preset(id: "tests", title: "Allow running tests",
               detail: "npm, pnpm, yarn, swift, cargo, go and pytest test runs.",
               rules: ["npm test*", "npm run test*", "pnpm test*", "yarn test*", "swift test*", "cargo test*", "go test*", "pytest*", "make test*"]
                .map { ApprovalRule(tool: "Bash", pattern: $0, action: .allow) }),
        Preset(id: "risky", title: "Always ask before force-pushing or deleting",
               detail: "git push --force, rm -rf and git reset --hard always come to you.",
               rules: ["*git push*--force*", "*git push* -f*", "*rm -rf*", "*rm -fr*", "*git reset --hard*"]
                .map { ApprovalRule(tool: "Bash", pattern: $0, action: .ask) }),
        Preset(id: "deploy", title: "Never deploy",
               detail: "Deny commands that mention deploy or publish.",
               rules: ["*deploy*", "*npm publish*", "*cargo publish*"]
                .map { ApprovalRule(tool: "Bash", pattern: $0, action: .deny, note: "Deploys go through a person.") }),
    ]
}
