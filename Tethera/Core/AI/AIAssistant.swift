import Foundation
import OSLog

/// What the assistant is told about the terminal. Built from visible state only —
/// file contents are never read unless the user attached a block containing them.
struct AIContext {
    struct BlockSummary {
        let command: String
        let exitCode: Int32?
        let output: String
    }

    var shell: String
    var workingDirectory: String
    var gitBranch: String?
    var gitDirty: Bool = false
    var directoryListing: [String] = []
    var recentCommands: [String] = []
    var blocks: [BlockSummary] = []
    var previousExchange: (question: String, answer: String)?

    var rendered: String {
        var lines: [String] = []
        let os = ProcessInfo.processInfo.operatingSystemVersion
        lines.append("Environment: macOS \(os.majorVersion).\(os.minorVersion), shell \((shell as NSString).lastPathComponent)")
        lines.append("Working directory: \(workingDirectory)")
        if let gitBranch {
            lines.append("Git branch: \(gitBranch)\(gitDirty ? " (uncommitted changes)" : "")")
        }
        if !directoryListing.isEmpty {
            lines.append("Files here: " + directoryListing.prefix(40).joined(separator: ", "))
        }
        if !recentCommands.isEmpty {
            lines.append("Recent commands:\n" + recentCommands.map { "  $ \($0)" }.joined(separator: "\n"))
        }
        for block in blocks {
            var section = "Terminal block:\n$ \(block.command)"
            if let exit = block.exitCode { section += "\n[exit code \(exit)]" }
            if !block.output.isEmpty { section += "\n" + block.output }
            lines.append(section)
        }
        if let previous = previousExchange {
            lines.append("Previous question: \(previous.question)\nYour previous answer: \(previous.answer.prefix(1500))")
        }
        return lines.joined(separator: "\n\n")
    }

    /// Keeps the tail of long output, where errors usually are.
    static func tail(_ text: String, maxLines: Int = 60, maxCharacters: Int = 2_400) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var kept = lines.suffix(maxLines).joined(separator: "\n")
        if kept.count > maxCharacters {
            kept = "…" + String(kept.suffix(maxCharacters))
        } else if lines.count > maxLines {
            kept = "…\n" + kept
        }
        return kept
    }
}

/// High-level AI features. Every request runs the user's chosen CLI headlessly; nothing
/// the AI returns is ever executed automatically.
@MainActor
final class AIAssistant {
    static let shared = AIAssistant()
    private let logger = Logger(subsystem: "com.tethera.app", category: "AIAssistant")

    private var settings: AISettings { UserSettings.shared.aiSettings }

    private func baseSystem(shell: String) -> String {
        """
        You are the assistant built into Tethera, a macOS terminal. You run headless: you cannot use tools, \
        read files, browse, or execute anything — work only from the context provided. Be precise and brief. \
        The user's shell is \((shell as NSString).lastPathComponent) on macOS.
        """
    }

    // MARK: Command generation

    func generateCommand(_ request: String, context: AIContext) -> AsyncStream<AgentEvent> {
        let system = baseSystem(shell: context.shell) + """

        Turn the user's request into ONE shell command they can run in the working directory. \
        Reply with only the command: no explanation, no markdown, no code fences, no leading "$". \
        Join multiple steps with && or pipes. Prefer safe, read-only commands; never add sudo unless the task requires it.
        """
        let prompt = "\(context.rendered)\n\nRequest: \(request)"
        return run(system: system, prompt: prompt, role: .fast, cwd: context.workingDirectory, timeout: 90)
    }

    // MARK: Fix

    func suggestFix(command: String, exitCode: Int32?, output: String, context: AIContext) -> AsyncStream<AgentEvent> {
        let system = baseSystem(shell: context.shell) + """

        A command just failed. Reply with ONLY the single corrected command most likely to do what the user wanted — \
        no explanation, no markdown, no code fences. If the failure can't be fixed with a command, reply exactly: NONE
        """
        var ctx = context
        ctx.blocks = [AIContext.BlockSummary(command: command, exitCode: exitCode, output: AIContext.tail(output, maxLines: 40, maxCharacters: 2_000))]
        return run(system: system, prompt: ctx.rendered + "\n\nWhat should I run instead?", role: .fast, cwd: context.workingDirectory, timeout: 60)
    }

    // MARK: Explain

    func explain(command: String, exitCode: Int32?, output: String, context: AIContext) -> AsyncStream<AgentEvent> {
        let system = baseSystem(shell: context.shell) + """

        Explain the terminal block below in plain language using short Markdown (a few sentences or bullets). \
        If it failed, say why and how to fix it. Put any commands in ```sh fenced blocks.
        """
        var ctx = context
        ctx.blocks = [AIContext.BlockSummary(command: command, exitCode: exitCode, output: AIContext.tail(output, maxLines: 80, maxCharacters: 4_000))]
        return run(system: system, prompt: ctx.rendered + "\n\nExplain this block.", role: .chat, cwd: context.workingDirectory, timeout: 120)
    }

    // MARK: Ask

    func ask(_ question: String, context: AIContext) -> AsyncStream<AgentEvent> {
        let system = baseSystem(shell: context.shell) + """

        Answer the user's question about their terminal session or a shell/programming task. \
        Use concise GitHub-flavored Markdown. Put every command in a ```sh fenced block so it can be inserted with one click. \
        Never claim you ran anything.
        """
        return run(system: system, prompt: context.rendered + "\n\nQuestion: \(question)", role: .chat, cwd: context.workingDirectory, timeout: 180)
    }

    // MARK: Safety

    func destructiveWarning(for command: String) -> String? {
        guard settings.warnOnDestructiveOps else { return nil }
        let program = CommandLineParser.programName(of: command)
        let words = command.split(separator: " ").map { $0.lowercased() }
        let usesSudo = words.first == "sudo"
        guard settings.destructiveCommands.contains(program) || usesSudo else { return nil }
        switch program {
        case "rm", "rmdir":
            return words.contains(where: { $0.hasPrefix("-") && $0.contains("r") }) ? "Recursively deletes files — this can't be undone." : "Deletes files — this can't be undone."
        case "kill", "killall": return "Terminates processes."
        case "dd", "mkfs": return "Writes directly to disks."
        case "shutdown", "reboot": return "Restarts or shuts down this Mac."
        case "chmod", "chown": return "Changes file permissions or ownership."
        default: return usesSudo ? "Runs with administrator privileges." : "May have destructive effects."
        }
    }

    // MARK: Plumbing

    private func run(system: String, prompt: String, role: AISettings.Role, cwd: String, timeout: TimeInterval) -> AsyncStream<AgentEvent> {
        let provider = settings.provider
        let request = AgentRequest(provider: provider, prompt: prompt, system: system,
                                   model: settings.model(for: provider, role: role),
                                   workingDirectory: cwd, timeout: timeout)
        logger.info("AI request via \(provider.rawValue, privacy: .public)")
        return AgentRunner.stream(request)
    }
}

// MARK: - Command extraction

enum CommandSanitizer {
    /// Pulls a runnable command out of a model reply ("NONE" → nil).
    static func command(from reply: String) -> String? {
        var text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let fenced = codeBlocks(in: text).first {
            text = fenced.code
        }
        var lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        lines = lines.map(stripPromptMarker)
        guard !lines.isEmpty else { return nil }

        // Keep backslash continuations together; otherwise take the first command-looking line.
        var command: String
        if lines.count > 1 && lines.dropLast().allSatisfy({ $0.hasSuffix("\\") }) {
            command = lines.joined(separator: "\n")
        } else {
            command = lines.first(where: looksLikeCommand) ?? lines[0]
        }
        if command.hasPrefix("`") && command.hasSuffix("`") && command.count > 2 {
            command = String(command.dropFirst().dropLast())
        }
        command = command.trimmingCharacters(in: .whitespaces)
        if command.uppercased() == "NONE" || command.isEmpty { return nil }
        return command
    }

    struct CodeBlock: Equatable {
        let language: String
        let code: String
    }

    static func codeBlocks(in markdown: String) -> [CodeBlock] {
        var blocks: [CodeBlock] = []
        var inBlock = false
        var language = ""
        var buffer: [String] = []
        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inBlock {
                    blocks.append(CodeBlock(language: language, code: buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
                    buffer = []
                    inBlock = false
                } else {
                    language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces).lowercased()
                    inBlock = true
                }
            } else if inBlock {
                buffer.append(line)
            }
        }
        if inBlock && !buffer.isEmpty {
            blocks.append(CodeBlock(language: language, code: buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return blocks
    }

    static let shellLanguages: Set<String> = ["", "sh", "bash", "zsh", "shell", "console", "terminal", "fish"]

    private static func stripPromptMarker(_ line: String) -> String {
        for marker in ["$ ", "% ", "> ", "❯ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return line
    }

    private static func looksLikeCommand(_ line: String) -> Bool {
        let first = line.split(separator: " ").first.map(String.init) ?? ""
        if first.hasSuffix(":") || first.first?.isUppercase == true && line.split(separator: " ").count > 4 && line.hasSuffix(".") {
            return false
        }
        return true
    }
}
