import XCTest
@testable import TetheraDaemon
@testable import TetheraKit

final class HookMapperTests: XCTestCase {
    private func map(_ source: String, _ json: String) -> AgentUpdate? {
        HookMapper.update(source: source, payload: Data(json.utf8))
    }

    func testClaudeEvents() {
        let permission = map("claude", #"{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}"#)
        XCTAssertEqual(permission?.state, .needsInput)
        XCTAssertEqual(permission?.reason, "permission")
        XCTAssertEqual(permission?.message, "Allow Bash: rm -rf build?")

        XCTAssertEqual(map("claude", #"{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"/x/Package.swift"}}"#)?.tool, "Edit Package.swift")
        XCTAssertEqual(map("claude", #"{"hook_event_name":"UserPromptSubmit","prompt":"fix the build"}"#)?.state, .working)
        let stop = map("claude", #"{"hook_event_name":"Stop","last_assistant_message":"All tests pass."}"#)
        XCTAssertEqual(stop?.state, .done)
        XCTAssertEqual(stop?.message, "All tests pass.")
        XCTAssertEqual(map("claude", #"{"hook_event_name":"Notification","notification_type":"idle_prompt","message":"waiting"}"#)?.state, .idle)
        XCTAssertEqual(map("claude", #"{"hook_event_name":"Notification","notification_type":"elicitation_dialog"}"#)?.reason, "question")
        XCTAssertEqual(map("claude", #"{"hook_event_name":"StopFailure","error":"rate_limit"}"#)?.state, .error)
        XCTAssertNil(map("claude", #"{"hook_event_name":"SubagentStop"}"#))
        XCTAssertNil(map("claude", "not json"))
    }

    func testStatusLinesCarryMetricsNotState() {
        let line = map("claude-statusline", #"{"model":{"id":"x","display_name":"Opus 5.5"},"context_window":{"used_percentage":42.5},"cost":{"total_cost_usd":0.31}}"#)
        XCTAssertNil(line?.state)
        XCTAssertEqual(line?.model, "Opus 5.5")
        XCTAssertEqual(line?.contextPercent, 42.5)
        XCTAssertEqual(line?.costUSD, 0.31)

        let agy = map("agy-status", #"{"agent_state":"tool_use","tool_confirmation_pending":true,"cost":{"total_usd":1.5}}"#)
        XCTAssertEqual(agy?.state, .needsInput)
        XCTAssertEqual(agy?.costUSD, 1.5)
    }

    func testOtherAgents() {
        XCTAssertEqual(map("codex", #"{"hook_event_name":"PermissionRequest","tool_name":"shell","tool_input":{"command":["git","push"]}}"#)?.message, "Allow shell: git push?")
        XCTAssertEqual(map("codex-notify", #"{"type":"agent-turn-complete","last-assistant-message":"Done."}"#)?.state, .done)
        XCTAssertEqual(map("hermes", #"{"hook_event_name":"on_session_end","extra":{"failed":true}}"#)?.state, .error)
        XCTAssertEqual(map("hermes", #"{"hook_event_name":"pre_tool_call","tool_name":"terminal","tool_input":{"command":"ls"}}"#)?.tool, "terminal: ls")
        let ask = map("opencode", #"{"type":"permission.asked","properties":{"permission":"bash","patterns":["npm test"]}}"#)
        XCTAssertEqual(ask?.state, .needsInput)
        XCTAssertEqual(ask?.message, "Allow bash npm test?")
        XCTAssertEqual(map("opencode", #"{"type":"session.status","properties":{"status":{"type":"busy"}}}"#)?.state, .working)
        XCTAssertEqual(map("opencode", #"{"type":"session.status","properties":{"status":{"type":"idle"}}}"#)?.state, .done)
        XCTAssertEqual(map("agy", #"{"hook_event_name":"PreToolUse","toolCall":{"name":"run_command"}}"#)?.tool, "run_command")
        XCTAssertEqual(map("hermes", #"{"hook_event_name":"pre_approval_request","extra":{"command":"rm -rf dist"}}"#)?.message, "Allow rm -rf dist?")
        XCTAssertNil(map("claude", #"{"hook_event_name":"PostToolUse","tool_name":"Bash"}"#), "a late PostToolUse must not undo Stop")
        XCTAssertEqual(map("agy", #"{"hookEventName":"Stop","error":"quota"}"#)?.state, .error)
    }
}

final class AgentIntegrationsTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("tethera-config-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        setenv("TETHERA_CONFIG_HOME", home.path, 1)
        setenv("TETHERA_HOME", home.appendingPathComponent("tethera").path, 1)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home)
        unsetenv("TETHERA_CONFIG_HOME")
        unsetenv("TETHERA_HOME")
    }

    private func json(_ url: URL) -> NSDictionary? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? NSDictionary
    }

    func testClaudeConnectPreservesUserConfigAndDisconnectRestoresIt() throws {
        let settings = home.appendingPathComponent(".claude/settings.json")
        let original = """
        {"model":"opus","theme":"dark",
         "statusLine":{"type":"command","command":"~/.claude/statusline/statusline.sh","padding":0},
         "hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"~/guard.sh"}]}]}}
        """
        try Data(original.utf8).write(to: settings)
        let before = json(settings)

        let plan = AgentIntegrations.connectPlan(.claude, wrapStatusLine: true)
        XCTAssertTrue(plan.hasChanges)
        try AgentIntegrations.apply(plan)
        XCTAssertTrue(AgentIntegrations.isConnected(.claude))
        XCTAssertTrue(AgentIntegrations.isStatusLineConnected())

        let connected = try XCTUnwrap(json(settings) as? [String: Any])
        XCTAssertEqual(connected["model"] as? String, "opus")
        let hooks = try XCTUnwrap(connected["hooks"] as? [String: Any])
        let preTool = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(preTool.count, 2, "the user's own hook stays")
        XCTAssertEqual((preTool[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String, "~/guard.sh")
        XCTAssertNotNil(hooks["PermissionRequest"])
        let backups = try FileManager.default.contentsOfDirectory(atPath: settings.deletingLastPathComponent().path)
            .filter { $0.hasPrefix("settings.json.tethera-backup-") }
        XCTAssertGreaterThanOrEqual(backups.count, 1)

        // Connecting again doesn't duplicate entries.
        try AgentIntegrations.apply(AgentIntegrations.connectPlan(.claude, wrapStatusLine: true))
        let again = try XCTUnwrap((json(settings)?["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(again.count, 2)

        try AgentIntegrations.apply(AgentIntegrations.disconnectPlan(.claude))
        XCTAssertFalse(AgentIntegrations.isConnected(.claude))
        XCTAssertEqual(json(settings), before, "disconnect restores the original config exactly")
    }

    func testAntigravityHermesAndOpenCodeRoundTrip() throws {
        // Antigravity: a "tethera" definition in hooks.json plus a title command, both removable.
        try AgentIntegrations.apply(AgentIntegrations.connectPlan(.antigravity))
        XCTAssertTrue(AgentIntegrations.isConnected(.antigravity))
        let hooks = try XCTUnwrap(json(home.appendingPathComponent(".gemini/config/hooks.json"))?["tethera"] as? [String: Any])
        XCTAssertNotNil(hooks["PreToolUse"])
        XCTAssertTrue(((json(home.appendingPathComponent(".gemini/antigravity-cli/settings.json"))?["title"] as? [String: Any])?["command"] as? String ?? "").hasSuffix("title agy"))
        try AgentIntegrations.apply(AgentIntegrations.disconnectPlan(.antigravity))
        XCTAssertFalse(AgentIntegrations.isConnected(.antigravity))

        // Hermes: a marked block appended to config.yaml, removed exactly.
        let config = home.appendingPathComponent(".hermes/config.yaml")
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        let yaml = "model: hermes-4\nproviders:\n  default: nous\n"
        try yaml.write(to: config, atomically: true, encoding: .utf8)
        try AgentIntegrations.apply(AgentIntegrations.connectPlan(.hermes))
        let connected = try String(contentsOf: config, encoding: .utf8)
        XCTAssertTrue(connected.hasPrefix(yaml))
        XCTAssertTrue(connected.contains("pre_tool_call:"))
        try AgentIntegrations.apply(AgentIntegrations.disconnectPlan(.hermes))
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), yaml)

        // An existing hooks: section is never edited; the user gets the lines to add instead.
        try (yaml + "hooks:\n  on_session_start:\n    - command: \"echo hi\"\n").write(to: config, atomically: true, encoding: .utf8)
        let manual = AgentIntegrations.connectPlan(.hermes)
        XCTAssertFalse(manual.hasChanges)
        XCTAssertNotNil(manual.manualSteps)

        // OpenCode: a plugin file Tethera owns.
        try AgentIntegrations.apply(AgentIntegrations.connectPlan(.opencode))
        let plugin = try String(contentsOf: home.appendingPathComponent(".config/opencode/plugins/tethera.js"), encoding: .utf8)
        XCTAssertTrue(plugin.contains("export const TetheraPlugin"))
        try AgentIntegrations.apply(AgentIntegrations.disconnectPlan(.opencode))
        XCTAssertFalse(AgentIntegrations.isConnected(.opencode))
    }

    func testCodexConnectCreatesHooksFile() throws {
        try AgentIntegrations.apply(AgentIntegrations.connectPlan(.codex))
        let file = home.appendingPathComponent(".codex/hooks.json")
        XCTAssertTrue(AgentIntegrations.isConnected(.codex))
        let stop = try XCTUnwrap(((json(file)?["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.first)
        XCTAssertTrue(((stop["hooks"] as? [[String: Any]])?.first?["command"] as? String ?? "").hasSuffix("hook codex"))
        try AgentIntegrations.apply(AgentIntegrations.disconnectPlan(.codex))
        XCTAssertFalse(AgentIntegrations.isConnected(.codex))
    }
}
