import Foundation
import TetheraKit

/// Suggestions for the line being typed at a shell prompt: the rest of a command from your
/// history (ghost text), and candidates for the current word (the ⌃Space list).
@MainActor
final class CompletionEngine {
    static let shared = CompletionEngine()

    struct Candidate: Equatable, Hashable {
        enum Kind { case command, subcommand, flag, path, folder, branch, script, history }
        var text: String
        var detail: String?
        var kind: Kind
    }

    /// Newest first, no repeats.
    private(set) var history: [String] = []
    private var loadedHistory = false
    private var pathCommands: [String]?

    // MARK: History

    /// zsh's and bash's history files, then what you ran in Tethera since.
    func loadHistoryIfNeeded() {
        guard !loadedHistory else { return }
        loadedHistory = true
        // Tests and captures point this at a stand-in home, away from your real history.
        let home = AgentIntegrations.configHome.path
        var lines: [String] = []
        if let data = FileManager.default.contents(atPath: home + "/.zsh_history") { lines += Self.zshHistory(data) }
        if let text = try? String(contentsOfFile: home + "/.bash_history", encoding: .utf8) {
            lines += text.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("#") }
        }
        var seen = Set<String>()
        history = lines.reversed().filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && trimmed.count < 500 && seen.insert(trimmed).inserted
        }
        history = Array(history.prefix(10_000))
    }

    func remember(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        history.removeAll { $0 == trimmed }
        history.insert(trimmed, at: 0)
    }

    /// The rest of the most recent history entry that starts with what's typed.
    func ghost(for line: String) -> String? {
        guard !line.isEmpty, !line.hasSuffix("  ") else { return nil }
        loadHistoryIfNeeded()
        guard let match = history.first(where: { $0.count > line.count && $0.hasPrefix(line) }) else { return nil }
        return String(match.dropFirst(line.count))
    }

    /// zsh writes `: <time>:<duration>;<command>` lines (extended history) or bare commands,
    /// with non-ASCII bytes "metafied" (0x83, then the byte xor 0x20) and `\` continuing a line.
    nonisolated static func zshHistory(_ data: Data) -> [String] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(data.count)
        var meta = false
        for byte in data {
            if meta { bytes.append(byte ^ 0x20); meta = false } else if byte == 0x83 { meta = true } else { bytes.append(byte) }
        }
        var commands: [String] = []
        var pending = ""
        for raw in String(decoding: bytes, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw)
            if pending.isEmpty, line.hasPrefix(": "), let semicolon = line.firstIndex(of: ";") {
                line = String(line[line.index(after: semicolon)...])
            }
            if line.hasSuffix("\\") {
                pending += line.dropLast() + "\n"
                continue
            }
            commands.append(pending + line)
            pending = ""
        }
        // Multi-line commands don't make good one-line suggestions.
        return commands.filter { !$0.isEmpty && !$0.contains("\n") }
    }

    // MARK: Candidates

    /// What could come next for the last word of `line`, run in `cwd`.
    func candidates(for line: String, cwd: String?) -> (word: String, items: [Candidate]) {
        let words = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let word = words.last ?? ""
        let previous = words.dropLast().filter { !$0.isEmpty }
        var items: [Candidate]
        if previous.isEmpty {
            items = commands(prefix: word)
        } else {
            items = arguments(command: previous[0], before: Array(previous.dropFirst()), word: word, cwd: cwd)
        }
        items = items.filter { $0.text.hasPrefix(word) && $0.text != word }
        var seen = Set<String>()
        return (word, Array(items.filter { seen.insert($0.text).inserted }.prefix(60)))
    }

    private func commands(prefix: String) -> [Candidate] {
        loadHistoryIfNeeded()
        let recent = history.compactMap { $0.split(separator: " ").first.map(String.init) }
        var ranked: [Candidate] = []
        var seen = Set<String>()
        for name in recent where name.hasPrefix(prefix) && seen.insert(name).inserted {
            ranked.append(Candidate(text: name, detail: CompletionSpecs.all[name]?.summary, kind: .command))
            if ranked.count >= 12 { break }
        }
        for name in CompletionSpecs.all.keys.sorted() where name.hasPrefix(prefix) && seen.insert(name).inserted {
            ranked.append(Candidate(text: name, detail: CompletionSpecs.all[name]?.summary, kind: .command))
        }
        for name in pathExecutables() where name.hasPrefix(prefix) && seen.insert(name).inserted {
            ranked.append(Candidate(text: name, kind: .command))
        }
        return ranked
    }

    private func arguments(command: String, before: [String], word: String, cwd: String?) -> [Candidate] {
        let subcommand = before.first { !$0.hasPrefix("-") }
        // Words that name branches, scripts and targets.
        if command == "git", let subcommand, ["checkout", "switch", "merge", "rebase", "branch", "diff", "log", "cherry-pick", "reset"].contains(subcommand), let cwd {
            return Self.gitBranches(in: cwd).map { Candidate(text: $0, kind: .branch) } + paths(word, cwd: cwd)
        }
        if ["npm", "pnpm", "yarn", "bun"].contains(command), subcommand == "run" || (command != "npm" && subcommand == nil), let cwd {
            let scripts = Self.packageScripts(in: cwd).sorted { $0.key < $1.key }.map { Candidate(text: $0.key, detail: $0.value, kind: .script) }
            if !scripts.isEmpty, subcommand == "run" || before.isEmpty { return scripts + specItems(command, subcommand, word) }
        }
        if command == "make", let cwd {
            return Self.makeTargets(in: cwd).map { Candidate(text: $0, kind: .script) }
        }
        var items = specItems(command, before.isEmpty ? nil : subcommand, word)
        if let cwd, !word.hasPrefix("-") { items += paths(word, cwd: cwd) }
        return items
    }

    private func specItems(_ command: String, _ subcommand: String?, _ word: String) -> [Candidate] {
        guard let spec = CompletionSpecs.all[command] else { return [] }
        if word.hasPrefix("-") {
            let flags = (subcommand.flatMap { spec.subcommandFlags[$0] } ?? []) + spec.flags
            return flags.map { Candidate(text: $0.name, detail: $0.detail, kind: .flag) }
        }
        guard subcommand == nil else { return [] }
        return spec.subcommands.map { Candidate(text: $0.name, detail: $0.detail, kind: .subcommand) }
    }

    /// Files and folders for a word that may be a path; folders end in `/`.
    func paths(_ word: String, cwd: String) -> [Candidate] {
        let expanded = (word as NSString).expandingTildeInPath
        let base = expanded.hasPrefix("/") ? "" : cwd + "/"
        let folder = word.contains("/") ? String(expanded[..<(expanded.lastIndex(of: "/").map { expanded.index(after: $0) } ?? expanded.startIndex)]) : ""
        let shownFolder = word.contains("/") ? String(word[..<(word.lastIndex(of: "/").map { word.index(after: $0) } ?? word.startIndex)]) : ""
        let partial = word.contains("/") ? String(word[word.index(after: word.lastIndex(of: "/")!)...]) : word
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: base + folder) else { return [] }
        return names.filter { $0.hasPrefix(partial) && (partial.hasPrefix(".") || !$0.hasPrefix(".")) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .prefix(200)
            .map { name in
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: base + folder + name, isDirectory: &isDirectory)
                return Candidate(text: shownFolder + name + (isDirectory.boolValue ? "/" : ""), kind: isDirectory.boolValue ? .folder : .path)
            }
    }

    private func pathExecutables() -> [String] {
        if let pathCommands { return pathCommands }
        var names = Set<String>()
        let home = NSHomeDirectory()
        let directories = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
               home + "/.local/bin", home + "/.cargo/bin", home + "/.bun/bin", home + "/.npm-global/bin"]
        for directory in Set(directories) {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: String(directory))) ?? [] where !name.hasPrefix(".") {
                names.insert(name)
            }
        }
        pathCommands = names.sorted()
        return pathCommands ?? []
    }

    // MARK: Project lookups (cheap, synchronous, small)

    static func gitBranches(in cwd: String) -> [String] {
        var directory = URL(fileURLWithPath: cwd)
        while directory.path != "/" {
            let git = directory.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: git.path, isDirectory: &isDirectory) {
                var gitDir = git
                if !isDirectory.boolValue, let pointer = try? String(contentsOf: git, encoding: .utf8), pointer.hasPrefix("gitdir: ") {
                    gitDir = URL(fileURLWithPath: pointer.dropFirst(8).trimmingCharacters(in: .whitespacesAndNewlines))
                    // A worktree's refs live in the main repository.
                    if let common = try? String(contentsOf: gitDir.appendingPathComponent("commondir"), encoding: .utf8) {
                        gitDir = URL(fileURLWithPath: common.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: gitDir).standardizedFileURL
                    }
                }
                var branches = Set<String>()
                let heads = gitDir.appendingPathComponent("refs/heads")
                if let enumerator = FileManager.default.enumerator(atPath: heads.path) {
                    for case let name as String in enumerator {
                        var isFolder: ObjCBool = false
                        if FileManager.default.fileExists(atPath: heads.appendingPathComponent(name).path, isDirectory: &isFolder), !isFolder.boolValue {
                            branches.insert(name)
                        }
                    }
                }
                if let packed = try? String(contentsOf: gitDir.appendingPathComponent("packed-refs"), encoding: .utf8) {
                    for line in packed.split(separator: "\n") where line.contains(" refs/heads/") {
                        branches.insert(String(line.split(separator: " ")[1].dropFirst("refs/heads/".count)))
                    }
                }
                return branches.sorted()
            }
            directory.deleteLastPathComponent()
        }
        return []
    }

    static func packageScripts(in cwd: String) -> [String: String] {
        guard let data = FileManager.default.contents(atPath: cwd + "/package.json"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = json["scripts"] as? [String: String] else { return [:] }
        return scripts
    }

    static func makeTargets(in cwd: String) -> [String] {
        guard let text = try? String(contentsOfFile: cwd + "/Makefile", encoding: .utf8) else { return [] }
        var targets: [String] = []
        for line in text.split(separator: "\n") {
            guard let first = line.first, first != "\t", first != "#", first != ".", let colon = line.firstIndex(of: ":"),
                  !line[colon...].hasPrefix(":=") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, !name.contains(" "), !name.contains("$"), !name.contains("=") { targets.append(name) }
        }
        return targets
    }
}
