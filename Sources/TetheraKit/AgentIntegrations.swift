import Foundation

/// Connects agent CLIs to Tethera by adding hook entries to their config files.
///
/// Every change is computed first (so the UI can show it), merged into the user's existing
/// config without touching anything else, backed up before writing, and fully reversible:
/// Disconnect removes exactly Tethera's entries.
public enum AgentIntegrations {
    /// A computed change to one or more files.
    public struct Plan: Equatable {
        public struct Change: Equatable {
            public let file: URL
            public let before: String
            /// nil deletes the file.
            public let after: String?
        }

        public let changes: [Change]
        /// Tethera-owned files written alongside (e.g. the user's saved status line).
        public let sideFiles: [URL: Data]
        /// When a file can't be edited safely, what the user should add by hand.
        public let manualSteps: String?
        /// What the user still has to do in the agent (trust, consent, restart).
        public let note: String?

        public var hasChanges: Bool { changes.contains { $0.before != ($0.after ?? "") } }
    }

    public enum Target: String, CaseIterable, Sendable {
        case claude, codex, antigravity, hermes, opencode

        public var kind: AgentKind {
            switch self {
            case .claude: return .claude
            case .codex: return .codex
            case .antigravity: return .antigravity
            case .hermes: return .hermes
            case .opencode: return .opencode
            }
        }

        public init?(kind: AgentKind) {
            guard let target = Target.allCases.first(where: { $0.kind == kind }) else { return nil }
            self = target
        }

        /// The main file Connect edits, for display.
        public var configFile: URL {
            let home = AgentIntegrations.configHome
            switch self {
            case .claude: return home.appendingPathComponent(".claude/settings.json")
            case .codex: return home.appendingPathComponent(".codex/hooks.json")
            case .antigravity: return home.appendingPathComponent(".gemini/config/hooks.json")
            case .hermes: return home.appendingPathComponent(".hermes/config.yaml")
            case .opencode: return home.appendingPathComponent(".config/opencode/plugins/tethera.js")
            }
        }
    }

    /// The home directory agent configs live under; `TETHERA_CONFIG_HOME` overrides it (tests).
    public static var configHome: URL {
        if let override = ProcessInfo.processInfo.environment["TETHERA_CONFIG_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// A stable, space-free link to Tethera's CLI. Hooks point here, so they survive the app
    /// moving; Hermes runs hook commands without a shell, so the path can't contain spaces.
    public static var cliLink: URL { configHome.appendingPathComponent(".local/bin/tethera") }

    static func command(_ arguments: String) -> String {
        "\(cliLink.path) \(arguments)"
    }

    static func isOurs(_ command: String) -> Bool {
        command.contains(cliLink.path) || (command.contains("tethera") && (command.contains(" hook ") || command.contains(" statusline ") || command.contains(" title ")))
    }

    // MARK: State

    public static func isConnected(_ target: Target) -> Bool {
        switch target {
        case .claude, .codex:
            return hookCommands(in: readJSON(target.configFile)?["hooks"] as? [String: Any]).contains { isOurs($0) }
        case .antigravity:
            return readJSON(target.configFile)?["tethera"] != nil
        case .hermes:
            return (try? String(contentsOf: target.configFile, encoding: .utf8))?.contains(hermesBegin) == true
        case .opencode:
            return FileManager.default.fileExists(atPath: target.configFile.path)
        }
    }

    public static func isStatusLineConnected() -> Bool {
        guard let line = readJSON(Target.claude.configFile)?["statusLine"] as? [String: Any] else { return false }
        return isOurs(line["command"] as? String ?? "")
    }

    private static func hookCommands(in hooks: [String: Any]?) -> [String] {
        (hooks ?? [:]).values.flatMap { groups in
            (groups as? [[String: Any]] ?? []).flatMap { group in
                (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
            }
        }
    }

    // MARK: Plans

    public static func connectPlan(_ target: Target, wrapStatusLine: Bool = false) -> Plan {
        switch target {
        case .claude: return claudeConnect(wrapStatusLine: wrapStatusLine)
        case .codex: return codexConnect()
        case .antigravity: return antigravityConnect()
        case .hermes: return hermesConnect()
        case .opencode: return openCodeConnect()
        }
    }

    public static func disconnectPlan(_ target: Target) -> Plan {
        switch target {
        case .claude:
            let file = Target.claude.configFile
            let original = readJSON(file) ?? [:]
            var json = removingOurHooks(from: original)
            if let line = original["statusLine"] as? [String: Any], isOurs(line["command"] as? String ?? "") {
                if let data = try? Data(contentsOf: savedStatusLine), let restored = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    json["statusLine"] = restored
                } else {
                    json.removeValue(forKey: "statusLine")
                }
            }
            return Plan(changes: [.init(file: file, before: render(original), after: render(json))], sideFiles: [:], manualSteps: nil, note: nil)
        case .codex:
            let file = Target.codex.configFile
            let original = readJSON(file) ?? [:]
            return Plan(changes: [.init(file: file, before: render(original), after: render(removingOurHooks(from: original)))], sideFiles: [:], manualSteps: nil, note: nil)
        case .antigravity:
            let hooksFile = Target.antigravity.configFile
            var hooks = readJSON(hooksFile) ?? [:]
            let hooksBefore = render(hooks)
            hooks.removeValue(forKey: "tethera")
            var changes = [Plan.Change(file: hooksFile, before: hooksBefore, after: render(hooks))]
            var settings = readJSON(antigravitySettings) ?? [:]
            if let title = settings["title"] as? [String: Any], isOurs(title["command"] as? String ?? "") {
                let before = render(settings)
                settings.removeValue(forKey: "title")
                changes.append(.init(file: antigravitySettings, before: before, after: render(settings)))
            }
            return Plan(changes: changes, sideFiles: [:], manualSteps: nil, note: nil)
        case .hermes:
            let file = Target.hermes.configFile
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            return Plan(changes: [.init(file: file, before: text, after: removingHermesBlock(text))], sideFiles: [:], manualSteps: nil, note: nil)
        case .opencode:
            let file = Target.opencode.configFile
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            return Plan(changes: [.init(file: file, before: text, after: nil)], sideFiles: [:], manualSteps: nil, note: nil)
        }
    }

    // MARK: Claude Code

    static var savedStatusLine: URL { TetheraPaths.home.appendingPathComponent("integrations/claude-statusline.json") }

    private static func claudeConnect(wrapStatusLine: Bool) -> Plan {
        let file = Target.claude.configFile
        let original = readJSON(file) ?? [:]
        var json = removingOurHooks(from: original)
        // The permission hook runs in line (and prints nothing, leaving the decision to the user);
        // everything else runs in the background so Claude never waits on Tethera.
        let events: [(String, Bool, Bool)] = [
            ("UserPromptSubmit", false, true), ("PreToolUse", true, true), ("PermissionRequest", true, false),
            ("Notification", false, true), ("Stop", false, true), ("StopFailure", false, true),
            ("SessionStart", false, true), ("SessionEnd", false, true),
        ]
        json["hooks"] = addingHooks(to: json["hooks"] as? [String: Any], events: events, command: command("hook claude"))

        var sideFiles: [URL: Data] = [:]
        if wrapStatusLine {
            let existing = original["statusLine"] as? [String: Any]
            if let existing, !isOurs(existing["command"] as? String ?? "") {
                sideFiles[savedStatusLine] = (try? JSONSerialization.data(withJSONObject: existing, options: [.prettyPrinted, .sortedKeys])) ?? Data()
            }
            json["statusLine"] = ["type": "command", "command": command("statusline claude"),
                                  "padding": (existing?["padding"] as? Int) ?? 0] as [String: Any]
        }
        return Plan(changes: [.init(file: file, before: render(readJSON(file)), after: render(json))], sideFiles: sideFiles, manualSteps: nil,
                    note: "Running Claude Code sessions pick this up when they restart.")
    }

    // MARK: Codex

    private static func codexConnect() -> Plan {
        let file = Target.codex.configFile
        let original = readJSON(file)
        var json = removingOurHooks(from: original ?? [:])
        if json["description"] == nil { json["description"] = "Tethera agent-status hooks" }
        let events: [(String, Bool, Bool)] = [
            ("UserPromptSubmit", false, false), ("PreToolUse", true, false), ("PermissionRequest", true, false),
            ("Stop", false, false), ("Interrupt", false, false), ("SessionStart", false, false),
        ]
        json["hooks"] = addingHooks(to: json["hooks"] as? [String: Any], events: events, command: command("hook codex"))
        return Plan(changes: [.init(file: file, before: render(original), after: render(json))], sideFiles: [:], manualSteps: nil,
                    note: "Codex runs new hooks only after you trust them: open /hooks in Codex once and trust Tethera's entries.")
    }

    // MARK: Antigravity

    static var antigravitySettings: URL { configHome.appendingPathComponent(".gemini/antigravity-cli/settings.json") }

    private static func antigravityConnect() -> Plan {
        let hooksFile = Target.antigravity.configFile
        let original = readJSON(hooksFile)
        var hooks = original ?? [:]
        func handler(_ event: String) -> [String: Any] {
            ["type": "command", "command": command("hook agy \(event)"), "timeout": 5]
        }
        hooks["tethera"] = [
            "SessionStart": [handler("SessionStart")],
            "PreInvocation": [handler("PreInvocation")],
            "PreToolUse": [["matcher": "*", "hooks": [handler("PreToolUse")]]],
            "PostToolUse": [["matcher": "*", "hooks": [handler("PostToolUse")]]],
            "Stop": [handler("Stop")],
        ] as [String: Any]
        var changes = [Plan.Change(file: hooksFile, before: render(original), after: render(hooks))]

        // The title command runs on every state change, including "waiting for your confirmation".
        let settingsOriginal = readJSON(antigravitySettings)
        var settings = settingsOriginal ?? [:]
        if settings["title"] == nil || isOurs((settings["title"] as? [String: Any])?["command"] as? String ?? "") {
            settings["title"] = ["type": "command", "command": command("title agy")] as [String: Any]
            changes.append(.init(file: antigravitySettings, before: render(settingsOriginal), after: render(settings)))
        }
        return Plan(changes: changes, sideFiles: [:], manualSteps: nil, note: "New agy sessions pick this up.")
    }

    // MARK: Hermes (YAML: appended between markers, never rewritten)

    static let hermesBegin = "# >>> tethera hooks (managed by Tethera; Disconnect removes this block) >>>"
    static let hermesEnd = "# <<< tethera hooks <<<"

    static var hermesEntries: [String] {
        let events = ["pre_llm_call", "pre_tool_call", "post_tool_call", "pre_approval_request", "on_session_end"]
        return events.flatMap { ["  \($0):", "    - command: \"\(command("hook hermes"))\"", "      timeout: 5"] }
    }

    static var hermesBlock: String {
        ([hermesBegin, "hooks:"] + hermesEntries + [hermesEnd]).joined(separator: "\n") + "\n"
    }

    private static func hermesConnect() -> Plan {
        let file = Target.hermes.configFile
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let cleaned = removingHermesBlock(text)
        let note = "Hermes asks once before running a new hook: approve Tethera's hooks the next time you run hermes (or with hermes hooks)."
        if cleaned.split(separator: "\n").contains(where: { $0.hasPrefix("hooks:") }) {
            return Plan(changes: [], sideFiles: [:],
                        manualSteps: "Your config.yaml already has a hooks: section. Add these entries under it:\n\n" + hermesEntries.joined(separator: "\n"),
                        note: note)
        }
        let separator = cleaned.isEmpty || cleaned.hasSuffix("\n\n") ? "" : (cleaned.hasSuffix("\n") ? "\n" : "\n\n")
        return Plan(changes: [.init(file: file, before: text, after: cleaned + separator + hermesBlock)], sideFiles: [:], manualSteps: nil, note: note)
    }

    static func removingHermesBlock(_ text: String) -> String {
        guard let start = text.range(of: hermesBegin),
              let end = text.range(of: hermesEnd, range: start.upperBound..<text.endIndex) else { return text }
        var tail = text[end.upperBound...]
        if tail.hasPrefix("\n") { tail = tail.dropFirst() }
        var head = String(text[..<start.lowerBound])
        while head.hasSuffix("\n\n") { head.removeLast() }
        return head + tail
    }

    // MARK: OpenCode (a plugin file Tethera owns)

    static var openCodePlugin: String {
        """
        // Managed by Tethera: reports this OpenCode session's state to the Tethera sidebar.
        // Disconnect in Tethera's Settings removes this file.
        const TETHERA = "\(cliLink.path)"
        const WATCH = new Set([
          "session.status", "session.idle", "session.error",
          "permission.asked", "permission.updated", "permission.replied",
          "question.asked", "question.replied", "question.rejected",
        ])

        function send(payload) {
          if (!process.env.TETHERA_SESSION_ID) return
          try {
            Bun.spawn([TETHERA, "hook", "opencode"], {
              stdin: new Blob([JSON.stringify(payload)]),
              stdout: "ignore",
              stderr: "ignore",
            })
          } catch {}
        }

        export const TetheraPlugin = async () => ({
          event: async ({ event }) => {
            if (WATCH.has(event.type)) send({ type: event.type, properties: event.properties })
          },
          "tool.execute.before": async (input) => {
            send({ type: "tool.execute.before", tool: input.tool })
          },
        })

        """
    }

    private static func openCodeConnect() -> Plan {
        let file = Target.opencode.configFile
        let before = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        return Plan(changes: [.init(file: file, before: before, after: openCodePlugin)], sideFiles: [:], manualSteps: nil,
                    note: "New OpenCode sessions load the plugin.")
    }

    // MARK: Writing

    /// Writes the plan, keeping a timestamped backup of each previous file next to it.
    public static func apply(_ plan: Plan) throws {
        let fm = FileManager.default
        for change in plan.changes where change.before != (change.after ?? "") {
            try fm.createDirectory(at: change.file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: change.file.path) {
                try backup(change.file)
            }
            if let after = change.after {
                try Data(after.utf8).write(to: change.file, options: .atomic)
            } else {
                try? fm.removeItem(at: change.file)
            }
        }
        for (url, data) in plan.sideFiles {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
    }

    private static func backup(_ file: URL) throws {
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let directory = file.deletingLastPathComponent()
        var target = directory.appendingPathComponent("\(file.lastPathComponent).tethera-backup-\(stamp)")
        var counter = 2
        while fm.fileExists(atPath: target.path) {
            target = directory.appendingPathComponent("\(file.lastPathComponent).tethera-backup-\(stamp)-\(counter)")
            counter += 1
        }
        try fm.copyItem(at: file, to: target)
    }

    /// Points the stable CLI link at this build's `tethera` binary. Never replaces a file that
    /// isn't Tethera's own link.
    public static func refreshCLILink(to executable: String) {
        let fm = FileManager.default
        let link = cliLink.path
        if let current = try? fm.destinationOfSymbolicLink(atPath: link) {
            if current == executable { return }
            guard current.contains("ethera") else { return }
            try? fm.removeItem(atPath: link)
        } else if fm.fileExists(atPath: link) {
            return
        }
        try? fm.createDirectory(at: cliLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.createSymbolicLink(atPath: link, withDestinationPath: executable)
    }

    // MARK: JSON helpers

    private static func addingHooks(to hooks: [String: Any]?, events: [(name: String, toolMatcher: Bool, async: Bool)], command: String) -> [String: Any] {
        var hooks = hooks ?? [:]
        for event in events {
            var handler: [String: Any] = ["type": "command", "command": command, "timeout": 5]
            if event.async { handler["async"] = true }
            var group: [String: Any] = ["hooks": [handler]]
            if event.toolMatcher { group["matcher"] = "*" }
            hooks[event.name] = (hooks[event.name] as? [[String: Any]] ?? []) + [group]
        }
        return hooks
    }

    static func removingOurHooks(from json: [String: Any]) -> [String: Any] {
        var json = json
        guard var hooks = json["hooks"] as? [String: Any] else { return json }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let cleaned: [[String: Any]] = groups.compactMap { group in
                var group = group
                let entries = (group["hooks"] as? [[String: Any]] ?? []).filter { !isOurs($0["command"] as? String ?? "") }
                guard !entries.isEmpty else { return nil }
                group["hooks"] = entries
                return group
            }
            if cleaned.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = cleaned }
        }
        if hooks.isEmpty { json.removeValue(forKey: "hooks") } else { json["hooks"] = hooks }
        if json["description"] as? String == "Tethera agent-status hooks" && json["hooks"] == nil {
            json.removeValue(forKey: "description")
        }
        return json
    }

    static func readJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func render(_ json: [String: Any]?) -> String {
        guard let json else { return "" }
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return "" }
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
