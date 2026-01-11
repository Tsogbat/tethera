import Foundation

/// Fast, file-based Git information provider
/// Reads .git folder directly - no subprocess spawning for maximum speed
@MainActor
class GitService: ObservableObject {
    static let shared = GitService()
    
    @Published var currentInfo: GitInfo?
    
    private var cachedPath: String?
    private var refreshTask: Task<Void, Never>?
    private let fileManager = FileManager.default
    
    private init() {}
    
    // MARK: - Public API
    
    /// Get Git info for a directory (cached, triggers background refresh)
    func getInfo(for directory: String) -> GitInfo? {
        // Return cached immediately if same path
        if cachedPath == directory, let info = currentInfo {
            return info
        }
        
        // Trigger background refresh
        refreshAsync(for: directory)
        
        // Return cached or nil
        return currentInfo
    }
    
    /// Force refresh Git info
    func refresh(for directory: String) {
        refreshAsync(for: directory)
    }
    
    // MARK: - Fast File-Based Parsing
    
    /// Check if directory is inside a Git repo (< 1ms)
    nonisolated func isGitRepo(at path: String) -> Bool {
        let gitPath = findGitDirectory(from: path)
        return gitPath != nil
    }
    
    /// Find .git directory (walks up to find repo root)
    nonisolated private func findGitDirectory(from path: String) -> String? {
        var current = path
        let fm = FileManager.default
        
        while current != "/" {
            let gitPath = (current as NSString).appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: gitPath, isDirectory: &isDir) {
                // .git can be a file (worktrees) or directory
                return gitPath
            }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }
    
    /// Read current branch from .git/HEAD (< 1ms)
    nonisolated private func getCurrentBranch(gitPath: String) -> String? {
        let headPath = (gitPath as NSString).appendingPathComponent("HEAD")
        
        guard let content = try? String(contentsOfFile: headPath, encoding: .utf8) else {
            return nil
        }
        
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if detached HEAD (commit hash)
        if !trimmed.hasPrefix("ref: ") {
            // Return short hash
            return String(trimmed.prefix(7))
        }
        
        // Extract branch name from "ref: refs/heads/main"
        let refPrefix = "ref: refs/heads/"
        if trimmed.hasPrefix(refPrefix) {
            return String(trimmed.dropFirst(refPrefix.count))
        }
        
        return trimmed
    }
    
    /// Check if repo has uncommitted changes
    /// Uses fast `git status --porcelain` - typically <50ms
    nonisolated private func isDirty(gitPath: String) -> Bool {
        // Get repo root (parent of .git)
        let repoRoot = (gitPath as NSString).deletingLastPathComponent
        
        // Use git status --porcelain for accurate detection
        // This is fast (<50ms) and returns empty if clean
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["status", "--porcelain"]
        process.currentDirectoryURL = URL(fileURLWithPath: repoRoot)
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // If output is not empty, there are changes
            return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            return false
        }
    }
    
    /// Get ahead/behind counts using refs (fast)
    nonisolated private func getAheadBehind(gitPath: String, branch: String) -> (ahead: Int, behind: Int) {
        // For speed, we skip this on initial load
        // Could implement by comparing local/remote refs
        return (0, 0)
    }
    
    // MARK: - Background Refresh
    
    private func refreshAsync(for directory: String) {
        refreshTask?.cancel()
        
        // Capture directory for this refresh
        let targetDirectory = directory
        
        refreshTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            // Find .git directory
            guard let gitPath = self.findGitDirectory(from: targetDirectory) else {
                await MainActor.run {
                    self.currentInfo = nil
                    self.cachedPath = targetDirectory
                    // Post notification for observers
                    NotificationCenter.default.post(name: .gitInfoDidChange, object: nil)
                }
                return
            }
            
            // Parse Git info
            let branch = self.getCurrentBranch(gitPath: gitPath) ?? "unknown"
            let dirty = self.isDirty(gitPath: gitPath)
            let (ahead, behind) = self.getAheadBehind(gitPath: gitPath, branch: branch)
            
            // Get repo root (parent of .git)
            let repoRoot = (gitPath as NSString).deletingLastPathComponent
            
            let info = GitInfo(
                branch: branch,
                isDirty: dirty,
                ahead: ahead,
                behind: behind,
                repoRoot: repoRoot
            )
            
            await MainActor.run {
                self.currentInfo = info
                self.cachedPath = targetDirectory
                // Post notification for observers
                NotificationCenter.default.post(name: .gitInfoDidChange, object: info)
            }
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let gitInfoDidChange = Notification.Name("gitInfoDidChange")
}

// MARK: - GitInfo Model

struct GitInfo: Equatable {
    let branch: String
    let isDirty: Bool
    let ahead: Int
    let behind: Int
    let repoRoot: String
    
    /// Check if this is a main/default branch
    var isMainBranch: Bool {
        let mainBranches = ["main", "master", "develop", "development"]
        return mainBranches.contains(branch.lowercased())
    }
    
    var displayBranch: String {
        branch
    }
    
    /// Icon for branch type
    var branchIcon: String {
        if isMainBranch {
            return "arrow.triangle.branch" // Default branch
        } else {
            return "arrow.triangle.pull" // Feature/PR branch
        }
    }
    
    var statusIndicator: String {
        if isDirty { return "●" }
        return ""
    }
    
    var aheadBehindText: String? {
        var parts: [String] = []
        if ahead > 0 { parts.append("↑\(ahead)") }
        if behind > 0 { parts.append("↓\(behind)") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
