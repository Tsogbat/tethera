import XCTest
@testable import Tethera

final class CompletionTests: XCTestCase {
    private let promptMark = Data("\u{1b}]133;A\u{07}".utf8)
    private let commandMark = Data("\u{1b}]133;C\u{07}".utf8)

    func testPromptLineFollowsMarksAndKeys() {
        var line = PromptLine()
        XCTAssertNil(line.text, "unknown until a prompt appears")
        _ = line.input(Data("ls".utf8))
        XCTAssertNil(line.text)
        line.output(Data("output".utf8) + promptMark + Data("❯ ".utf8))
        XCTAssertEqual(line.text, "")
        _ = line.input(Data("git pux".utf8))
        _ = line.input(Data([0x7F]))
        XCTAssertEqual(line.text, "git pu")
        _ = line.input(Data([0x17]))
        XCTAssertEqual(line.text, "git ", "⌃W deletes a word")
        _ = line.input(Data("status".utf8))
        XCTAssertEqual(line.input(Data("\r".utf8)), "git status")
        XCTAssertNil(line.text, "running")
        line.output(commandMark)
        XCTAssertNil(line.text)
        line.output(promptMark)
        _ = line.input(Data("vim".utf8))
        _ = line.input(Data("\u{1b}[D".utf8))
        XCTAssertNil(line.text, "an arrow key edits in ways this doesn't follow")
    }

    func testPromptMarkSplitAcrossChunks() {
        var line = PromptLine()
        let mark = Array(promptMark)
        line.output(Data(mark[0..<3]))
        XCTAssertNil(line.text)
        line.output(Data(mark[3...]))
        XCTAssertEqual(line.text, "")
    }

    func testZshExtendedHistoryWithMetaBytes() {
        // "Ã" is 0xC3 0x83; zsh writes its reserved byte 0x83 as 0x83 then 0x83 ^ 0x20.
        var data = Data(": 1700000000:0;git push\n: 1700000001:0;echo caf".utf8)
        data += Data([0xC3, 0x83, 0xA3])
        data += Data("\n: 1700000002:0;for x in 1 2\\\ndo echo $x; done\nnpm test\n".utf8)
        let commands = CompletionEngine.zshHistory(data)
        XCTAssertEqual(commands, ["git push", "echo cafÃ", "npm test"], "multi-line commands are skipped")
    }

    @MainActor
    func testGhostIsTheNewestMatchingHistory() {
        let engine = CompletionEngine()
        engine.loadHistoryIfNeeded()
        engine.remember("git pull --rebase")
        engine.remember("git push origin main")
        XCTAssertEqual(engine.ghost(for: "git pu"), "sh origin main")
        XCTAssertNil(engine.ghost(for: "git push origin main"), "nothing to add")
        XCTAssertNil(engine.ghost(for: ""))
    }

    @MainActor
    func testCandidatesFromScriptsTargetsBranchesSpecsAndFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tethera-complete-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("src"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(#"{"scripts":{"dev":"vite","build":"vite build"}}"#.utf8).write(to: folder.appendingPathComponent("package.json"))
        try Data("build:\n\tswift build\ntest: build\n\tswift test\nVAR := 1\n.PHONY: test\n".utf8).write(to: folder.appendingPathComponent("Makefile"))
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(".git/refs/heads/feature"), withIntermediateDirectories: true)
        try Data("abc\n".utf8).write(to: folder.appendingPathComponent(".git/refs/heads/main"))
        try Data("abc\n".utf8).write(to: folder.appendingPathComponent(".git/refs/heads/feature/login"))
        try Data("# pack-refs\nabc refs/heads/old-release\n".utf8).write(to: folder.appendingPathComponent(".git/packed-refs"))

        let engine = CompletionEngine()
        func texts(_ line: String) -> [String] { engine.candidates(for: line, cwd: folder.path).items.map(\.text) }
        XCTAssertEqual(texts("npm run "), ["build", "dev"])
        XCTAssertEqual(texts("npm run d"), ["dev"])
        XCTAssertEqual(texts("make "), ["build", "test"])
        XCTAssertEqual(Set(texts("git checkout ").prefix(3)), ["feature/login", "main", "old-release"])
        XCTAssertTrue(texts("git ").contains("push"))
        XCTAssertTrue(texts("git commit --").contains("--amend"))
        XCTAssertEqual(texts("cat sr"), ["src/"], "folders end in a slash")
        XCTAssertTrue(texts("cat ").contains("package.json"))
        XCTAssertFalse(texts("cat ").contains(".git/"), "hidden files only when asked for")
    }
}
