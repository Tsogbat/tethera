import Foundation

// MARK: - Command Category

enum CommandCategory: String, Codable {
    case fileOperation = "file"
    case navigation = "navigation"
    case gitOperation = "git"
    case packageManager = "package"
    case process = "process"
    case networkOperation = "network"
    case development = "development"
    case shell = "shell"
    case media = "media"
    case agent = "agent"
    case unknown = "unknown"

    static func categorize(_ command: String) -> CommandCategory {
        let firstWord = CommandLineParser.programName(of: command)

        switch firstWord {
        case "ls", "cat", "less", "more", "rm", "cp", "mv", "mkdir", "rmdir", "touch", "find", "grep", "chmod", "chown":
            return .fileOperation
        case "cd", "pwd", "pushd", "popd":
            return .navigation
        case "git":
            return .gitOperation
        case "npm", "yarn", "pnpm", "bun", "brew", "pip", "pip3", "gem", "cargo", "apt", "yum":
            return .packageManager
        case "ps", "top", "htop", "kill", "killall", "jobs", "bg", "fg", "nohup":
            return .process
        case "curl", "wget", "ssh", "scp", "ping", "nc", "netstat":
            return .networkOperation
        case "swift", "python", "python3", "node", "ruby", "go", "make", "gcc", "clang":
            return .development
        case "echo", "export", "source", "alias", "unalias", "history", "clear", "exit":
            return .shell
        case "preview", "show":
            return .media
        default:
            return AgentCLI(programName: firstWord) != nil ? .agent : .unknown
        }
    }
}

/// Splits enough of a command line to know which program it runs.
enum CommandLineParser {
    private static let wrappers: Set<String> = ["sudo", "env", "time", "nohup", "exec", "command", "builtin", "caffeinate", "npx", "bunx", "pnpx"]

    /// The program a command line runs, skipping `VAR=value` prefixes and wrappers like `sudo`.
    static func programName(of command: String) -> String {
        let words = command.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
        for word in words {
            if word.contains("=") && !word.hasPrefix("-") && !word.hasPrefix("/") { continue }
            if word.hasPrefix("-") { continue }
            let name = (word as NSString).lastPathComponent.lowercased()
            if wrappers.contains(name) { continue }
            return name
        }
        return ""
    }
}

// MARK: - Terminal Block

struct TerminalBlock: Identifiable {
    enum Kind: Equatable {
        case command
        case ai
        case system
    }

    enum Status: Equatable {
        case running
        case finished
    }

    enum AIState: Equatable {
        case idle
        case loading
        case ready(String)
        case failed(String)
    }

    let id: UUID
    var kind: Kind
    var status: Status
    var input: String
    /// Plain output, used for copy, search and AI context.
    var output: String
    /// Styled output captured from the emulator.
    var styledOutput: StyledText?
    var timestamp: Date
    var workingDirectory: String?
    var gitBranch: String?
    var success: Bool?
    var exitCode: Int32?
    var durationMs: Int64?
    var category: CommandCategory
    var mediaFiles: [String]?
    /// Bumped whenever the output changes, so rendered caches invalidate.
    var outputVersion = 0

    // AI blocks
    var aiProvider: AgentCLI?
    var aiError: String?
    var aiHint: String?

    // Failed-command assistance
    var fix: AIState = .idle
    var explanation: AIState = .idle

    var hasMedia: Bool { !(mediaFiles ?? []).isEmpty }
    var isRunning: Bool { status == .running }
    var isFailure: Bool { kind == .command && status == .finished && success == false }
    var wasInterrupted: Bool { exitCode == 130 || exitCode == 137 || exitCode == 143 }

    /// Whether this block's output should be rendered as markdown.
    var isMarkdownContent: Bool {
        if kind == .ai { return true }
        let lower = input.lowercased()
        let mentionsMarkdown = lower.contains(".md") || lower.contains(".markdown")
        let reader = ["cat", "less", "more", "bat"].contains(CommandLineParser.programName(of: input))
        return mentionsMarkdown && reader
    }

    /// The markdown file a `cat file.md`-style command read (for inline editing).
    var markdownSourcePath: String? {
        guard kind == .command, isMarkdownContent else { return nil }
        let parts = input.split(separator: " ", maxSplits: 1)
        guard parts.count > 1 else { return nil }
        var filePath = String(parts[1]).trimmingCharacters(in: .whitespaces)
        if filePath.hasPrefix("~") {
            filePath = (filePath as NSString).expandingTildeInPath
        }
        if !filePath.hasPrefix("/"), let wd = workingDirectory {
            filePath = (wd as NSString).appendingPathComponent(filePath)
        }
        return filePath
    }

    init(
        id: UUID = UUID(),
        kind: Kind = .command,
        status: Status = .finished,
        input: String,
        output: String = "",
        styledOutput: StyledText? = nil,
        timestamp: Date = Date(),
        workingDirectory: String? = nil,
        gitBranch: String? = nil,
        success: Bool? = nil,
        exitCode: Int32? = nil,
        durationMs: Int64? = nil,
        mediaFiles: [String]? = nil,
        aiProvider: AgentCLI? = nil
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.input = input
        self.output = output
        self.styledOutput = styledOutput
        self.timestamp = timestamp
        self.workingDirectory = workingDirectory
        self.gitBranch = gitBranch
        self.success = success
        self.exitCode = exitCode
        self.durationMs = durationMs
        self.category = kind == .command ? CommandCategory.categorize(input) : .unknown
        self.mediaFiles = mediaFiles
        self.aiProvider = aiProvider
    }

    // MARK: - Display helpers

    var formattedDuration: String? {
        guard let ms = durationMs else { return nil }
        return Self.format(milliseconds: ms)
    }

    static func format(milliseconds ms: Int64) -> String {
        if ms < 1000 { return "\(ms)ms" }
        if ms < 60_000 { return String(format: "%.1fs", Double(ms) / 1000) }
        let minutes = ms / 60_000
        let seconds = (ms % 60_000) / 1000
        return "\(minutes)m \(seconds)s"
    }

    var outputLineCount: Int {
        if let styledOutput { return styledOutput.lineCount }
        return output.isEmpty ? 0 : output.split(separator: "\n", omittingEmptySubsequences: false).count
    }
}
