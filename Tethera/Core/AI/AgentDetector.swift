import Foundation

/// Finds which AI CLIs are installed and their versions.
@MainActor
final class AgentDetector: ObservableObject {
    static let shared = AgentDetector()

    struct Status: Equatable {
        var path: String?
        var version: String?
        var isInstalled: Bool { path != nil }
    }

    @Published private(set) var statuses: [AgentCLI: Status] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var models: [AgentCLI: [String]] = [:]

    private init() {
        Task { await refresh() }
    }

    func status(for provider: AgentCLI) -> Status? {
        statuses[provider]
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await withTaskGroup(of: (AgentCLI, Status).self) { group in
            for provider in AgentCLI.allCases {
                group.addTask {
                    guard let path = await ShellEnvironment.shared.resolve(provider.binary) else {
                        return (provider, Status(path: nil, version: nil))
                    }
                    let output = await Self.run(path, ["--version"], timeout: 8)
                    return (provider, Status(path: path, version: Self.parseVersion(output)))
                }
            }
            for await (provider, status) in group {
                statuses[provider] = status
            }
        }
    }

    /// Models the provider can list itself (OpenCode, Ollama).
    func loadModels(for provider: AgentCLI) async {
        var resolved = statuses[provider]?.path
        if resolved == nil { resolved = await ShellEnvironment.shared.resolve(provider.binary) }
        guard let path = resolved else { return }
        let output: String
        switch provider {
        case .opencode:
            output = await Self.run(path, ["models"], timeout: 20)
            models[provider] = output.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.contains("/") && !$0.contains(" ") }
                .sorted { lhs, rhs in
                    // Free models first — that's why people pick OpenCode.
                    let lFree = lhs.hasPrefix("opencode/"), rFree = rhs.hasPrefix("opencode/")
                    return lFree != rFree ? lFree : lhs < rhs
                }
        case .ollama:
            output = await Self.run(path, ["list"], timeout: 10)
            models[provider] = output.split(separator: "\n").dropFirst()
                .compactMap { $0.split(separator: " ").first.map(String.init) }
        default:
            break
        }
    }

    private nonisolated static func parseVersion(_ output: String) -> String? {
        let firstLine = ANSIStripper.strip(output).split(separator: "\n").first.map(String.init) ?? ""
        guard let regex = try? NSRegularExpression(pattern: "\\d+\\.\\d+(?:\\.\\d+)?"),
              let match = regex.firstMatch(in: firstLine, range: NSRange(firstLine.startIndex..., in: firstLine)),
              let range = Range(match.range, in: firstLine) else {
            return firstLine.isEmpty ? nil : String(firstLine.prefix(32))
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
