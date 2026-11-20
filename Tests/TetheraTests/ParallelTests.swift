import XCTest
@testable import Tethera
@testable import TetheraKit

final class ParallelTests: XCTestCase {
    func testWorktreeNamesDontCollide() {
        let first = WorktreeService.plan(repoRoot: "/code/api", agent: .claude, existingBranches: [], existingPaths: [])
        XCTAssertEqual(first.branch, "tethera/claude-1")
        XCTAssertEqual(first.path, "/code/api.worktrees/claude-1")
        let next = WorktreeService.plan(repoRoot: "/code/api", agent: .claude,
                                        existingBranches: ["tethera/claude-1"], existingPaths: ["/code/api.worktrees/claude-2"])
        XCTAssertEqual(next.branch, "tethera/claude-3", "skips names taken by a branch or a folder")
        XCTAssertEqual(WorktreeService.plan(repoRoot: "/r", agent: nil, existingBranches: [], existingPaths: []).branch, "tethera/shell-1")
    }

    func testWorktreeLifecycleInARealRepository() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tethera-wt-\(UUID().uuidString)")
        let repo = base.appendingPathComponent("api").path
        try FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        for command in [["init", "-q", "-b", "main"], ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init"]] {
            let result = await GitService.run(command, in: repo)
            XCTAssertTrue(result.ok, result.output)
        }
        let info = try await WorktreeService.create(from: repo, agent: .codex)
        XCTAssertEqual(info.branch, "tethera/codex-1")
        XCTAssertEqual(info.base, "main")
        XCTAssertTrue(FileManager.default.fileExists(atPath: info.root))
        let found = await WorktreeService.info(for: info.root)
        XCTAssertEqual(found?.branch, info.branch)
        XCTAssertEqual(found?.base, "main", "the base is remembered in the repo's config")
        let mainInfo = await WorktreeService.info(for: repo)
        XCTAssertNil(mainInfo, "the main checkout isn't a worktree")

        // The agent's work, committed in the worktree, merges back into main.
        try Data("hello\n".utf8).write(to: URL(fileURLWithPath: info.root).appendingPathComponent("feature.txt"))
        _ = await GitService.run(["add", "-A"], in: info.root)
        let commit = await GitService.run(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "feature"], in: info.root)
        XCTAssertTrue(commit.ok, commit.output)
        _ = try await WorktreeService.merge(info)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo + "/feature.txt"))

        try await WorktreeService.remove(info, force: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: info.root))
        let branches = await GitService.run(["branch", "--list", info.branch], in: repo)
        XCTAssertTrue(branches.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "merged branch deleted")
    }

    func testClaudeDecisions() throws {
        let allow = try XCTUnwrap(ApprovalDecision.claude("allow"))
        let json = try JSONSerialization.jsonObject(with: Data(allow.utf8)) as? [String: Any]
        let output = json?["hookSpecificOutput"] as? [String: Any]
        XCTAssertEqual(output?["hookEventName"] as? String, "PermissionRequest")
        XCTAssertEqual((output?["decision"] as? [String: Any])?["behavior"] as? String, "allow")
        let deny = try XCTUnwrap(ApprovalDecision.claude("deny"))
        XCTAssertTrue(deny.contains(#""behavior":"deny""#) && deny.contains("message"))
        XCTAssertNil(ApprovalDecision.claude("terminal"), "answer in the terminal: print nothing")
    }

    @MainActor
    func testApprovalSummaries() {
        XCTAssertEqual(ApprovalCenter.summary(tool: "Bash", input: ["command": "rm -rf build\necho ok"]), "rm -rf build ⏎ echo ok")
        XCTAssertEqual(ApprovalCenter.summary(tool: "Edit", input: ["file_path": "/x/a.swift", "old_string": "a"]), "/x/a.swift")
        XCTAssertEqual(ApprovalCenter.summary(tool: "Custom", input: [:]), "Custom")
    }

    func testReorderingInsideARepoGroupKeepsOthersInPlace() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        // a and c are in one repo, b and d in another; move c above a.
        let result = SessionGroups.reordered([a, b, c, d], group: [a, c], from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(result, [c, b, a, d])
    }
}
