import Foundation
import OSLog
import SwiftTerm

/// Semantic events from the shell, delivered on the main thread.
@MainActor
protocol ShellSessionDelegate: AnyObject {
    func shellSession(_ session: ShellSession, didReceive event: OSC133Splitter.Event)
    func shellSessionDidExit(_ session: ShellSession, status: Int32?)
}

/// A login shell running inside a real pseudo-terminal (forkpty via SwiftTerm), with
/// Tethera's shell integration loaded race-free through ZDOTDIR / --rcfile.
final class ShellSession: LocalProcessDelegate {
    weak var delegate: ShellSessionDelegate?

    let shellPath: String
    private(set) var isRunning = false
    private(set) var bracketedPasteEnabled = false
    private var process: LocalProcess!
    private var splitter = OSC133Splitter()
    private var windowSize = winsize(ws_row: 30, ws_col: 100, ws_xpixel: 0, ws_ypixel: 0)
    private var masterFD: Int32 = -1
    private let logger = Logger(subsystem: "com.tethera.app", category: "ShellSession")

    init(shellPath: String = ShellEnvironment.loginShell) {
        self.shellPath = shellPath
        self.process = LocalProcess(delegate: self, dispatchQueue: .main)
    }

    deinit {
        terminate()
    }

    // MARK: - Lifecycle

    func start(workingDirectory: String, columns: Int, rows: Int) {
        guard !isRunning else { return }
        windowSize = winsize(ws_row: UInt16(clamping: max(rows, 2)), ws_col: UInt16(clamping: max(columns, 10)), ws_xpixel: 0, ws_ypixel: 0)

        var env = ShellEnvironment.removingParentAgentMarkers(ProcessInfo.processInfo.environment)
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "Tethera"
        env["TERM_PROGRAM_VERSION"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        env["TETHERA"] = "1"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        if env["LC_CTYPE"] == nil { env["LC_CTYPE"] = env["LANG"] }
        env.removeValue(forKey: "TETHERA_ENV_PROBE")
        // Drop variables that only make sense for the parent (Xcode / swift run).
        for key in env.keys where key.hasPrefix("__CF") || key == "PWD" || key == "OLDPWD" || key == "SHLVL" {
            env.removeValue(forKey: key)
        }

        var args = ["-l", "-i"]
        let shellName = (shellPath as NSString).lastPathComponent
        do {
            let integration = try ShellIntegration.install()
            if shellName == "zsh" {
                env["TETHERA_USER_ZDOTDIR"] = env["ZDOTDIR"] ?? ""
                env["TETHERA_INTEGRATION"] = integration.zshScript
                env["ZDOTDIR"] = integration.zshDirectory
            } else if shellName == "bash" {
                args = ["--rcfile", integration.bashRCFile, "-i"]
            }
        } catch {
            logger.error("Shell integration unavailable: \(error.localizedDescription)")
        }

        let envList = env.map { "\($0.key)=\($0.value)" }
        // A leading "-" in argv[0] marks a login shell. Bash ignores --rcfile in login mode,
        // so its shim emulates the login startup files instead.
        let execName = shellName == "bash" ? shellName : "-" + shellName
        process.startProcess(executable: shellPath, args: args, environment: envList,
                             execName: execName, currentDirectory: workingDirectory)
        isRunning = process.running
        masterFD = process.childfd
        if !isRunning {
            logger.error("Failed to launch \(self.shellPath)")
        }
    }

    /// Ends the shell without blocking: SIGHUP like a closed terminal, SIGKILL if it lingers.
    func terminate() {
        guard isRunning else { return }
        isRunning = false
        let pid = process.shellPid
        guard pid > 0 else { return }
        kill(pid, SIGHUP)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) {
            if kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
            }
            var status: Int32 = 0
            waitpid(pid, &status, WNOHANG)
        }
    }

    // MARK: - Input

    func send(_ bytes: ArraySlice<UInt8>) {
        guard isRunning else { return }
        process.send(data: bytes)
    }

    func send(_ string: String) {
        send(Array(string.utf8)[...])
    }

    /// Submits a command line to the shell prompt.
    func submit(_ command: String) {
        // ^U clears anything typed ahead at the prompt so it can't merge with the command.
        var payload = "\u{15}"
        if command.contains("\n") && bracketedPasteEnabled {
            payload += "\u{1b}[200~" + command + "\u{1b}[201~"
        } else {
            payload += command
        }
        payload += "\r"
        send(payload)
    }

    func interrupt() {
        send("\u{03}")
    }

    var windowColumns: Int { Int(windowSize.ws_col) }
    var windowRows: Int { Int(windowSize.ws_row) }

    func resize(columns: Int, rows: Int) {
        let cols = UInt16(clamping: max(columns, 10))
        let rowCount = UInt16(clamping: max(rows, 2))
        guard cols != windowSize.ws_col || rowCount != windowSize.ws_row else { return }
        windowSize.ws_col = cols
        windowSize.ws_row = rowCount
        guard isRunning, masterFD >= 0 else { return }
        var size = windowSize
        _ = PseudoTerminalHelpers.setWinSize(masterPtyDescriptor: masterFD, windowSize: &size)
    }

    // MARK: - LocalProcessDelegate

    func dataReceived(slice: ArraySlice<UInt8>) {
        let events = splitter.feed(slice)
        for event in events {
            if case .bracketedPaste(let enabled) = event {
                bracketedPasteEnabled = enabled
            }
        }
        MainActor.assumeIsolated {
            guard let delegate else { return }
            for event in events {
                delegate.shellSession(self, didReceive: event)
            }
        }
    }

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        isRunning = false
        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }
        MainActor.assumeIsolated {
            delegate?.shellSessionDidExit(self, status: exitCode)
        }
    }

    func getWindowSize() -> winsize {
        windowSize
    }
}

/// Writes the integration shims into Application Support. The zsh shims are dot-files,
/// which SwiftPM refuses to bundle, so they are generated here instead.
enum ShellIntegration {
    struct Paths {
        let zshDirectory: String
        let zshScript: String
        let bashRCFile: String
    }

    private static var cached: Paths?

    static func install() throws -> Paths {
        if let cached { return cached }
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tethera/shell", isDirectory: true)
        let zdot = support.appendingPathComponent("zsh", isDirectory: true)
        try fm.createDirectory(at: zdot, withIntermediateDirectories: true)

        let zshScript = support.appendingPathComponent("tethera.zsh")
        let bashScript = support.appendingPathComponent("tethera.bash")
        try bundledScript("tethera.zsh").write(to: zshScript, atomically: true, encoding: .utf8)
        try bundledScript("tethera.bash").write(to: bashScript, atomically: true, encoding: .utf8)

        for (name, body) in zshShims {
            try body.write(to: zdot.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let bashRC = support.appendingPathComponent("bashrc")
        try bashShim(integration: bashScript.path).write(to: bashRC, atomically: true, encoding: .utf8)

        let paths = Paths(zshDirectory: zdot.path, zshScript: zshScript.path, bashRCFile: bashRC.path)
        cached = paths
        return paths
    }

    private static func bundledScript(_ name: String) throws -> String {
        guard let url = Bundle.tethera.url(forResource: name, withExtension: nil, subdirectory: "shell") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "shell/\(name)"])
        }
        return try String(contentsOf: url, encoding: .utf8)
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
