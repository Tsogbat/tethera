import Foundation

/// How a session's shell is started: the user's login shell with Tethera's integration loaded
/// race-free (zsh through a `ZDOTDIR` shim, bash through `--rcfile`), so nothing is ever typed
/// into the shell to set it up.
public struct ShellLaunch: Equatable, Sendable {
    public let executable: String
    /// argv including argv[0] (a leading `-` asks zsh for a login shell).
    public let arguments: [String]
    public let environment: [String: String]

    /// The user's shell: `$SHELL` if it is a supported shell, otherwise the passwd entry, otherwise zsh.
    public static var loginShell: String {
        let candidates = [ProcessInfo.processInfo.environment["SHELL"], passwdShell()].compactMap { $0 }
        return candidates.first(where: isSupported) ?? "/bin/zsh"
    }

    public static func isSupported(_ shell: String) -> Bool {
        let name = (shell as NSString).lastPathComponent
        return ["zsh", "bash", "fish", "sh"].contains(name) && FileManager.default.isExecutableFile(atPath: shell)
    }

    private static func passwdShell() -> String? {
        guard let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell else { return nil }
        return String(cString: shell)
    }

    /// Builds the launch for a session. `base` is the environment to start from.
    public static func make(shell: String?, sessionID: UUID, base: [String: String], version: String) throws -> ShellLaunch {
        let path = shell.flatMap { isSupported($0) ? $0 : nil } ?? loginShell
        let name = (path as NSString).lastPathComponent

        var env = removingParentAgentMarkers(base)
        for key in env.keys where key.hasPrefix("__CF") || key == "PWD" || key == "OLDPWD" || key == "SHLVL" || key == "_" {
            env.removeValue(forKey: key)
        }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "Tethera"
        env["TERM_PROGRAM_VERSION"] = version
        env["TETHERA"] = "1"
        env["TETHERA_SESSION_ID"] = sessionID.uuidString
        env["TETHERA_SOCKET"] = TetheraPaths.socket.path
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        if env["LC_CTYPE"] == nil { env["LC_CTYPE"] = env["LANG"] }

        var arguments = ["-" + name]
        let integration = try ShellIntegrationFiles.install()
        switch name {
        case "zsh":
            env["TETHERA_USER_ZDOTDIR"] = env["ZDOTDIR"] ?? ""
            env["TETHERA_INTEGRATION"] = integration.zshScript
            env["ZDOTDIR"] = integration.zshDirectory
        case "bash":
            // Bash ignores --rcfile in login mode; the shim emulates the login startup files.
            arguments = [name, "--rcfile", integration.bashRCFile, "-i"]
        default:
            break
        }
        return ShellLaunch(executable: path, arguments: arguments, environment: env)
    }

    /// Session markers a parent agent sets for its children. Inherited by our shells, they make a
    /// `claude` run inside Tethera believe it is nested in the session that launched Tethera.
    public static func removingParentAgentMarkers(_ env: [String: String]) -> [String: String] {
        env.filter { key, _ in
            !(key == "CLAUDECODE" || key == "CLAUDE_PID" || key == "CLAUDE_EFFORT"
              || key.hasPrefix("CLAUDE_CODE_SESSION") || key.hasPrefix("CLAUDE_CODE_MESSAGING")
              || key == "CLAUDE_CODE_ENTRYPOINT" || key == "CLAUDE_CODE_CHILD_SESSION" || key == "CLAUDE_CODE_EXECPATH"
              || key == "TETHERA_SESSION_ID")
        }
    }
}

/// Writes the integration scripts and zsh shims under the Tethera home. The zsh shims are
/// dot-files, so they are generated here rather than bundled.
public enum ShellIntegrationFiles {
    public struct Paths: Sendable {
        public let zshDirectory: String
        public let zshScript: String
        public let bashRCFile: String
    }

    nonisolated(unsafe) private static var cached: Paths?
    private static let lock = NSLock()

    public static func install() throws -> Paths {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        try TetheraPaths.prepare()
        let root = TetheraPaths.shellIntegration
        let zdot = root.appendingPathComponent("zsh", isDirectory: true)
        try FileManager.default.createDirectory(at: zdot, withIntermediateDirectories: true)

        let zshScript = root.appendingPathComponent("tethera.zsh")
        let bashScript = root.appendingPathComponent("tethera.bash")
        try ShellScripts.zsh.write(to: zshScript, atomically: true, encoding: .utf8)
        try ShellScripts.bash.write(to: bashScript, atomically: true, encoding: .utf8)
        for (name, body) in zshShims {
            try body.write(to: zdot.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let bashRC = root.appendingPathComponent("bashrc")
        try bashShim(integration: bashScript.path).write(to: bashRC, atomically: true, encoding: .utf8)

        let paths = Paths(zshDirectory: zdot.path, zshScript: zshScript.path, bashRCFile: bashRC.path)
        cached = paths
        return paths
    }

    /// Each shim sources the user's real file with ZDOTDIR pointing at the user's directory,
    /// then switches back so zsh keeps loading Tethera's remaining shims.
    private static let zshShims: [(String, String)] = {
        func shim(_ file: String, extra: String = "") -> String {
            """
            # Generated by Tethera. Loads the user's \(file), then Tethera's integration.
            __tethera_shim_dir="$ZDOTDIR"
            ZDOTDIR="${TETHERA_USER_ZDOTDIR:-$HOME}"
            [[ -r "$ZDOTDIR/\(file)" ]] && builtin source "$ZDOTDIR/\(file)"
            if [[ "$ZDOTDIR" != "$__tethera_shim_dir" ]]; then
                TETHERA_USER_ZDOTDIR="$ZDOTDIR"
            fi
            ZDOTDIR="$__tethera_shim_dir"
            unset __tethera_shim_dir
            \(extra)
            """
        }
        let restore = """
        __tethera_restore_zdotdir() {
            if [[ -n "${TETHERA_USER_ZDOTDIR-}" && "$TETHERA_USER_ZDOTDIR" != "$HOME" ]]; then
                export ZDOTDIR="$TETHERA_USER_ZDOTDIR"
            else
                unset ZDOTDIR
            fi
            unset TETHERA_USER_ZDOTDIR
        }
        """
        let rcExtra = """
        [[ -r "${TETHERA_INTEGRATION-}" ]] && builtin source "$TETHERA_INTEGRATION"
        unset TETHERA_INTEGRATION
        \(restore)
        [[ -o login ]] || __tethera_restore_zdotdir
        """
        let loginExtra = """
        (( $+functions[__tethera_restore_zdotdir] )) && __tethera_restore_zdotdir
        """
        return [
            (".zshenv", shim(".zshenv")),
            (".zprofile", shim(".zprofile")),
            (".zshrc", shim(".zshrc", extra: rcExtra)),
            (".zlogin", shim(".zlogin", extra: loginExtra)),
        ]
    }()

    private static func bashShim(integration: String) -> String {
        """
        # Generated by Tethera. Mirrors login-shell startup, then loads the integration.
        [ -r /etc/profile ] && . /etc/profile
        if [ -r "$HOME/.bash_profile" ]; then
            . "$HOME/.bash_profile"
        elif [ -r "$HOME/.bash_login" ]; then
            . "$HOME/.bash_login"
        elif [ -r "$HOME/.profile" ]; then
            . "$HOME/.profile"
        elif [ -r "$HOME/.bashrc" ]; then
            . "$HOME/.bashrc"
        fi
        [ -r "\(integration)" ] && . "\(integration)"
        """
    }
}

/// OSC 133 prompt marks and OSC 7 cwd reports for each shell.
enum ShellScripts {
    static let zsh = #"""
# Tethera — zsh integration
# Emits OSC 133 semantic prompt marks and OSC 7 working-directory updates so
# Tethera can split the session into blocks. Loaded by Tethera's ZDOTDIR shim.

[[ -o interactive ]] || return 0
[[ -n "${__tethera_integrated-}" ]] && return 0
typeset -g __tethera_integrated=1
typeset -gi __tethera_command_running=0

# Blocks are separate, so zsh's "missing newline" marker (an inverse %) would only leak into output.
unsetopt PROMPT_SP 2>/dev/null

__tethera_osc() {
    builtin printf '\e]%s\a' "$1"
}

__tethera_precmd() {
    local status_code=$?
    if (( __tethera_command_running )); then
        __tethera_osc "133;D;${status_code}"
        __tethera_command_running=0
    fi
    __tethera_osc "7;file://${HOST}${PWD}"
    __tethera_osc "133;A"
    return $status_code
}

__tethera_preexec() {
    __tethera_command_running=1
    __tethera_osc "133;B"
    __tethera_osc "133;C"
}

# Run first so $? still holds the command's exit status.
precmd_functions=(__tethera_precmd ${precmd_functions:#__tethera_precmd})
preexec_functions=(${preexec_functions:#__tethera_preexec} __tethera_preexec)
"""#

    static let bash = #"""
# Tethera — bash integration
# Emits OSC 133 semantic prompt marks and OSC 7 working-directory updates so
# Tethera can split the session into blocks. Loaded through Tethera's --rcfile shim.

[[ $- == *i* ]] || return 0
[[ -n "${__tethera_integrated-}" ]] && return 0
__tethera_integrated=1
__tethera_at_prompt=0
__tethera_command_running=0
__tethera_status=0

__tethera_osc() {
    builtin printf '\e]%s\a' "$1"
}

__tethera_save_status() {
    __tethera_status=$?
}

__tethera_prompt_command() {
    if [[ $__tethera_command_running == 1 ]]; then
        __tethera_osc "133;D;${__tethera_status}"
        __tethera_command_running=0
    fi
    __tethera_osc "7;file://${HOSTNAME}${PWD}"
    __tethera_osc "133;A"
    __tethera_at_prompt=1
    return $__tethera_status
}

__tethera_debug_trap() {
    [[ $__tethera_at_prompt == 1 ]] || return 0
    [[ -n "${COMP_LINE-}" ]] && return 0
    case "$BASH_COMMAND" in
        __tethera_save_status*|__tethera_prompt_command*) return 0 ;;
    esac
    __tethera_at_prompt=0
    __tethera_command_running=1
    __tethera_osc "133;B"
    __tethera_osc "133;C"
}

trap '__tethera_debug_trap' DEBUG
PROMPT_COMMAND="__tethera_save_status${PROMPT_COMMAND:+;$PROMPT_COMMAND};__tethera_prompt_command"
"""#
}
