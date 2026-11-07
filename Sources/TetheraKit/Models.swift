import Foundation

/// The protocol version both ends must speak. Bump on incompatible changes.
public let tetheraProtocolVersion = 1

/// A JSON control message. One flat shape keeps both ends simple; `type` says which fields matter.
public struct ControlMessage: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        // client → daemon
        case hello, list, create, attach, detach, resize, signal, rename, close, subscribe, hook, shutdown, reorder
        // daemon → client
        case welcome, sessions, created, attached, updated, removed, exited, error
    }

    public var type: Kind
    public var session: UUID?
    public var sessions: [SessionInfo]?
    public var info: SessionInfo?
    public var spec: SessionSpec?
    public var cols: Int?
    public var rows: Int?
    public var name: String?
    public var signal: Int32?
    public var agent: String?
    /// Raw hook JSON from an agent, forwarded by `tethera hook`.
    public var payload: String?
    public var order: [UUID]?
    public var protocolVersion: Int?
    public var pid: Int32?
    public var message: String?
    /// When a hook fired (seconds since 1970); background hooks can arrive out of order.
    public var sentAt: Double?

    public init(_ type: Kind, session: UUID? = nil) {
        self.type = type
        self.session = session
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}

/// What to start in a new session.
public struct SessionSpec: Codable, Equatable, Sendable {
    public var name: String?
    public var cwd: String?
    /// Shell executable; the user's login shell when nil.
    public var shell: String?
    /// Typed into the shell after its first prompt, e.g. `claude\r`. The session outlives it.
    public var initialInput: String?
    public var cols: Int
    public var rows: Int

    public init(name: String? = nil, cwd: String? = nil, shell: String? = nil, initialInput: String? = nil, cols: Int = 100, rows: Int = 30) {
        self.name = name
        self.cwd = cwd
        self.shell = shell
        self.initialInput = initialInput
        self.cols = cols
        self.rows = rows
    }
}

/// A session as the sidebar and overview see it.
public struct SessionInfo: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// Shown everywhere: the user's name for it, or the current folder's name.
    public var name: String
    /// Set once the user renames the session; until then the name follows the folder.
    public var customName: String?
    public var cwd: String
    public var title: String
    public var shell: String
    public var createdAt: Date
    public var lastActivity: Date
    /// False when the shell has exited or the session was restored cold after a reboot.
    public var isAlive: Bool
    public var isRestored: Bool
    public var pid: Int32?
    /// The foreground program's name, e.g. `zsh`, `claude`, `vim`.
    public var foreground: String?
    public var agent: AgentInfo?
    public var isCommandRunning: Bool
    public var lastExitCode: Int32?
    public var cols: Int
    public var rows: Int
    public var clients: Int
    public var order: Int
    /// Bumped on every bell or desktop notification (OSC 9/99/777) so clients can alert once.
    public var attention: Int
    public var lastNotification: String?

    public init(id: UUID = UUID(), name: String, cwd: String, shell: String, cols: Int, rows: Int, order: Int) {
        self.id = id
        self.name = name
        self.cwd = cwd
        self.title = ""
        self.shell = shell
        self.createdAt = Date()
        self.lastActivity = Date()
        self.isAlive = true
        self.isRestored = false
        self.isCommandRunning = false
        self.cols = cols
        self.rows = rows
        self.clients = 0
        self.order = order
        self.attention = 0
    }
}

/// An agent running in a session and what it is doing.
public struct AgentInfo: Codable, Equatable, Sendable {
    public var kind: AgentKind
    public var state: AgentState
    /// Why it is blocked: permission, question or auth.
    public var reason: String?
    /// Short status text from the agent (a permission request, the last tool, an error).
    public var message: String?
    public var since: Date
    public var model: String?
    public var contextPercent: Double?
    public var costUSD: Double?
    public var lastTool: String?
    /// Set when a turn finished while nobody was looking; cleared when a client focuses it.
    public var unseen: Bool

    public init(kind: AgentKind, state: AgentState = .idle, since: Date = Date()) {
        self.kind = kind
        self.state = state
        self.since = since
        self.unseen = false
    }
}

public enum AgentState: String, Codable, Sendable {
    case idle, working, needsInput, done, error

    /// Needs-you first, then errors, then work in progress.
    public var attentionRank: Int {
        switch self {
        case .needsInput: return 0
        case .error: return 1
        case .done: return 2
        case .working: return 3
        case .idle: return 4
        }
    }
}

/// Agent CLIs Tethera knows by name.
public enum AgentKind: String, Codable, CaseIterable, Sendable {
    case claude, codex, opencode, hermes, gemini, antigravity, ollama, aider, cursor, amp, goose, crush, qwen

    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        case .hermes: return "Hermes"
        case .gemini: return "Gemini"
        case .antigravity: return "Antigravity"
        case .ollama: return "Ollama"
        case .aider: return "Aider"
        case .cursor: return "Cursor Agent"
        case .amp: return "Amp"
        case .goose: return "Goose"
        case .crush: return "Crush"
        case .qwen: return "Qwen Code"
        }
    }

    /// The command that starts it interactively.
    public var command: String {
        switch self {
        case .antigravity: return "agy"
        case .cursor: return "cursor-agent"
        case .ollama: return "ollama"
        default: return rawValue
        }
    }

    /// Identifies an agent from a process's executable path and arguments. Node and Python
    /// agents run as `node …/gemini-cli/…` or `python …/hermes`, so the arguments count too.
    public init?(executable: String, arguments: [String] = []) {
        let candidates = [executable] + arguments.prefix(3)
        for candidate in candidates {
            let lower = candidate.lowercased()
            let name = (lower as NSString).lastPathComponent
            if let kind = AgentKind.byProgram[name] {
                self = kind
                return
            }
            for (fragment, kind) in AgentKind.pathFragments where lower.contains(fragment) {
                self = kind
                return
            }
        }
        return nil
    }

    private static let byProgram: [String: AgentKind] = [
        "claude": .claude, "claude-code": .claude, "codex": .codex, "opencode": .opencode, "hermes": .hermes, "hermes-agent": .hermes,
        "gemini": .gemini, "agy": .antigravity, "antigravity": .antigravity, "ollama": .ollama, "aider": .aider,
        "cursor-agent": .cursor, "amp": .amp, "goose": .goose, "crush": .crush, "qwen": .qwen,
    ]

    private static let pathFragments: [(String, AgentKind)] = [
        ("/claude-code/", .claude), ("@anthropic-ai/claude-code", .claude), ("/codex/", .codex),
        ("@openai/codex", .codex), ("/opencode", .opencode), ("gemini-cli", .gemini),
        ("hermes_cli", .hermes), ("hermes-agent", .hermes), ("/aider", .aider), ("@qwen-code", .qwen),
    ]
}
