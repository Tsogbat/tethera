import Foundation
import TetheraKit

/// Finds which agent CLIs are installed, through the login shell's PATH, and their versions.
@MainActor
final class AgentDetector: ObservableObject {
    static let shared = AgentDetector()

    struct Status: Equatable {
        var path: String?
        var version: String?
        var isInstalled: Bool { path != nil }
    }

    /// The agents Tethera offers in "New session", in menu order.
    static let launchable: [AgentKind] = [.claude, .codex, .opencode, .hermes, .antigravity, .gemini, .ollama]

    @Published private(set) var statuses: [AgentKind: Status] = [:]
    @Published private(set) var isRefreshing = false

    private init() {
        Task { await refresh() }
    }

    func status(for kind: AgentKind) -> Status? {
        statuses[kind]
    }

    var installed: [AgentKind] {
        Self.launchable.filter { statuses[$0]?.isInstalled == true }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await withTaskGroup(of: (AgentKind, Status).self) { group in
            for kind in Self.launchable {
                group.addTask {
                    guard let path = await ShellEnvironment.shared.resolve(kind.command) else {
                        return (kind, Status(path: nil, version: nil))
                    }
                    let output = await Self.run(path, ["--version"], timeout: 8)
                    return (kind, Status(path: path, version: Self.parseVersion(output)))
                }
            }
            for await (kind, status) in group {
                statuses[kind] = status
            }
        }
    }

    nonisolated static func parseVersion(_ output: String) -> String? {
        let firstLine = output.split(separator: "\n").first.map(String.init) ?? ""
        guard let regex = try? NSRegularExpression(pattern: "\\d+\\.\\d+(?:\\.\\d+)?"),
              let match = regex.firstMatch(in: firstLine, range: NSRange(firstLine.startIndex..., in: firstLine)),
              let range = Range(match.range, in: firstLine) else {
            return nil
        }
        return String(firstLine[range])
    }

    nonisolated static func run(_ path: String, _ arguments: [String], timeout: TimeInterval) async -> String {
        let env = await ShellEnvironment.shared.environment()
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                var environment = env
                environment["NO_COLOR"] = "1"
                environment["TERM"] = "dumb"
                process.environment = environment
                process.standardInput = FileHandle.nullDevice
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: "")
                    return
                }
                let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                timer.cancel()
                continuation.resume(returning: String(decoding: data, as: UTF8.self))
            }
        }
    }
}
