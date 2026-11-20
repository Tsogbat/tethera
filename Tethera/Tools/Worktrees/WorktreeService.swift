import AppKit
import Foundation
import TetheraKit

/// Agents in their own git worktree: each gets a branch and a folder next to the repo, so
/// several agents can work on one repository without stepping on each other.
///
///     ~/code/api                     your checkout
///     ~/code/api.worktrees/claude-1  a worktree on branch tethera/claude-1
///
/// The branch a worktree started from is remembered in the repo's config
/// (`branch.<name>.tetheraBase`), so Merge and Open PR know where to go.
enum WorktreeService {
    struct Info: Equatable {
        /// The main checkout this worktree belongs to.
        let mainRoot: String
        /// This worktree's folder.
        let root: String
        let branch: String
        let base: String
    }

    /// Plans a new worktree: a branch name nobody uses yet, and a folder beside the repo.
    static func plan(repoRoot: String, agent: AgentKind?, existingBranches: Set<String>, existingPaths: Set<String>) -> (branch: String, path: String) {
        let name = agent?.rawValue ?? "shell"
        let container = repoRoot + ".worktrees"
        var index = 1
        while existingBranches.contains("tethera/\(name)-\(index)") || existingPaths.contains("\(container)/\(name)-\(index)") {
            index += 1
        }
        return ("tethera/\(name)-\(index)", "\(container)/\(name)-\(index)")
    }

    /// The repository's main checkout and current branch for a folder inside it.
    static func repository(at path: String) async -> (root: String, branch: String)? {
        let common = await GitService.run(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: path)
        let branch = await GitService.run(["rev-parse", "--abbrev-ref", "HEAD"], in: path)
        guard common.ok, branch.ok else { return nil }
        let gitDir = common.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return ((gitDir as NSString).deletingLastPathComponent, branch.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Creates the worktree and returns its folder.
    static func create(from folder: String, agent: AgentKind?) async throws -> Info {
        guard let repo = await repository(at: folder) else { throw Failure("Not a git repository.") }
        let branches = await GitService.run(["for-each-ref", "--format=%(refname:short)", "refs/heads"], in: repo.root)
        let worktrees = await list(repo.root)
        let (branch, path) = plan(repoRoot: repo.root, agent: agent,
                                  existingBranches: Set(branches.output.split(separator: "\n").map(String.init)),
                                  existingPaths: Set(worktrees.map(\.root)))
        let base = repo.branch == "HEAD" ? "main" : repo.branch
        let added = await GitService.run(["worktree", "add", "-b", branch, path, base], in: repo.root)
        guard added.ok else { throw Failure(added.output) }
        _ = await GitService.run(["config", "branch.\(branch).tetheraBase", base], in: repo.root)
        return Info(mainRoot: repo.root, root: path, branch: branch, base: base)
    }

    /// Every linked worktree of a repository (the main checkout excluded).
    static func list(_ mainRoot: String) async -> [Info] {
        let result = await GitService.run(["worktree", "list", "--porcelain"], in: mainRoot)
        guard result.ok else { return [] }
        var infos: [Info] = []
        var path: String?, branch: String?
        func flush() async {
            if let path, path != mainRoot, let branch {
                let base = await GitService.run(["config", "branch.\(branch).tetheraBase"], in: mainRoot)
                infos.append(Info(mainRoot: mainRoot, root: path, branch: branch,
                                  base: base.ok ? base.output.trimmingCharacters(in: .whitespacesAndNewlines) : "main"))
            }
        }
        for line in result.output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("worktree ") {
                await flush()
                path = String(line.dropFirst(9)); branch = nil
            } else if line.hasPrefix("branch refs/heads/") {
                branch = String(line.dropFirst("branch refs/heads/".count))
            }
        }
        await flush()
        return infos
    }

    /// The worktree a folder is in, if it's a linked worktree (not the main checkout).
    static func info(for folder: String) async -> Info? {
        guard let repo = await repository(at: folder) else { return nil }
        let top = await GitService.run(["rev-parse", "--show-toplevel"], in: folder)
        let root = top.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard top.ok, root != repo.root else { return nil }
        return await list(repo.root).first { $0.root == root }
    }

    // MARK: Review

    /// Merges the worktree's branch into its base in the main checkout (`--no-ff`, so the
    /// agent's work stays one visible unit).
    static func merge(_ info: Info) async throws -> String {
        let status = await GitService.run(["status", "--porcelain", "--untracked-files=no"], in: info.mainRoot)
        guard status.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure("\((info.mainRoot as NSString).lastPathComponent) has uncommitted changes. Commit or stash them first.")
        }
        let pending = await GitService.run(["status", "--porcelain"], in: info.root)
        guard pending.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure("The worktree has uncommitted changes. Commit them (or ask the agent to) before merging.")
        }
        let current = await GitService.run(["rev-parse", "--abbrev-ref", "HEAD"], in: info.mainRoot)
        if current.output.trimmingCharacters(in: .whitespacesAndNewlines) != info.base {
            let switched = await GitService.run(["switch", info.base], in: info.mainRoot)
            guard switched.ok else { throw Failure(switched.output) }
        }
        let merged = await GitService.run(["merge", "--no-ff", "--no-edit", info.branch], in: info.mainRoot)
        guard merged.ok else {
            _ = await GitService.run(["merge", "--abort"], in: info.mainRoot)
            throw Failure("The merge has conflicts, so nothing was changed. Resolve it in a session:\n\n" + merged.output)
        }
        return merged.output
    }

    /// Removes the worktree folder and its branch. Refuses unmerged work unless forced.
    static func remove(_ info: Info, force: Bool) async throws {
        let removed = await GitService.run(["worktree", "remove"] + (force ? ["--force"] : []) + [info.root], in: info.mainRoot)
        guard removed.ok else { throw Failure(removed.output) }
        let deleted = await GitService.run(["branch", force ? "-D" : "-d", info.branch], in: info.mainRoot)
        guard deleted.ok else { throw Failure("The folder is gone, but the branch \(info.branch) isn't merged, so it was kept.\n\n" + deleted.output) }
        _ = await GitService.run(["config", "--unset", "branch.\(info.branch).tetheraBase"], in: info.mainRoot)
    }

    /// Pushes the branch and opens a pull request, in a session so you see (and can answer) it.
    @MainActor
    static func openPullRequest(_ info: Info) {
        let command = "git push -u origin \(shellQuote(info.branch)) && gh pr create --fill --base \(shellQuote(info.base)) --head \(shellQuote(info.branch))"
        Workspace.shared.newSession(command: command, cwd: info.root, inNewPane: .horizontal)
    }

    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message.trimmingCharacters(in: .whitespacesAndNewlines) }
        var errorDescription: String? { message }
    }
}

/// Which sessions are in linked worktrees, cached per folder.
@MainActor
final class WorktreeMonitor: ObservableObject {
    static let shared = WorktreeMonitor()
    @Published private(set) var infos: [String: WorktreeService.Info] = [:]
    /// The main checkout each folder belongs to (for grouping sessions by repository).
    @Published private(set) var repoRoots: [String: String] = [:]
    private var checked: Set<String> = []

    func info(for cwd: String) -> WorktreeService.Info? {
        check(cwd)
        return infos[cwd]
    }

    func repoRoot(for cwd: String) -> String? {
        check(cwd)
        return repoRoots[cwd]
    }

    private func check(_ cwd: String) {
        guard !checked.contains(cwd) else { return }
        checked.insert(cwd)
        Task {
            if let repo = await WorktreeService.repository(at: cwd) { repoRoots[cwd] = repo.root }
            if let info = await WorktreeService.info(for: cwd) { infos[cwd] = info }
        }
    }

    func forget(_ info: WorktreeService.Info) {
        for (cwd, value) in infos where value == info { infos[cwd] = nil }
    }

    func remember(_ info: WorktreeService.Info) {
        infos[info.root] = info
        repoRoots[info.root] = info.mainRoot
        checked.insert(info.root)
    }
}

/// Starting an agent in a new worktree, and the review actions on one.
@MainActor
enum WorktreeActions {
    static func newAgent(_ agent: AgentKind?, from folder: String? = nil) {
        guard let folder = folder ?? Workspace.shared.focusedSession?.localFolder ?? RecentFolders.all.first else {
            alert("Open a session in a git repository first.")
            return
        }
        Task {
            do {
                let info = try await WorktreeService.create(from: folder, agent: agent)
                WorktreeMonitor.shared.remember(info)
                Workspace.shared.newSession(agent: agent, cwd: info.root)
            } catch {
                alert(error.localizedDescription)
            }
        }
    }

    static func merge(_ info: WorktreeService.Info) {
        let confirm = NSAlert()
        confirm.messageText = "Merge \(info.branch) into \(info.base)?"
        confirm.informativeText = "Tethera merges in \((info.mainRoot as NSString).lastPathComponent) with a merge commit. Nothing is pushed."
        confirm.addButton(withTitle: "Merge")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do {
                _ = try await WorktreeService.merge(info)
                alert("Merged \(info.branch) into \(info.base).", style: .informational)
            } catch {
                alert(error.localizedDescription)
            }
        }
    }

    static func remove(_ info: WorktreeService.Info) {
        let confirm = NSAlert()
        confirm.messageText = "Remove the worktree \((info.root as NSString).lastPathComponent)?"
        confirm.informativeText = "Its folder and the branch \(info.branch) are deleted. Sessions in it end. Unmerged work is kept unless you choose Remove Anyway."
        confirm.addButton(withTitle: "Remove")
        confirm.addButton(withTitle: "Remove Anyway")
        confirm.addButton(withTitle: "Cancel")
        let choice = confirm.runModal()
        guard choice != .alertThirdButtonReturn else { return }
        let force = choice == .alertSecondButtonReturn
        for session in DaemonClient.shared.sessions where session.host == nil && session.cwd.hasPrefix(info.root) {
            DaemonClient.shared.close(session.id)
        }
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            do {
                try await WorktreeService.remove(info, force: force)
                WorktreeMonitor.shared.forget(info)
            } catch {
                alert(error.localizedDescription)
            }
        }
    }

    static func alert(_ text: String, style: NSAlert.Style = .warning) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = style == .warning ? "Couldn't do that" : text
        if style == .warning { alert.informativeText = text }
        alert.runModal()
    }
}
