import Foundation
import TetheraKit

/// What one member shares with the team: their agents' state and spend, never terminal content.
struct MemberStatus: Codable, Equatable {
    struct Session: Codable, Equatable, Hashable {
        var name: String
        /// The repository's folder name.
        var repo: String
        var agent: String
        var state: String
        var since: Date
        var costUSD: Double?
    }

    struct DayCost: Codable, Equatable, Hashable {
        var day: String
        var agent: String
        var repo: String
        var usd: Double
    }

    var login: String
    var mac: String
    var updated: Date
    var sessions: [Session]
    /// The last 30 days.
    var costs: [DayCost]
}

/// The GitHub calls a team needs.
protocol TeamBackend: Sendable {
    func login() async throws -> String
    /// Throws unless the repository exists, has a first commit, and you can push to it.
    func checkAccess(_ repo: String) async throws
    /// A file's contents, or nil when it doesn't exist.
    func readFile(_ repo: String, path: String, ref: String?) async throws -> Data?
    /// The logins that have shared a status.
    func members(_ repo: String) async throws -> [String]
    /// Replaces your member branch with one commit holding these files.
    func publish(_ repo: String, login: String, files: [String: Data]) async throws
}

struct TeamError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// A team is a private GitHub repository. Each member's status and audit trail live on their
/// own branch, `tethera/members/<login>`, as a single commit replaced on every update (so the
/// default branch stays clean). The team's approval rules are `policies.json` on the default
/// branch. Everything goes through `gh api`, with your own GitHub login; Tethera never reads a
/// token.
@MainActor
final class TeamSync: ObservableObject {
    static let shared = TeamSync()
    nonisolated static let branchPrefix = "tethera/members/"

    @Published private(set) var members: [MemberStatus] = []
    @Published private(set) var login: String?
    @Published private(set) var lastSync: Date?
    @Published private(set) var problem: String?
    @Published private(set) var syncing = false

    var repository: String? { fixedRepository ?? PreferencesStore.shared.value.teamRepository }
    private var fixedRepository: String?

    private var backend: TeamBackend = GitHubCLI()
    private var timer: Timer?
    private var lastPublished: Data?
    private var lastPublishAt = Date.distantPast
    /// How often the board refreshes; faster while a board pane is open.
    var boardVisible = false

    private init() {}

    /// For tests.
    init(backend: TeamBackend, repository: String) {
        self.backend = backend
        fixedRepository = repository
    }

    func start() {
        timer?.invalidate()
        guard repository != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in await TeamSync.shared.tick() }
        }
        Task { await sync(force: true) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        members = []
    }

    /// Checks a repository before joining it; returns your GitHub login.
    func check(_ repo: String) async throws -> String {
        guard repo.split(separator: "/").count == 2 else { throw TeamError(message: "Use owner/name, like acme/tethera-team.") }
        try await backend.checkAccess(repo)
        return try await backend.login()
    }

    func join(_ repo: String) {
        PreferencesStore.shared.value.teamRepository = repo
        lastPublished = nil
        start()
    }

    func leave() {
        PreferencesStore.shared.value.teamRepository = nil
        stop()
        try? FileManager.default.removeItem(at: ApprovalPolicies.teamFile)
        PolicyStore.shared.reload()
    }

    private var ticks = 0

    private func tick() async {
        ticks += 1
        // Publish when something changed (at most every 30 s), and every 10 minutes regardless;
        // read the board every 30 s while it's on screen, else every 2 minutes.
        await sync(force: boardVisible || ticks % 4 == 0)
    }

    func sync(force: Bool) async {
        guard let repo = repository, !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            let login: String
            if let known = self.login { login = known } else { login = try await backend.login() }
            self.login = login
            try await publish(repo: repo, login: login)
            if force {
                try await refreshPolicies(repo: repo)
                members = try await readMembers(repo: repo)
            }
            lastSync = Date()
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    private func publish(repo: String, login: String) async throws {
        let status = Self.status(login: login)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(status)
        var comparable = status
        comparable.updated = .distantPast
        let fingerprint = try encoder.encode(comparable)
        guard fingerprint != lastPublished || Date().timeIntervalSince(lastPublishAt) > 600 else { return }
        let month = String(JournalFile.dayName(Date()).prefix(7))
        try await backend.publish(repo, login: login, files: ["status.json": data, "audit/\(month).jsonl": Self.auditLines(since: Self.startOfMonth())])
        lastPublished = fingerprint
        lastPublishAt = Date()
    }

    private func refreshPolicies(repo: String) async throws {
        let data = try await backend.readFile(repo, path: "policies.json", ref: nil)
        if let data {
            try FileManager.default.createDirectory(at: ApprovalPolicies.teamFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: ApprovalPolicies.teamFile, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: ApprovalPolicies.teamFile)
        }
        PolicyStore.shared.reload()
    }

    private func readMembers(repo: String) async throws -> [MemberStatus] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var result: [MemberStatus] = []
        for login in try await backend.members(repo) {
            if let data = try await backend.readFile(repo, path: "status.json", ref: Self.branchPrefix + login),
               let status = try? decoder.decode(MemberStatus.self, from: data) {
                result.append(status)
            }
        }
        return result.sorted { $0.login.lowercased() < $1.login.lowercased() }
    }

    /// Every member's approvals and policy decisions this month, newest first.
    func teamAudit() async -> [(login: String, event: Journal.Event)] {
        guard let repo = repository else { return [] }
        let month = String(JournalFile.dayName(Date()).prefix(7))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var rows: [(String, Journal.Event)] = []
        for member in members {
            guard let data = try? await backend.readFile(repo, path: "audit/\(month).jsonl", ref: Self.branchPrefix + member.login) else { continue }
            for line in data.split(separator: 0x0A) {
                if let event = try? decoder.decode(Journal.Event.self, from: line) { rows.append((member.login, event)) }
            }
        }
        return rows.sorted { $0.1.at > $1.1.at }
    }

    // MARK: What you share

    static func status(login: String, sessions: [SessionInfo]? = nil, now: Date = Date()) -> MemberStatus {
        let rows = (sessions ?? DaemonClient.shared.sessions).compactMap { session -> MemberStatus.Session? in
            guard let agent = session.agent, session.host == nil else { return nil }
            let repo = WorktreeMonitor.shared.repoRoot(for: session.cwd) ?? session.cwd
            return MemberStatus.Session(name: session.name, repo: (repo as NSString).lastPathComponent, agent: agent.kind.rawValue,
                                        state: agent.state.rawValue, since: agent.since, costUSD: agent.costUSD)
        }
        return MemberStatus(login: login, mac: Host.current().localizedName ?? "Mac", updated: now, sessions: rows,
                            costs: CostReport.daily(days: 30, now: now))
    }

    static func startOfMonth(_ now: Date = Date()) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: now)) ?? now
    }

    /// This month's approvals and budget events, as journal lines.
    static func auditLines(since start: Date) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var out = Data()
        for event in Journal.shared.events(from: start) where event.kind == .approval || event.kind == .budget {
            if let line = try? encoder.encode(event) { out.append(line); out.append(0x0A) }
        }
        return out
    }
}

/// `gh api`, with the login `gh auth login` set up.
struct GitHubCLI: TeamBackend {
    static var executable: String? {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func gh(_ arguments: [String], input: Data? = nil) async throws -> Data {
        guard let executable = Self.executable else {
            throw TeamError(message: "Teams use the GitHub CLI. Install it (brew install gh) and run gh auth login.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let output = Pipe(), errors = Pipe(), stdin = Pipe()
            process.standardOutput = output
            process.standardError = errors
            process.standardInput = stdin
            process.terminationHandler = { process in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if process.terminationStatus == 0 {
                    continuation.resume(returning: data)
                } else {
                    let body = String(decoding: data, as: UTF8.self)
                    let text = [message, body].first { !$0.isEmpty } ?? "gh failed"
                    continuation.resume(throwing: TeamError(message: text.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            do {
                try process.run()
                if let input { stdin.fileHandleForWriting.write(input) }
                try? stdin.fileHandleForWriting.close()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func json(_ arguments: [String], body: [String: Any]? = nil) async throws -> Any {
        let input = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        let data = try await gh(["api"] + arguments + (input == nil ? [] : ["--input", "-"]), input: input)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    func login() async throws -> String {
        guard let user = try await json(["user"]) as? [String: Any], let login = user["login"] as? String else {
            throw TeamError(message: "Sign in to GitHub first: gh auth login.")
        }
        return login
    }

    func checkAccess(_ repo: String) async throws {
        let info: [String: Any]
        do {
            info = try await json(["repos/\(repo)"]) as? [String: Any] ?? [:]
        } catch {
            throw TeamError(message: "Can't open \(repo) on GitHub. Check the name and that you're a collaborator.")
        }
        guard (info["permissions"] as? [String: Any])?["push"] as? Bool == true else {
            throw TeamError(message: "You can see \(repo) but can't push to it; ask its owner for write access.")
        }
        if info["private"] as? Bool == false {
            throw TeamError(message: "\(repo) is public. A team repository should be private: it holds what your agents are doing.")
        }
        guard let branch = info["default_branch"] as? String,
              (try? await json(["repos/\(repo)/branches/\(branch)"])) != nil else {
            throw TeamError(message: "\(repo) is empty. Add a first commit (a README is enough), then join.")
        }
    }

    func readFile(_ repo: String, path: String, ref: String?) async throws -> Data? {
        let query = ref.map { "?ref=\($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0)" } ?? ""
        do {
            guard let file = try await json(["repos/\(repo)/contents/\(path)\(query)"]) as? [String: Any],
                  let content = file["content"] as? String else { return nil }
            return Data(base64Encoded: content.replacingOccurrences(of: "\n", with: ""))
        } catch let error as TeamError where error.message.contains("404") || error.message.contains("Not Found") {
            return nil
        }
    }

    func members(_ repo: String) async throws -> [String] {
        let refs = try await json(["repos/\(repo)/git/matching-refs/heads/\(TeamSync.branchPrefix)"]) as? [[String: Any]] ?? []
        return refs.compactMap { ($0["ref"] as? String)?.components(separatedBy: "refs/heads/" + TeamSync.branchPrefix).last }
            .filter { !$0.isEmpty }
    }

    func publish(_ repo: String, login: String, files: [String: Data]) async throws {
        let entries = files.sorted { $0.key < $1.key }.map { path, data in
            ["path": path, "mode": "100644", "type": "blob", "content": String(decoding: data, as: UTF8.self)]
        }
        guard let tree = (try await json(["-X", "POST", "repos/\(repo)/git/trees"], body: ["tree": entries]) as? [String: Any])?["sha"] as? String,
              let commit = (try await json(["-X", "POST", "repos/\(repo)/git/commits"],
                                           body: ["message": "\(login)'s Tethera status", "tree": tree, "parents": []]) as? [String: Any])?["sha"] as? String
        else { throw TeamError(message: "GitHub didn't accept the status update.") }
        let ref = TeamSync.branchPrefix + login
        do {
            _ = try await json(["-X", "PATCH", "repos/\(repo)/git/refs/heads/\(ref)"], body: ["sha": commit, "force": true])
        } catch {
            _ = try await json(["-X", "POST", "repos/\(repo)/git/refs"], body: ["ref": "refs/heads/\(ref)", "sha": commit])
        }
    }
}
