import XCTest
@testable import Tethera
@testable import TetheraKit

final class ToolsTests: XCTestCase {
    func testFileKinds() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tethera-kinds-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func file(_ name: String, _ data: Data) -> String {
            let url = directory.appendingPathComponent(name)
            try? data.write(to: url)
            return url.path
        }
        XCTAssertEqual(FileKind.of(file("a.swift", Data("let x = 1".utf8))), .text)
        XCTAssertEqual(FileKind.of(file("README.md", Data("# Hi".utf8))), .markdown)
        XCTAssertEqual(FileKind.of(file("Makefile", Data("all:\n\techo hi".utf8))), .text)
        XCTAssertEqual(FileKind.of(file("blob.bin", Data([0, 1, 2, 0, 255]))), .other)
        XCTAssertEqual(FileKind.of(file("x.png", Data())), .image)
        XCTAssertEqual(FileKind.of(file("x.pdf", Data())), .pdf)
        XCTAssertEqual(FileKind.of(file("x.mp4", Data())), .media)
    }

    func testHighlighterKeepsKeywordsInCommentsAndStringsQuiet() {
        let highlighter = SyntaxHighlighter.forFile("/x/a.swift")!
        let text = "let a = \"let\" // let\nfunc f() {}"
        var spans: [(SyntaxHighlighter.Token, String)] = []
        let full = NSRange(location: 0, length: (text as NSString).length)
        var claimed = IndexSet()
        for rule in highlighter.rules {
            rule.regex.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let range = match?.range(at: rule.group), range.length > 0 else { return }
                let span = range.location..<(range.location + range.length)
                if claimed.intersects(integersIn: span) { return }
                if rule.token == .comment || rule.token == .string { claimed.insert(integersIn: span) }
                spans.append((rule.token, (text as NSString).substring(with: range)))
            }
        }
        XCTAssertTrue(spans.contains { $0.0 == .comment && $0.1 == "// let" })
        XCTAssertTrue(spans.contains { $0.0 == .string && $0.1 == "\"let\"" })
        XCTAssertEqual(spans.filter { $0.0 == .keyword }.map(\.1), ["let", "func"])
        XCTAssertNil(SyntaxHighlighter.forFile("/x/notes.unknownext"))
    }

    func testMarkdownKeepsWordsDropsTags() {
        let source = "<p align=\"center\">\n  <img src=\"x.png\">\n</p>\n<h1 align=\"center\">Tethera</h1>\n```html\n<b>kept</b>\n```\nText<br>more"
        let stripped = MarkdownRenderer.strippingHTML(source)
        XCTAssertFalse(stripped.contains("<p"))
        XCTAssertFalse(stripped.contains("<img"))
        XCTAssertTrue(stripped.contains("Tethera"))
        XCTAssertTrue(stripped.contains("<b>kept</b>"), "code fences stay as written")
        XCTAssertTrue(stripped.contains("Text  more"))
    }

    @MainActor
    func testPreviewDetectorFindsDevServers() {
        let detector = PreviewDetector.shared
        let session = UUID()
        detector.scan(session, Data("  \u{1b}[32m➜\u{1b}[39m  Local:   \u{1b}[36mhttp://localhost:\u{1b}[1m5173\u{1b}[22m/\u{1b}[39m\n".utf8))
        XCTAssertEqual(detector.urls[session]?.absoluteString, "http://localhost:5173/")
        detector.scan(session, Data("ready - started server on 0.0.0.0:3000, url: http://0.0.0.0:3000\n".utf8))
        XCTAssertEqual(detector.urls[session]?.absoluteString, "http://localhost:3000")
        detector.scan(session, Data("compiled successfully\n".utf8))
        XCTAssertEqual(detector.urls[session]?.port, 3000)
        detector.sessionsChanged([.init(id: session, running: false)])
        XCTAssertNil(detector.urls[session])
    }

    @MainActor
    func testValidPanesKeepToolsThatStillExist() {
        let alive = UUID(), tab = UUID()
        let panes = [
            Workspace.Pane(content: .file("/exists")), Workspace.Pane(content: .file("/gone")),
            Workspace.Pane(content: .browser(tab)), Workspace.Pane(content: .browser(UUID())),
            Workspace.Pane(content: .changes(alive)), Workspace.Pane(content: .changes(UUID())),
        ]
        let kept = Workspace.validPanes(panes, sessions: [alive], tabs: [tab], fileExists: { $0 == "/exists" })
        XCTAssertEqual(kept.map(\.content), [.file("/exists"), .browser(tab), .changes(alive)])
    }
}

final class BrowserMCPTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("tethera-mcp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setenv("TETHERA_CONFIG_HOME", home.path, 1)
        setenv("TETHERA_HOME", home.appendingPathComponent("tethera").path, 1)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home)
        unsetenv("TETHERA_CONFIG_HOME")
        unsetenv("TETHERA_HOME")
    }

    /// The real `tethera mcp`, spoken to over stdio like an agent would.
    func testServerListsPlaywrightToolsAndReportsWhenTheAppIsClosed() throws {
        let cli = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("tethera-cli")
        let process = Process()
        process.executableURL = cli
        process.arguments = ["mcp"]
        process.environment = ["TETHERA_HOME": home.appendingPathComponent("tethera").path]
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        try process.run()
        let requests = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"browser_snapshot","arguments":{}}}"#,
            #"{"jsonrpc":"2.0","id":4,"method":"nope"}"#,
        ]
        stdin.fileHandleForWriting.write(Data((requests.joined(separator: "\n") + "\n").utf8))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        let lines = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n")
        let replies = lines.compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        XCTAssertEqual(replies.count, 4, "one reply per request; none for the notification")

        let initialize = replies[0]["result"] as? [String: Any]
        XCTAssertEqual(initialize?["protocolVersion"] as? String, "2025-06-18")
        XCTAssertEqual((initialize?["serverInfo"] as? [String: Any])?["name"] as? String, "tethera")

        let tools = ((replies[1]["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        XCTAssertEqual(Set(tools), ["browser_navigate", "browser_navigate_back", "browser_snapshot", "browser_click", "browser_type",
                                    "browser_press_key", "browser_wait_for", "browser_take_screenshot", "browser_evaluate", "browser_tabs"])

        let call = replies[2]["result"] as? [String: Any]
        XCTAssertEqual(call?["isError"] as? Bool, true)
        XCTAssertTrue(((call?["content"] as? [[String: Any]])?.first?["text"] as? String ?? "").contains("isn't running"))

        XCTAssertEqual((replies[3]["error"] as? [String: Any])?["code"] as? Int, -32601)
    }

    func testBrowserConfigRoundTrips() throws {
        let fm = FileManager.default
        // OpenCode: merged into the user's opencode.json, and removed again exactly.
        let openCode = AgentIntegrations.mcpConfigFile(.opencode)
        try fm.createDirectory(at: openCode.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"theme":"system","mcp":{"other":{"type":"remote","url":"https://x"}}}"#.utf8).write(to: openCode)
        try AgentIntegrations.apply(AgentIntegrations.mcpConnectPlan(.opencode))
        XCTAssertTrue(AgentIntegrations.isMCPConnected(.opencode))
        let merged = try JSONSerialization.jsonObject(with: Data(contentsOf: openCode)) as? [String: Any]
        XCTAssertEqual(merged?["theme"] as? String, "system")
        XCTAssertNotNil((merged?["mcp"] as? [String: Any])?["other"])
        try AgentIntegrations.apply(AgentIntegrations.mcpDisconnectPlan(.opencode))
        XCTAssertFalse(AgentIntegrations.isMCPConnected(.opencode))
        XCTAssertNotNil(((try JSONSerialization.jsonObject(with: Data(contentsOf: openCode)) as? [String: Any])?["mcp"] as? [String: Any])?["other"])

        // Codex: a marked TOML block appended, then removed, leaving the file as it was.
        let codex = AgentIntegrations.mcpConfigFile(.codex)
        try fm.createDirectory(at: codex.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = "model = \"gpt-5\"\n\n[mcp_servers.other]\ncommand = \"x\"\n"
        try Data(original.utf8).write(to: codex)
        try AgentIntegrations.apply(AgentIntegrations.mcpConnectPlan(.codex))
        let toml = try String(contentsOf: codex, encoding: .utf8)
        XCTAssertTrue(toml.contains("[mcp_servers.tethera]"))
        XCTAssertTrue(toml.contains(#"args = ["mcp"]"#))
        try AgentIntegrations.apply(AgentIntegrations.mcpDisconnectPlan(.codex))
        XCTAssertEqual(try String(contentsOf: codex, encoding: .utf8), original)

        // Gemini settings: mcpServers merged; a commented file is left alone with manual steps.
        let gemini = AgentIntegrations.mcpConfigFile(.antigravity)
        try fm.createDirectory(at: gemini.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("// my settings\n{\"theme\": \"x\"}".utf8).write(to: gemini)
        let refused = AgentIntegrations.mcpConnectPlan(.antigravity)
        XCTAssertTrue(refused.changes.isEmpty)
        XCTAssertNotNil(refused.manualSteps)

        // Hermes: an existing mcp_servers: section means manual steps, never a rewrite.
        let hermes = AgentIntegrations.mcpConfigFile(.hermes)
        try fm.createDirectory(at: hermes.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("model: x\nmcp_servers:\n  other:\n    command: y\n".utf8).write(to: hermes)
        XCTAssertTrue(AgentIntegrations.mcpConnectPlan(.hermes).changes.isEmpty)

        // Claude: Claude Code's own command, so its state file stays consistent.
        let claude = AgentIntegrations.mcpConnectPlan(.claude, agentExecutable: "/usr/local/bin/claude")
        XCTAssertEqual(claude.commands.first?.prefix(6), ["/usr/local/bin/claude", "mcp", "add", "--scope", "user", "tethera"])
        XCTAssertEqual(claude.commands.first?.suffix(2), [AgentIntegrations.cliLink.path, "mcp"])
    }
}
