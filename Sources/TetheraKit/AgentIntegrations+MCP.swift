import Foundation

/// Adding Tethera's browser (`tethera mcp`) to each agent as an MCP server. Same rules as
/// hooks: shown first, merged without touching anything else, backed up, reversible.
extension AgentIntegrations {
    public static let mcpName = "tethera"

    /// Which agents can get the browser, and where it's configured.
    public static func mcpConfigFile(_ target: Target) -> URL {
        let home = configHome
        switch target {
        case .claude: return home.appendingPathComponent(".claude.json")
        case .codex: return home.appendingPathComponent(".codex/config.toml")
        case .antigravity: return home.appendingPathComponent(".gemini/settings.json")
        case .hermes: return home.appendingPathComponent(".hermes/config.yaml")
        case .opencode: return home.appendingPathComponent(".config/opencode/opencode.json")
        }
    }

    public static func isMCPConnected(_ target: Target) -> Bool {
        let file = mcpConfigFile(target)
        switch target {
        case .claude, .antigravity:
            return (readJSON(file)?["mcpServers"] as? [String: Any])?[mcpName] != nil
        case .opencode:
            return (readJSON(file)?["mcp"] as? [String: Any])?[mcpName] != nil
        case .codex:
            return (try? String(contentsOf: file, encoding: .utf8))?.contains(codexMCPBegin) == true
        case .hermes:
            return (try? String(contentsOf: file, encoding: .utf8))?.contains(hermesMCPBegin) == true
        }
    }

    /// `agentExecutable` is the agent's CLI (for Claude Code, whose own `claude mcp add` keeps
    /// its state file consistent).
    public static func mcpConnectPlan(_ target: Target, agentExecutable: String? = nil) -> Plan {
        let file = mcpConfigFile(target)
        let name = target == .antigravity ? AgentKind.gemini.displayName : target.kind.displayName
        let note = "Start a new \(name) session to pick it up. The agent can then open pages beside its session, read them and click through them."
        switch target {
        case .claude:
            guard let claude = agentExecutable else {
                return Plan(changes: [], sideFiles: [:], manualSteps: "Run:\n\nclaude mcp add --scope user \(mcpName) -- \(cliLink.path) mcp", note: note)
            }
            return Plan(changes: [], sideFiles: [:], manualSteps: nil, note: note,
                        commands: [[claude, "mcp", "add", "--scope", "user", mcpName, "--", cliLink.path, "mcp"]])

        case .antigravity:
            let original = readJSON(file)
            if original == nil, FileManager.default.fileExists(atPath: file.path) { return unreadable(file, snippet: geminiSnippet, note: note) }
            var json = original ?? [:]
            var servers = json["mcpServers"] as? [String: Any] ?? [:]
            servers[mcpName] = ["command": cliLink.path, "args": ["mcp"]]
            json["mcpServers"] = servers
            return Plan(changes: [.init(file: file, before: render(original), after: render(json))], sideFiles: [:], manualSteps: nil, note: note)

        case .opencode:
            let original = readJSON(file)
            if original == nil, FileManager.default.fileExists(atPath: file.path) { return unreadable(file, snippet: openCodeSnippet, note: note) }
            var json = original ?? ["$schema": "https://opencode.ai/config.json"]
            var servers = json["mcp"] as? [String: Any] ?? [:]
            servers[mcpName] = ["type": "local", "command": [cliLink.path, "mcp"], "enabled": true]
            json["mcp"] = servers
            return Plan(changes: [.init(file: file, before: render(original), after: render(json))], sideFiles: [:], manualSteps: nil, note: note)

        case .codex:
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let cleaned = removingBlock(text, begin: codexMCPBegin, end: codexMCPEnd)
            if cleaned.contains("[mcp_servers.\(mcpName)]") {
                return Plan(changes: [], sideFiles: [:], manualSteps: "Your config.toml already has [mcp_servers.\(mcpName)].", note: nil)
            }
            return Plan(changes: [.init(file: file, before: text, after: appending(codexMCPBlock, to: cleaned))], sideFiles: [:], manualSteps: nil, note: note)

        case .hermes:
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let cleaned = removingBlock(text, begin: hermesMCPBegin, end: hermesMCPEnd)
            if cleaned.split(separator: "\n").contains(where: { $0.hasPrefix("mcp_servers:") }) {
                return Plan(changes: [], sideFiles: [:],
                            manualSteps: "Your config.yaml already has an mcp_servers: section. Add this under it:\n\n" + hermesMCPEntries.joined(separator: "\n"),
                            note: note)
            }
            return Plan(changes: [.init(file: file, before: text, after: appending(hermesMCPBlock, to: cleaned))], sideFiles: [:], manualSteps: nil, note: note)
        }
    }

    public static func mcpDisconnectPlan(_ target: Target, agentExecutable: String? = nil) -> Plan {
        let file = mcpConfigFile(target)
        switch target {
        case .claude:
            guard let claude = agentExecutable else {
                return Plan(changes: [], sideFiles: [:], manualSteps: "Run:\n\nclaude mcp remove --scope user \(mcpName)", note: nil)
            }
            return Plan(changes: [], sideFiles: [:], manualSteps: nil, note: nil, commands: [[claude, "mcp", "remove", "--scope", "user", mcpName]])
        case .antigravity, .opencode:
            guard let original = readJSON(file) else { return Plan(changes: [], sideFiles: [:], manualSteps: nil, note: nil) }
            var json = original
            let key = target == .opencode ? "mcp" : "mcpServers"
            var servers = json[key] as? [String: Any] ?? [:]
            servers.removeValue(forKey: mcpName)
            json[key] = servers.isEmpty ? nil : servers
            return Plan(changes: [.init(file: file, before: render(original), after: render(json))], sideFiles: [:], manualSteps: nil, note: nil)
        case .codex, .hermes:
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let cleaned = target == .codex
                ? removingBlock(text, begin: codexMCPBegin, end: codexMCPEnd)
                : removingBlock(text, begin: hermesMCPBegin, end: hermesMCPEnd)
            return Plan(changes: [.init(file: file, before: text, after: cleaned)], sideFiles: [:], manualSteps: nil, note: nil)
        }
    }

    // MARK: Blocks for text configs

    static let codexMCPBegin = "# >>> tethera browser (managed by Tethera; Disconnect removes this block) >>>"
    static let codexMCPEnd = "# <<< tethera browser <<<"
    static var codexMCPBlock: String {
        [codexMCPBegin, "[mcp_servers.\(mcpName)]", "command = \"\(cliLink.path)\"", "args = [\"mcp\"]", codexMCPEnd].joined(separator: "\n") + "\n"
    }

    static let hermesMCPBegin = "# >>> tethera browser (managed by Tethera; Disconnect removes this block) >>>"
    static let hermesMCPEnd = "# <<< tethera browser <<<"
    static var hermesMCPEntries: [String] {
        ["  \(mcpName):", "    command: \"\(cliLink.path)\"", "    args: [\"mcp\"]"]
    }
    static var hermesMCPBlock: String {
        ([hermesMCPBegin, "mcp_servers:"] + hermesMCPEntries + [hermesMCPEnd]).joined(separator: "\n") + "\n"
    }

    static var geminiSnippet: String {
        "\"mcpServers\": {\n  \"\(mcpName)\": { \"command\": \"\(cliLink.path)\", \"args\": [\"mcp\"] }\n}"
    }

    static var openCodeSnippet: String {
        "\"mcp\": {\n  \"\(mcpName)\": { \"type\": \"local\", \"command\": [\"\(cliLink.path)\", \"mcp\"], \"enabled\": true }\n}"
    }

    private static func unreadable(_ file: URL, snippet: String, note: String) -> Plan {
        Plan(changes: [], sideFiles: [:],
             manualSteps: "\((file.path as NSString).abbreviatingWithTildeInPath) has comments or isn't plain JSON, so Tethera won't rewrite it. Add this to it:\n\n\(snippet)",
             note: note)
    }

    static func appending(_ block: String, to text: String) -> String {
        let separator = text.isEmpty || text.hasSuffix("\n\n") ? "" : (text.hasSuffix("\n") ? "\n" : "\n\n")
        return text + separator + block
    }

    static func removingBlock(_ text: String, begin: String, end: String) -> String {
        guard let start = text.range(of: begin), let stop = text.range(of: end, range: start.upperBound..<text.endIndex) else { return text }
        var tail = text[stop.upperBound...]
        if tail.hasPrefix("\n") { tail = tail.dropFirst() }
        var head = String(text[..<start.lowerBound])
        while head.hasSuffix("\n\n") { head.removeLast() }
        return head + tail
    }
}
