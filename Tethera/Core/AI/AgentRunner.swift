import Foundation
import OSLog

struct AgentRequest {
    var provider: AgentCLI
    var prompt: String
    var system: String
    var model: String?
    var workingDirectory: String
    var timeout: TimeInterval = 120
}

struct AgentFailure: Error, Equatable {
    enum Kind: Equatable {
        case notInstalled, notSignedIn, rateLimited, timedOut, cancelled, failed
    }

    var kind: Kind
    var message: String
    var hint: String?
}

enum AgentEvent: Equatable {
    /// The full response so far.
    case update(String)
    case finished(String)
    case failed(AgentFailure)
}

/// Runs an AI CLI headlessly and streams its answer.
enum AgentRunner {
    private static let logger = Logger(subsystem: "com.tethera.app", category: "AgentRunner")

    static func stream(_ request: AgentRequest) -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            let job = Job(request: request, continuation: continuation)
            continuation.onTermination = { termination in
                if case .cancelled = termination { job.cancel() }
            }
            Task.detached(priority: .userInitiated) {
                await job.start()
            }
        }
    }

    /// Collects a stream into its final text.
    static func complete(_ request: AgentRequest) async -> Result<String, AgentFailure> {
        var last = ""
        for await event in stream(request) {
            switch event {
            case .update(let text): last = text
            case .finished(let text): return .success(text.isEmpty ? last : text)
            case .failed(let failure): return .failure(failure)
            }
        }
        return .failure(AgentFailure(kind: .cancelled, message: "Cancelled"))
    }

    // MARK: - Job

    private final class Job: @unchecked Sendable {
        let request: AgentRequest
        let continuation: AsyncStream<AgentEvent>.Continuation
        private let lock = NSLock()
        private var process: Process?
        private var parser: AgentOutputParser
        private var lineBuffer = Data()
        private var stderr = Data()
        private var lastEmitted = ""
        private var finished = false
        private var cancelled = false
        private var timedOut = false

        init(request: AgentRequest, continuation: AsyncStream<AgentEvent>.Continuation) {
            self.request = request
            self.continuation = continuation
            self.parser = AgentOutputParser(format: request.provider.outputFormat)
        }

        func start() async {
            guard let executable = await ShellEnvironment.shared.resolve(request.provider.binary) else {
                finish(.failed(AgentFailure(kind: .notInstalled,
                                            message: "\(request.provider.displayName) isn't installed.",
                                            hint: "Install the `\(request.provider.binary)` CLI, or pick another provider in Settings → AI.")))
                return
            }
            var env = await ShellEnvironment.shared.environment()
            env["NO_COLOR"] = "1"
            env["TERM"] = "dumb"
            env["FORCE_COLOR"] = "0"
            env["TETHERA"] = "1"

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = request.provider.headlessArguments(prompt: request.prompt, system: request.system,
                                                                   model: request.model, workingDirectory: request.workingDirectory)
            process.environment = env
            if FileManager.default.fileExists(atPath: request.workingDirectory) {
                process.currentDirectoryURL = URL(fileURLWithPath: request.workingDirectory)
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            let stdinPipe = Pipe()
            process.standardInput = request.provider.readsPromptFromStdin ? stdinPipe : FileHandle.nullDevice

            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard let self else { return }
                if data.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    self.consume(stdout: data)
                }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard let self else { return }
                if data.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    self.lock.lock()
                    if self.stderr.count < 32_768 { self.stderr.append(data) }
                    self.lock.unlock()
                }
            }
            process.terminationHandler = { [weak self] proc in
                // Let the pipes drain before deciding the outcome.
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    let rest = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    if !rest.isEmpty { self?.consume(stdout: rest) }
                    self?.processExited(status: proc.terminationStatus)
                }
            }

            guard register(process) else {
                finish(.failed(AgentFailure(kind: .cancelled, message: "Cancelled")))
                return
            }

            do {
                try process.run()
            } catch {
                finish(.failed(AgentFailure(kind: .failed, message: "Couldn't start \(request.provider.binary): \(error.localizedDescription)")))
                return
            }
            if request.provider.readsPromptFromStdin {
                stdinPipe.fileHandleForWriting.write(Data(request.prompt.utf8))
                try? stdinPipe.fileHandleForWriting.close()
            }

            let timeout = request.timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let running = !self.finished
                if running { self.timedOut = true }
                self.lock.unlock()
                if running { self.terminate() }
            }
        }

        /// Records the process unless the request was already cancelled.
        private func register(_ process: Process) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !cancelled else { return false }
            self.process = process
            return true
        }

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
            terminate()
        }

        private func terminate() {
            lock.lock()
            let process = self.process
            lock.unlock()
            guard let process, process.isRunning else { return }
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
            }
        }

        private func consume(stdout data: Data) {
            lock.lock()
            lineBuffer.append(data)
            var changed = false
            if parser.format == .plain {
                if let text = String(data: lineBuffer, encoding: .utf8) {
                    parser.appendPlain(text)
                    lineBuffer.removeAll()
                    changed = true
                }
            } else {
                while let newline = lineBuffer.firstIndex(of: 0x0A) {
                    let line = lineBuffer[lineBuffer.startIndex..<newline]
                    lineBuffer.removeSubrange(lineBuffer.startIndex...newline)
                    if parser.consume(line: String(decoding: line, as: UTF8.self)) { changed = true }
                }
            }
            let text = parser.text
            let shouldEmit = changed && text != lastEmitted && !finished
            if shouldEmit { lastEmitted = text }
            lock.unlock()
            if shouldEmit {
                continuation.yield(.update(text.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }

        private func processExited(status: Int32) {
            lock.lock()
            if !lineBuffer.isEmpty, parser.format != .plain {
                _ = parser.consume(line: String(decoding: lineBuffer, as: UTF8.self))
                lineBuffer.removeAll()
            }
            let text = parser.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
            let parserError = parser.errorMessage
            let errorOutput = String(decoding: stderr, as: UTF8.self)
            let wasCancelled = cancelled
            let wasTimedOut = timedOut
            lock.unlock()

            if wasCancelled {
                finish(.failed(AgentFailure(kind: .cancelled, message: "Cancelled")))
            } else if wasTimedOut {
                finish(.failed(AgentFailure(kind: .timedOut, message: "\(request.provider.displayName) took too long to answer.",
                                            hint: "Try again, or switch to a faster model in Settings → AI.")))
            } else if status == 0, parserError == nil, !text.isEmpty {
                finish(.finished(text))
            } else {
                let raw = parserError ?? (errorOutput.isEmpty ? text : errorOutput)
                finish(.failed(AgentRunner.classify(raw, status: status, provider: request.provider)))
            }
        }

        private func finish(_ event: AgentEvent) {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            lock.unlock()
            continuation.yield(event)
            continuation.finish()
        }
    }
}

extension AgentRunner {
    /// Maps a CLI's error output to a friendly failure with a next step.
    static func classify(_ raw: String, status: Int32, provider: AgentCLI) -> AgentFailure {
        let cleaned = ANSIStripper.strip(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = cleaned.lowercased()
        let summary = cleaned.split(separator: "\n").suffix(4).joined(separator: "\n")
        let message = summary.isEmpty ? "\(provider.displayName) exited with status \(status)." : String(summary.prefix(600))

        let signInMarkers = ["not logged in", "log in", "login", "logged out", "unauthorized", "401", "authenticat",
                             "api key", "api_key", "credentials", "sign in", "oauth", "/login"]
        if signInMarkers.contains(where: lower.contains) {
            return AgentFailure(kind: .notSignedIn, message: message,
                                hint: "Sign in by running `\(provider.loginCommand)` — Settings → AI → Sign in opens it in a tab.")
        }
        let limitMarkers = ["rate limit", "429", "quota", "usage limit", "too many requests", "overloaded"]
        if limitMarkers.contains(where: lower.contains) {
            return AgentFailure(kind: .rateLimited, message: message, hint: "The provider is rate-limited. Wait a moment or switch providers.")
        }
        if lower.contains("model") && (lower.contains("not found") || lower.contains("unknown") || lower.contains("invalid") || lower.contains("not supported")) {
            return AgentFailure(kind: .failed, message: message, hint: "Check the model name in Settings → AI.")
        }
        return AgentFailure(kind: .failed, message: message, hint: nil)
    }
}

// MARK: - Output parsing

/// Turns each CLI's output format into the assistant's text.
struct AgentOutputParser {
    let format: AgentOutputFormat
    private var orderedIDs: [String] = []
    private var parts: [String: String] = [:]
    private var streamed = ""
    private var resultText: String?
    private var rawLines: [String] = []
    private(set) var errorMessage: String?

    init(format: AgentOutputFormat) {
        self.format = format
    }

    /// Text assembled so far.
    var text: String {
        switch format {
        case .plain:
            return ANSIStripper.strip(streamed)
        case .claudeStreamJSON, .geminiStreamJSON:
            return streamed.isEmpty ? joinedParts : streamed
        case .opencodeJSON, .codexJSON:
            return joinedParts
        }
    }

    /// Text once the process exited, falling back to final results and non-JSON output.
    var finalText: String {
        if let resultText, !resultText.isEmpty, text.isEmpty { return resultText }
        let current = text
        if current.isEmpty && !rawLines.isEmpty {
            return ANSIStripper.strip(rawLines.joined(separator: "\n"))
        }
        return current
    }

    private var joinedParts: String {
        orderedIDs.compactMap { parts[$0] }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    mutating func appendPlain(_ chunk: String) {
        streamed += chunk
    }

    /// Returns true when the visible text changed.
    mutating func consume(line rawLine: String) -> Bool {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return false }
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if rawLines.count < 400 { rawLines.append(line) }
            return false
        }
        let before = text
        switch format {
        case .claudeStreamJSON: consumeClaude(object)
        case .codexJSON: consumeCodex(object)
        case .opencodeJSON: consumeOpenCode(object)
        case .geminiStreamJSON: consumeGemini(object)
        case .plain: break
        }
        return text != before
    }

    private mutating func setPart(_ id: String, _ value: String) {
        if parts[id] == nil { orderedIDs.append(id) }
        parts[id] = value
    }

    private mutating func consumeClaude(_ object: [String: Any]) {
        let type = object["type"] as? String
        switch type {
        case "stream_event":
            guard let event = object["event"] as? [String: Any] else { return }
            if event["type"] as? String == "content_block_delta",
               let delta = event["delta"] as? [String: Any],
               delta["type"] as? String == "text_delta",
               let text = delta["text"] as? String {
                streamed += text
            }
        case "assistant":
            guard let message = object["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return }
            let text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            if !text.isEmpty { setPart(message["id"] as? String ?? UUID().uuidString, text) }
        case "result":
            let result = object["result"] as? String
            if object["is_error"] as? Bool == true || (object["subtype"] as? String)?.hasPrefix("error") == true {
                errorMessage = result ?? (object["subtype"] as? String) ?? "Claude Code reported an error."
            } else {
                resultText = result
            }
        default:
            break
        }
    }

    private mutating func consumeCodex(_ object: [String: Any]) {
        let type = object["type"] as? String ?? ""
        if type.hasPrefix("item."), let item = object["item"] as? [String: Any] {
            let itemType = (item["type"] as? String) ?? (item["item_type"] as? String)
            if itemType == "agent_message" || itemType == "assistant_message", let text = item["text"] as? String {
                setPart(item["id"] as? String ?? "\(orderedIDs.count)", text)
            }
        } else if type == "error" {
            errorMessage = object["message"] as? String ?? "Codex reported an error."
        } else if type == "turn.failed" {
            let error = object["error"] as? [String: Any]
            errorMessage = error?["message"] as? String ?? "Codex turn failed."
        }
    }

    private mutating func consumeOpenCode(_ object: [String: Any]) {
        let type = object["type"] as? String
        if type == "error" {
            let error = object["error"] as? [String: Any]
            let data = error?["data"] as? [String: Any]
            errorMessage = (data?["message"] as? String) ?? (error?["message"] as? String) ?? (error?["name"] as? String) ?? "OpenCode reported an error."
            return
        }
        if let part = object["part"] as? [String: Any], part["type"] as? String == "text", let text = part["text"] as? String {
            setPart(part["id"] as? String ?? "\(orderedIDs.count)", text)
        }
    }

    private mutating func consumeGemini(_ object: [String: Any]) {
        let type = object["type"] as? String
        switch type {
        case "message":
            guard object["role"] as? String == "assistant", let content = object["content"] as? String else { return }
            if object["delta"] as? Bool == true {
                streamed += content
            } else {
                setPart("\(orderedIDs.count)", content)
            }
        case "error":
            errorMessage = object["message"] as? String ?? "Gemini reported an error."
        case "result":
            if object["status"] as? String == "error" {
                let error = object["error"] as? [String: Any]
                errorMessage = error?["message"] as? String ?? "Gemini reported an error."
            }
        default:
            break
        }
    }
}

enum ANSIStripper {
    private static let pattern = try! NSRegularExpression(pattern: "\u{1B}(?:\\[[0-?]*[ -/]*[@-~]|\\][^\u{07}\u{1B}]*(?:\u{07}|\u{1B}\\\\)|[@-Z\\\\-_])")

    static func strip(_ string: String) -> String {
        guard string.contains("\u{1B}") || string.contains("\r") else { return string }
        let range = NSRange(string.startIndex..., in: string)
        var result = pattern.stringByReplacingMatches(in: string, range: range, withTemplate: "")
        // Spinners redraw with carriage returns; keep only the last state of each line.
        if result.contains("\r") {
            result = result.components(separatedBy: "\n").map { line in
                line.components(separatedBy: "\r").last(where: { !$0.isEmpty }) ?? ""
            }.joined(separator: "\n")
        }
        return result
    }
}
