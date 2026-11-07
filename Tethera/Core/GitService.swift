import Foundation

/// Git state for a directory, read with one `git status --porcelain=v2 --branch`, plus the
/// handful of commands the Git inspector runs.
enum GitService {
    static func status(for directory: String) async -> GitStatus? {
        guard findGitDirectory(from: directory) != nil else { return nil }
        let result = await run(["status", "--porcelain=v2", "--branch", "--untracked-files=normal"], in: directory)
        guard result.ok else { return nil }
        return parse(result.output)
    }

    /// Runs git in `directory` and returns its combined output.
    static func run(_ arguments: [String], in directory: String) async -> (ok: Bool, output: String) {
        let git = await ShellEnvironment.shared.resolve("git") ?? "/usr/bin/git"
        return await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: git)
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
            var env = ProcessInfo.processInfo.environment
            env["GIT_OPTIONAL_LOCKS"] = "0"
            env["GIT_TERMINAL_PROMPT"] = "0"
            env["LC_ALL"] = "C"
            process.environment = env
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return (false, error.localizedDescription)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus == 0, String(decoding: data, as: UTF8.self))
        }.value
    }

    /// Walks up from `path` looking for `.git` (a directory, or a file for worktrees).
    static func findGitDirectory(from path: String) -> String? {
        var current = (path as NSString).standardizingPath
        let fm = FileManager.default
        while !current.isEmpty {
            let candidate = (current as NSString).appendingPathComponent(".git")
            if fm.fileExists(atPath: candidate) { return candidate }
            if current == "/" { break }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }

    static func parse(_ output: String) -> GitStatus? {
        var branch: String?
        var oid: String?
        var ahead = 0, behind = 0
        var files: [GitFile] = []
        for line in output.split(separator: "\n") {
            if line.hasPrefix("# branch.head ") {
                branch = String(line.dropFirst("# branch.head ".count))
            } else if line.hasPrefix("# branch.oid ") {
                oid = String(line.dropFirst("# branch.oid ".count))
            } else if line.hasPrefix("# branch.ab ") {
                for part in line.dropFirst("# branch.ab ".count).split(separator: " ") {
                    if part.hasPrefix("+") { ahead = Int(part.dropFirst()) ?? 0 }
                    if part.hasPrefix("-") { behind = Int(part.dropFirst()) ?? 0 }
                }
            } else if line.hasPrefix("? ") {
                files.append(GitFile(path: String(line.dropFirst(2)), staged: " ", unstaged: "?"))
            } else if line.hasPrefix("1 ") || line.hasPrefix("2 ") || line.hasPrefix("u ") {
                let fields = line.split(separator: " ", maxSplits: line.hasPrefix("1 ") ? 8 : (line.hasPrefix("2 ") ? 9 : 10))
                guard fields.count >= 2, let xy = fields[1].first.map({ ($0, fields[1].dropFirst().first ?? ".") }) else { continue }
                var path = String(fields.last ?? "")
                if line.hasPrefix("2 "), let tab = path.firstIndex(of: "\t") { path = String(path[..<tab]) }
                files.append(GitFile(path: path, staged: xy.0, unstaged: xy.1))
            }
        }
        guard var name = branch else { return nil }
        if name == "(detached)" {
            name = String((oid ?? "detached").prefix(7))
        }
        return GitStatus(info: GitInfo(branch: name, isDirty: !files.isEmpty, ahead: ahead, behind: behind), files: files)
    }
}

struct GitStatus: Equatable {
    let info: GitInfo
    let files: [GitFile]
}

struct GitFile: Equatable, Identifiable {
    let path: String
    /// Porcelain status letters: index (staged) and worktree (unstaged); `.` means unchanged.
    let staged: Character
    let unstaged: Character

    var id: String { path }
    var isStaged: Bool { staged != "." && staged != " " && staged != "?" }
    var isUntracked: Bool { unstaged == "?" }
    /// One letter for the list: the worktree change if any, otherwise the staged one.
    var letter: String {
        if isUntracked { return "U" }
        let code = unstaged != "." ? unstaged : staged
        return String(code)
    }
}

struct GitInfo: Equatable {
    let branch: String
    let isDirty: Bool
    let ahead: Int
    let behind: Int

    var aheadBehindText: String? {
        var parts: [String] = []
        if ahead > 0 { parts.append("↑\(ahead)") }
        if behind > 0 { parts.append("↓\(behind)") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
