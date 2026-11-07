import Foundation

/// Git repository state for a directory, read with one `git status --porcelain=v2 --branch`.
enum GitService {
    static func info(for directory: String) async -> GitInfo? {
        guard findGitDirectory(from: directory) != nil else { return nil }
        let git = await ShellEnvironment.shared.resolve("git") ?? "/usr/bin/git"
        return await Task.detached(priority: .utility) {
            compute(directory: directory, git: git)
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

    private static func compute(directory: String, git: String) -> GitInfo? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: git)
        process.arguments = ["status", "--porcelain=v2", "--branch", "--untracked-files=normal"]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        var env = ProcessInfo.processInfo.environment
        env["GIT_OPTIONAL_LOCKS"] = "0"
        env["LC_ALL"] = "C"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return parse(String(decoding: data, as: UTF8.self))
    }

    static func parse(_ output: String) -> GitInfo? {
        var branch: String?
        var oid: String?
        var ahead = 0, behind = 0
        var dirty = false
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
            } else if !line.hasPrefix("#") {
                dirty = true
            }
        }
        guard var name = branch else { return nil }
        if name == "(detached)" {
            name = String((oid ?? "detached").prefix(7))
        }
        return GitInfo(branch: name, isDirty: dirty, ahead: ahead, behind: behind)
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
