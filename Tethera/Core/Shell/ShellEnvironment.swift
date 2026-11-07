import Foundation
import TetheraKit
import OSLog

/// The user's login-shell environment, captured once in the background.
///
/// Apps launched from Finder inherit a minimal environment (no Homebrew/nvm PATH, no LANG),
/// so AI CLIs such as `opencode` or `claude` would not resolve. Everything that spawns
/// helper processes goes through this.
final class ShellEnvironment: @unchecked Sendable {
    static let shared = ShellEnvironment()

    private let task: Task<[String: String], Never>
    private static let logger = Logger(subsystem: "com.tethera.app", category: "ShellEnvironment")

    private init() {
        task = Task.detached(priority: .userInitiated) {
            Self.capture()
        }
    }

    /// Environment for helper processes (AI CLIs, completions).
    func environment() async -> [String: String] {
        await task.value
    }

    /// The shell Tethera runs: the user's shell when it is zsh or bash, otherwise zsh.
    static var loginShell: String {
        let candidates = [ProcessInfo.processInfo.environment["SHELL"], passwdShell()].compactMap { $0 }
        for shell in candidates where isSupported(shell) && FileManager.default.isExecutableFile(atPath: shell) {
            return shell
        }
        return "/bin/zsh"
    }

    static func isSupported(_ shell: String) -> Bool {
        let name = (shell as NSString).lastPathComponent
        return name == "zsh" || name == "bash"
    }

    /// Resolves an executable against the captured PATH.
    func resolve(_ binary: String) async -> String? {
        if binary.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: binary) ? binary : nil
        }
        let path = await environment()["PATH"] ?? ""
        var dirs = path.split(separator: ":").map(String.init)
        // Common install locations that are missing from minimal PATHs.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        dirs += ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.bun/bin",
                 "\(home)/.opencode/bin", "\(home)/.npm-global/bin", "\(home)/.cargo/bin"]
        for dir in dirs {
            let candidate = (dir as NSString).appendingPathComponent(binary)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func passwdShell() -> String? {
        guard let pw = getpwuid(getuid()), let shell = pw.pointee.pw_shell else { return nil }
        return String(cString: shell)
    }

    private static func capture() -> [String: String] {
        var fallback = ShellLaunch.removingParentAgentMarkers(ProcessInfo.processInfo.environment)
        if fallback["LANG"] == nil { fallback["LANG"] = "en_US.UTF-8" }

        let begin = "__TETHERA_ENV_BEGIN__"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: loginShell)
        process.arguments = ["-l", "-i", "-c", "printf '\\n\(begin)\\n'; env -0"]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        var env = fallback
        env["TETHERA_ENV_PROBE"] = "1"
        process.environment = env

        do {
            try process.run()
        } catch {
            logger.error("Could not capture login environment: \(error.localizedDescription)")
            return fallback
        }

        let deadline = DispatchTime.now() + .seconds(6)
        let reader = DispatchQueue(label: "tethera.env.reader")
        var data = Data()
        let group = DispatchGroup()
        group.enter()
        reader.async {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        if group.wait(timeout: deadline) == .timedOut {
            process.terminate()
            logger.error("Login environment capture timed out")
            return fallback
        }
        process.waitUntilExit()

        guard let marker = "\n\(begin)\n".data(using: .utf8),
              let range = data.range(of: marker, options: .backwards) else {
            return fallback
        }
        let body = data[range.upperBound...]
        var result: [String: String] = [:]
        for entry in body.split(separator: 0) {
            guard let string = String(data: Data(entry), encoding: .utf8),
                  let eq = string.firstIndex(of: "=") else { continue }
            result[String(string[..<eq])] = String(string[string.index(after: eq)...])
        }
        guard result["PATH"] != nil else { return fallback }
        result.removeValue(forKey: "TETHERA_ENV_PROBE")
        result.removeValue(forKey: "_")
        if result["LANG"] == nil { result["LANG"] = "en_US.UTF-8" }
        return result
    }
}
