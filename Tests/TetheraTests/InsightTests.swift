import XCTest
@testable import Tethera
@testable import TetheraKit

final class InsightTests: XCTestCase {
    @MainActor
    func testSpendFollowsRunningTotalsAndRestarts() {
        let a = UUID(), b = UUID()
        func cost(_ session: UUID, _ value: Double) -> Journal.Event { .init(at: Date(), kind: .cost, session: session, costUSD: value) }
        let before = [cost(a, 0.50)]
        let window = [cost(a, 0.80), cost(a, 1.10), cost(b, 0.20), cost(a, 0.05)]
        let spend = Journal.spend(in: window, baseline: before)
        XCTAssertEqual(spend[a] ?? 0, 0.30 + 0.30 + 0.05, accuracy: 0.0001, "grew 0.60 from the baseline, then a new conversation spent 0.05")
        XCTAssertEqual(spend[b] ?? 0, 0.20, accuracy: 0.0001, "no baseline: its first total counts")
    }

    @MainActor
    func testAwaySummaryFromTheJournal() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("tethera-journal-\(UUID().uuidString)")
        setenv("TETHERA_HOME", home.path, 1)
        defer { unsetenv("TETHERA_HOME"); try? FileManager.default.removeItem(at: home) }
        let journal = Journal()
        let left = Date().addingTimeInterval(-3600)
        let api = UUID(), docs = UUID()
        journal.append(.init(at: left.addingTimeInterval(-60), kind: .cost, session: api, sessionName: "api", agent: "claude", costUSD: 1.0))
        journal.append(.init(at: left.addingTimeInterval(60), kind: .state, session: api, sessionName: "api", agent: "claude", state: "working"))
        journal.append(.init(at: left.addingTimeInterval(120), kind: .cost, session: api, sessionName: "api", agent: "claude", costUSD: 1.4))
        journal.append(.init(at: left.addingTimeInterval(300), kind: .state, session: api, sessionName: "api", agent: "claude", state: "done", message: "Migrated."))
        journal.append(.init(at: left.addingTimeInterval(400), kind: .state, session: docs, sessionName: "docs", agent: "codex", state: "needsInput", message: "Which DB?"))
        let summary = AwayTracker.summarize(since: left, journal: journal)
        XCTAssertEqual(summary.rows.map(\.name), ["docs", "api"], "needs you first")
        XCTAssertEqual(summary.rows.last?.outcome, "finished")
        XCTAssertEqual(summary.rows.last?.message, "Migrated.")
        XCTAssertEqual(summary.rows.last?.cost ?? 0, 0.4, accuracy: 0.0001, "spent since you left, not the whole total")
        XCTAssertEqual(summary.headline, "1 finished · 1 needs you")
    }

    func testClaudeTranscript() {
        let lines = [
            #"{"type":"user","timestamp":"2026-11-20T10:00:00.000Z","message":{"role":"user","content":"Fix the login bug"}}"#,
            #"{"type":"assistant","timestamp":"2026-11-20T10:00:05.000Z","message":{"role":"assistant","usage":{"input_tokens":1200,"cache_read_input_tokens":800,"output_tokens":90},"content":[{"type":"text","text":"Looking at auth.ts"},{"type":"tool_use","id":"t1","name":"Edit","input":{"file_path":"/x/auth.ts","old_string":"a == b","new_string":"a === b"}}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok","is_error":false}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"npm test"}}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t2","content":[{"type":"text","text":"1 failing"}],"is_error":true}]}}"#,
            #"{"type":"ai-title","title":"x"}"#,
            "not json",
        ].map { Data($0.utf8) }
        let steps = TranscriptParser.parse(lines: lines, firstID: 0)
        XCTAssertEqual(steps.map(\.kind), [.prompt, .reply, .tool, .result, .tool, .error])
        XCTAssertEqual(steps[1].inputTokens, 2000)
        XCTAssertEqual(steps[1].outputTokens, 90)
        XCTAssertEqual(steps[2].before, "a == b")
        XCTAssertEqual(steps[2].after, "a === b")
        XCTAssertEqual(steps[2].title, "Edit  auth.ts")
        XCTAssertEqual(steps[4].title, "Bash  npm test")
        XCTAssertEqual(steps[5].text, "1 failing")
    }

    func testCodexTranscript() {
        let lines = [
            #"{"type":"session_meta","payload":{"cwd":"/x"}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"add tests"}]}}"#,
            #"{"type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"{\"command\":\"swift test\"}"}}"#,
            #"{"type":"response_item","payload":{"type":"function_call_output","output":"Executed 3 tests"}}"#,
            #"{"type":"token_usage_record","payload":{"usage":{"input_tokens":500,"output_tokens":40}}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Done."}]}}"#,
        ].map { Data($0.utf8) }
        let steps = TranscriptParser.parse(lines: lines, firstID: 0)
        XCTAssertEqual(steps.map(\.kind), [.prompt, .tool, .result, .reply])
        XCTAssertEqual(steps[1].title, "shell  swift test")
        XCTAssertEqual(steps[2].outputTokens, 40)
        XCTAssertEqual(TranscriptParser.claudeProjectFolder(for: "/Users/me/my.app"), "-Users-me-my-app")
    }

    func testStatusLineFormat() {
        let values = StatusLineFormat.values(from: [
            "model": ["display_name": "Opus 5.5"], "context_window": ["used_percentage": 41.6],
            "cost": ["total_cost_usd": 0.314], "workspace": ["current_dir": "/code/api"],
        ], branch: "main")
        XCTAssertEqual(StatusLineFormat.render("{model} · {context} · {cost} · {branch}", values: values), "Opus 5.5 · 42% · $0.31 · main")
        XCTAssertEqual(StatusLineFormat.render("{model} · {missing} · {folder}", values: values), "Opus 5.5 · api")
        XCTAssertEqual(StatusLineFormat.render("{missing} · {model}", values: values), "Opus 5.5", "no dangling separator")
        XCTAssertEqual(StatusLineFormat.render("⏺ {model}!", values: values), "⏺ Opus 5.5!")
        XCTAssertEqual(StatusLineFormat.render("{missing}", values: values), "")
    }

    func testThemeImport() throws {
        let ghostty = (0..<16).map { "palette = \($0)=#\(String(format: "%02x%02x%02x", $0 * 10, $0 * 10, $0 * 10))" }.joined(separator: "\n")
            + "\nbackground = 101010\nforeground = #eeeeee\n"
        let palette = try ThemeImport.ghostty(ghostty)
        XCTAssertEqual(palette.ansi[15].hex, "#969696")
        XCTAssertEqual(palette.background.hex, "#101010")
        XCTAssertEqual(palette.foreground.hex, "#EEEEEE")
        XCTAssertThrowsError(try ThemeImport.ghostty("palette = 0=#000000"))

        var plist: [String: Any] = [:]
        for index in 0..<16 { plist["Ansi \(index) Color"] = ["Red Component": 1.0, "Green Component": 0.5, "Blue Component": 0.0] }
        plist["Background Color"] = ["Red Component": 0.0, "Green Component": 0.0, "Blue Component": 0.0]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let iTerm = try ThemeImport.iTerm(data)
        XCTAssertEqual(iTerm.ansi[3].hex, "#FF8000")
        XCTAssertEqual(iTerm.background.hex, "#000000")
    }

    func testKeyBindingDisplay() {
        XCTAssertEqual(KeyBinding("a", shift: true).display, "⇧⌘A")
        XCTAssertEqual(KeyBinding("t", option: true, control: true).display, "⌃⌥⌘T")
        XCTAssertNotNil(KeyBinding("k").shortcut)
    }
}
