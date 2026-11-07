import SwiftUI

/// AI coding CLIs Tethera can drive with the user's existing login — no API keys.
enum AgentCLI: String, CaseIterable, Codable, Identifiable {
    case opencode
    case claude
    case codex
    case hermes
    case gemini
    case ollama

    var id: String { rawValue }

    init?(programName: String) {
        switch programName.lowercased() {
        case "opencode": self = .opencode
        case "claude": self = .claude
        case "codex": self = .codex
        case "hermes": self = .hermes
        case "gemini": self = .gemini
        case "ollama": self = .ollama
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .opencode: return "OpenCode"
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .hermes: return "Hermes"
        case .gemini: return "Gemini"
        case .ollama: return "Ollama"
        }
    }

    var binary: String { rawValue }

    var tint: Color {
        switch self {
        case .opencode: return Color(red: 0.98, green: 0.62, blue: 0.24)
        case .claude: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: return Color(red: 0.36, green: 0.80, blue: 0.62)
        case .hermes: return Color(red: 0.62, green: 0.50, blue: 1.0)
        case .gemini: return Color(red: 0.36, green: 0.58, blue: 1.0)
        case .ollama: return Color(red: 0.80, green: 0.82, blue: 0.86)
        }
    }

    var tagline: String {
        switch self {
        case .opencode: return "Free models via `opencode run`"
        case .claude: return "Your Claude login via `claude -p`"
        case .codex: return "Your ChatGPT login via `codex exec`"
        case .hermes: return "Nous Hermes Agent via `hermes -z`"
        case .gemini: return "Your Google login via `gemini`"
        case .ollama: return "Local models via `ollama run`"
        }
    }

    var defaultFastModel: String? {
        switch self {
        case .claude: return "haiku"
        case .ollama: return "llama3.2"
        default: return nil
        }
    }

    var defaultChatModel: String? {
        switch self {
        case .claude: return "sonnet"
        case .ollama: return "llama3.2"
        default: return nil
        }
    }

    /// Placeholder text for the model fields in Settings.
    var modelPlaceholder: String {
        switch self {
        case .opencode: return "opencode default (e.g. opencode/big-pickle)"
        case .claude: return "haiku · sonnet · opus"
        case .codex: return "codex default (e.g. gpt-5-codex)"
        case .hermes: return "hermes default"
        case .gemini: return "gemini default (e.g. gemini-2.5-flash)"
        case .ollama: return "llama3.2"
        }
    }

    /// Command that signs the user in, run in a new tab.
    var loginCommand: String {
        switch self {
        case .opencode: return "opencode auth login"
        case .claude: return "claude"
        case .codex: return "codex login"
        case .hermes: return "hermes setup"
        case .gemini: return "gemini"
        case .ollama: return "ollama serve"
        }
    }

    /// Interactive session command, optionally seeded with a prompt.
    func interactiveCommand(prompt: String?) -> String {
        guard let prompt, !prompt.isEmpty else {
            return self == .ollama ? "ollama run \(defaultChatModel ?? "llama3.2")" : binary
        }
        let quoted = ShellQuoting.singleQuote(prompt)
        switch self {
        case .claude, .codex, .gemini:
            return "\(binary) \(quoted)"
        case .opencode:
            return "opencode --prompt \(quoted)"
        case .hermes:
            return "hermes chat -q \(quoted)"
        case .ollama:
            return "ollama run \(defaultChatModel ?? "llama3.2") \(quoted)"
        }
    }

    var outputFormat: AgentOutputFormat {
        switch self {
        case .opencode: return .opencodeJSON
        case .claude: return .claudeStreamJSON
        case .codex: return .codexJSON
        case .gemini: return .geminiStreamJSON
        case .hermes, .ollama: return .plain
        }
    }

    /// Whether the prompt is written to stdin instead of passed as an argument.
    var readsPromptFromStdin: Bool { self == .claude }

    /// argv for a one-shot, tool-less (or read-only) request.
    func headlessArguments(prompt: String, system: String, model: String?, workingDirectory: String) -> [String] {
        let combined = system.isEmpty ? prompt : "\(system)\n\n\(prompt)"
        switch self {
        case .opencode:
            var args = ["run", "--format", "json", "--agent", "plan"]
            if let model { args += ["-m", model] }
            return args + [combined]
        case .claude:
            var args = ["-p", "--tools", "", "--output-format", "stream-json", "--verbose",
                        "--include-partial-messages", "--no-session-persistence", "--strict-mcp-config"]
            if !system.isEmpty { args += ["--system-prompt", system] }
            if let model { args += ["--model", model] }
            return args
        case .codex:
            var args = ["exec", "--json", "--ephemeral", "--skip-git-repo-check", "-s", "read-only",
                        "--color", "never", "-C", workingDirectory]
            if let model { args += ["-m", model] }
            return args + [combined]
        case .hermes:
            var args = ["-z", combined, "--ignore-rules"]
            if let model { args += ["-m", model] }
            return args
        case .gemini:
            var args = ["-o", "stream-json"]
            if let model { args += ["-m", model] }
            return args + [combined]
        case .ollama:
            return ["run", model ?? "llama3.2", combined]
        }
    }
}

enum AgentOutputFormat {
    case opencodeJSON
    case claudeStreamJSON
    case codexJSON
    case geminiStreamJSON
    case plain
}

/// Programs that need a real screen and keyboard: shown full-pane while they run.
enum InteractivePrograms {
    static let names: Set<String> = [
        "claude", "codex", "opencode", "hermes", "gemini", "ollama", "aider", "cursor-agent", "amp", "crush", "qwen", "goose",
        "vim", "vi", "nvim", "nano", "emacs", "micro", "helix", "hx",
        "htop", "top", "btop", "btm", "glances", "k9s", "lazygit", "lazydocker", "tig", "ranger", "yazi", "nnn", "mc",
        "less", "more", "man", "ssh", "mosh", "tmux", "screen", "zellij",
        "python", "python3", "ipython", "node", "irb", "ghci", "psql", "mysql", "sqlite3", "redis-cli", "mongosh",
        "watch", "fzf", "telnet", "ftp", "sftp",
    ]

    static func isInteractive(_ command: String) -> Bool {
        let program = CommandLineParser.programName(of: command)
        guard names.contains(program) else { return false }
        // `python script.py` or `node app.js` run to completion; only bare REPLs are interactive.
        let replOnly: Set<String> = ["python", "python3", "node", "irb"]
        if replOnly.contains(program) {
            let words = command.split(separator: " ").filter { !$0.hasPrefix("-") }
            return words.count <= 1
        }
        if program == "ssh" {
            // `ssh host cmd` runs a remote command; `ssh host` is a session.
            let words = command.split(separator: " ").filter { !$0.hasPrefix("-") }
            return words.count <= 2
        }
        if program == "ollama" {
            // `ollama run <model>` opens a chat; anything else is one-shot.
            let words = command.split(separator: " ").map(String.init)
            return words.count == 3 && words[1] == "run"
        }
        if AgentCLI(programName: program) != nil {
            // Agent subcommands like `codex exec` or `claude -p` are one-shot.
            let lower = " \(command.lowercased()) "
            let oneShot = [" -p ", " --print ", " exec ", " run ", " -z ", " --oneshot ", " login", " auth ", " --version", " --help", " models", " list "]
            return !oneShot.contains(where: { lower.contains($0) })
        }
        return true
    }
}

enum ShellQuoting {
    static func singleQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
