import XCTest
@testable import Tethera

final class AgentParsingTests: XCTestCase {
    private func parse(_ format: AgentOutputFormat, _ lines: [String]) -> AgentOutputParser {
        var parser = AgentOutputParser(format: format)
        for line in lines { _ = parser.consume(line: line) }
        return parser
    }

    func testClaudeStreamDeltas() {
        let parser = parse(.claudeStreamJSON, [
            #"{"type":"system","subtype":"init","session_id":"x"}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"ls "}}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"-la"}}}"#,
            #"{"type":"assistant","message":{"id":"m1","content":[{"type":"text","text":"ls -la"}]}}"#,
            #"{"type":"result","subtype":"success","is_error":false,"result":"ls -la"}"#,
        ])
        XCTAssertEqual(parser.finalText, "ls -la")
        XCTAssertNil(parser.errorMessage)
    }

    func testClaudeError() {
        let parser = parse(.claudeStreamJSON, [
            #"{"type":"result","subtype":"success","is_error":true,"result":"Invalid API key · Please run /login"}"#,
        ])
        XCTAssertEqual(parser.errorMessage, "Invalid API key · Please run /login")
    }

    func testCodexAgentMessages() {
        let parser = parse(.codexJSON, [
            #"{"type":"thread.started","thread_id":"t"}"#,
            #"{"type":"item.completed","item":{"id":"item_0","type":"reasoning","text":"thinking"}}"#,
            #"{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"git status"}}"#,
            #"{"type":"turn.completed","usage":{}}"#,
        ])
        XCTAssertEqual(parser.finalText, "git status")
    }

    func testCodexFailure() {
        let parser = parse(.codexJSON, [#"{"type":"turn.failed","error":{"message":"You've hit your usage limit"}}"#])
        XCTAssertEqual(parser.errorMessage, "You've hit your usage limit")
    }

    func testOpenCodeTextParts() {
        let parser = parse(.opencodeJSON, [
            #"{"type":"step_start","part":{"id":"s","type":"step-start"}}"#,
            #"{"type":"text","part":{"id":"p1","type":"text","text":"Use"}}"#,
            #"{"type":"text","part":{"id":"p1","type":"text","text":"Use `du -sh *`"}}"#,
            "INFO some log line",
        ])
        XCTAssertEqual(parser.finalText, "Use `du -sh *`")
    }

    func testOpenCodeError() {
        let parser = parse(.opencodeJSON, [#"{"type":"error","error":{"name":"ProviderAuthError","data":{"message":"Not authenticated"}}}"#])
        XCTAssertEqual(parser.errorMessage, "Not authenticated")
    }

    func testGeminiDeltas() {
        let parser = parse(.geminiStreamJSON, [
            #"{"type":"init","session_id":"g"}"#,
            #"{"type":"message","role":"user","content":"hi"}"#,
            #"{"type":"message","role":"assistant","content":"Hel","delta":true}"#,
            #"{"type":"message","role":"assistant","content":"lo","delta":true}"#,
            #"{"type":"result","status":"success"}"#,
        ])
        XCTAssertEqual(parser.finalText, "Hello")
    }

    func testPlainOutputStripsANSIAndSpinners() {
        var parser = AgentOutputParser(format: .plain)
        parser.appendPlain("\u{1b}[?25l⠋ \r⠙ \r\u{1b}[32mfind . -name '*.swift'\u{1b}[0m\n")
        XCTAssertEqual(parser.text.trimmingCharacters(in: .whitespacesAndNewlines), "find . -name '*.swift'")
    }

    func testNonJSONFallback() {
        let parser = parse(.codexJSON, ["plain answer from an older CLI"])
        XCTAssertEqual(parser.finalText, "plain answer from an older CLI")
    }

    func testFailureClassification() {
        XCTAssertEqual(AgentRunnerTestHooks.classify("Error: Not logged in. Run claude /login").kind, .notSignedIn)
        XCTAssertEqual(AgentRunnerTestHooks.classify("429 Too Many Requests").kind, .rateLimited)
        XCTAssertEqual(AgentRunnerTestHooks.classify("segfault").kind, .failed)
    }
}

/// Small shim so tests can reach the private classifier through a public path.
enum AgentRunnerTestHooks {
    static func classify(_ text: String) -> AgentFailure {
        AgentRunner.classify(text, status: 1, provider: .claude)
    }
}

final class CommandSanitizerTests: XCTestCase {
    func testPlainCommand() {
        XCTAssertEqual(CommandSanitizer.command(from: "ls -la"), "ls -la")
    }

    func testFencedCommand() {
        XCTAssertEqual(CommandSanitizer.command(from: "Here you go:\n```bash\nfind . -name '*.swift' | xargs grep -n Renderer\n```"),
                       "find . -name '*.swift' | xargs grep -n Renderer")
    }

    func testPromptMarkerAndBackticks() {
        XCTAssertEqual(CommandSanitizer.command(from: "$ git status"), "git status")
        XCTAssertEqual(CommandSanitizer.command(from: "`brew install jq`"), "brew install jq")
    }

    func testNone() {
        XCTAssertNil(CommandSanitizer.command(from: "NONE"))
        XCTAssertNil(CommandSanitizer.command(from: "   "))
    }

    func testContinuationLines() {
        XCTAssertEqual(CommandSanitizer.command(from: "docker run \\\n  -it ubuntu"), "docker run \\\n-it ubuntu")
    }

    func testCodeBlocks() {
        let blocks = CommandSanitizer.codeBlocks(in: "a\n```sh\necho 1\n```\ntext\n```python\nprint(2)\n```")
        XCTAssertEqual(blocks, [.init(language: "sh", code: "echo 1"), .init(language: "python", code: "print(2)")])
    }
}

final class CommandParsingTests: XCTestCase {
    func testProgramName() {
        XCTAssertEqual(CommandLineParser.programName(of: "sudo -E FOO=1 vim file"), "vim")
        XCTAssertEqual(CommandLineParser.programName(of: "FOO=bar npx claude"), "claude")
        XCTAssertEqual(CommandLineParser.programName(of: "/opt/homebrew/bin/codex"), "codex")
    }

    func testInteractiveDetection() {
        XCTAssertTrue(InteractivePrograms.isInteractive("claude"))
        XCTAssertTrue(InteractivePrograms.isInteractive("codex 'fix the build'"))
        XCTAssertFalse(InteractivePrograms.isInteractive("claude -p 'hi'"))
        XCTAssertFalse(InteractivePrograms.isInteractive("codex exec 'hi'"))
        XCTAssertFalse(InteractivePrograms.isInteractive("opencode run 'hi'"))
        XCTAssertTrue(InteractivePrograms.isInteractive("opencode"))
        XCTAssertTrue(InteractivePrograms.isInteractive("vim README.md"))
        XCTAssertTrue(InteractivePrograms.isInteractive("python3"))
        XCTAssertFalse(InteractivePrograms.isInteractive("python3 script.py"))
        XCTAssertTrue(InteractivePrograms.isInteractive("ollama run llama3.2"))
        XCTAssertFalse(InteractivePrograms.isInteractive("ollama list"))
        XCTAssertFalse(InteractivePrograms.isInteractive("ls -la"))
        XCTAssertTrue(InteractivePrograms.isInteractive("ssh host"))
        XCTAssertFalse(InteractivePrograms.isInteractive("ssh host uptime"))
    }

    func testInteractiveCommandQuoting() {
        XCTAssertEqual(AgentCLI.claude.interactiveCommand(prompt: "it's broken"), "claude 'it'\\''s broken'")
        XCTAssertEqual(AgentCLI.hermes.interactiveCommand(prompt: nil), "hermes")
    }

    func testShellHistoryParsing() {
        let text = ": 1700000000:0;git status\n: 1700000001:0;echo one \\\ntwo\nls -la\n\n"
        XCTAssertEqual(ShellHistoryReader.parse(text), ["git status", "echo one \ntwo", "ls -la"])
    }

    func testGitStatusParsing() {
        let output = "# branch.oid abc1234567\n# branch.head main\n# branch.upstream origin/main\n# branch.ab +2 -1\n1 .M N... 100644 100644 100644 a b README.md\n"
        XCTAssertEqual(GitService.parse(output), GitInfo(branch: "main", isDirty: true, ahead: 2, behind: 1))
        XCTAssertEqual(GitService.parse("# branch.oid deadbeefcafe\n# branch.head (detached)\n"),
                       GitInfo(branch: "deadbee", isDirty: false, ahead: 0, behind: 0))
    }
}
