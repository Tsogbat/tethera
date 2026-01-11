import Foundation
import SwiftUI

// MARK: - Command Category (Stage 2-3 AI Context)
enum CommandCategory: String, Codable {
    case fileOperation = "file"
    case navigation = "navigation"
    case gitOperation = "git"
    case packageManager = "package"
    case process = "process"
    case networkOperation = "network"
    case development = "development"
    case shell = "shell"
    case media = "media"
    case unknown = "unknown"
    
    static func categorize(_ command: String) -> CommandCategory {
        let firstWord = command.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
        
        switch firstWord {
        case "ls", "cat", "less", "more", "rm", "cp", "mv", "mkdir", "rmdir", "touch", "find", "grep", "chmod", "chown":
            return .fileOperation
        case "cd", "pwd", "pushd", "popd":
            return .navigation
        case "git":
            return .gitOperation
        case "npm", "yarn", "brew", "pip", "pip3", "gem", "cargo", "apt", "yum":
            return .packageManager
        case "ps", "top", "kill", "killall", "jobs", "bg", "fg", "nohup":
            return .process
        case "curl", "wget", "ssh", "scp", "ping", "nc", "netstat":
            return .networkOperation
        case "swift", "python", "python3", "node", "ruby", "go", "make", "gcc", "clang":
            return .development
        case "echo", "export", "source", "alias", "unalias", "history", "clear", "exit":
            return .shell
        case "preview", "show":
            return .media
        default:
            return .unknown
        }
    }
}

// MARK: - Terminal Block Model (Enhanced for Roadmap Stages 2-3)
struct TerminalBlock: Identifiable, Codable {
    let id: UUID
    var input: String
    var output: String
    var timestamp: Date
    var workingDirectory: String?
    var success: Bool?
    
    // Stage 2: Enhanced metadata for AI features
    var exitCode: Int32?
    var durationMs: Int64?
    var category: CommandCategory
    
    // Stage 3: Block summary support (for AI-generated summaries)
    var summary: String?
    var isExpanded: Bool = true
    
    // Media preview support
    var mediaFiles: [String]? // File paths for image/media preview
    
    /// Whether this block has media to display
    var hasMedia: Bool {
        guard let files = mediaFiles else { return false }
        return !files.isEmpty
    }
    
    /// Whether this block's output should be rendered as markdown
    var isMarkdownContent: Bool {
        // Check if command is reading a markdown file
        let mdFilePattern = input.contains(".md") || input.contains(".markdown")
        if mdFilePattern && (input.hasPrefix("cat ") || input.hasPrefix("less ") || input.hasPrefix("more ") || input.hasPrefix("bat ")) {
            return true
        }
        return false
    }
    
    init(
        id: UUID = UUID(),
        input: String,
        output: String,
        timestamp: Date = Date(),
        workingDirectory: String? = nil,
        success: Bool? = nil,
        exitCode: Int32? = nil,
        durationMs: Int64? = nil,
        summary: String? = nil,
        mediaFiles: [String]? = nil
    ) {
        self.id = id
        self.input = input
        self.output = output
        self.timestamp = timestamp
        self.workingDirectory = workingDirectory
        self.success = success
        self.exitCode = exitCode
        self.durationMs = durationMs
        self.category = CommandCategory.categorize(input)
        self.summary = summary
        self.mediaFiles = mediaFiles
    }
    
    // MARK: - Computed Properties
    
    /// Human-readable duration string
    var formattedDuration: String? {
        guard let ms = durationMs else { return nil }
        if ms < 1000 {
            return "\(ms)ms"
        } else if ms < 60000 {
            return String(format: "%.1fs", Double(ms) / 1000.0)
        } else {
            let minutes = ms / 60000
            let seconds = (ms % 60000) / 1000
            return "\(minutes)m \(seconds)s"
        }
    }
    
    /// Auto-generated summary based on output (Stage 3 preparation)
    var autoSummary: String {
        if let summary = summary { return summary }
        
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        let lineCount = lines.count
        
        if output.isEmpty || lineCount == 0 {
            return success == true ? "Completed successfully" : "No output"
        }
        
        // Generate smart summary based on category and output
        switch category {
        case .fileOperation:
            if input.hasPrefix("ls") {
                return "\(lineCount) items listed"
            } else if input.hasPrefix("grep") {
                return "\(lineCount) matches found"
            }
        case .gitOperation:
            if input.contains("status") {
                if output.contains("nothing to commit") {
                    return "Working tree clean"
                } else if output.contains("Changes to be committed") {
                    return "Staged changes present"
                }
            }
        default:
            break
        }
        
        // Default: show first line or line count
        if lineCount == 1 {
            return String(lines.first?.prefix(50) ?? "")
        }
        return "\(lineCount) lines of output"
    }
    
    /// Status indicator icon
    var statusIcon: String {
        if let success = success {
            return success ? "checkmark.circle.fill" : "xmark.circle.fill"
        }
        if let exitCode = exitCode {
            return exitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill"
        }
        return "circle"
    }
    
    /// Status color
    var statusColor: SwiftUI.Color {
        if let success = success {
            return success ? .green : .red
        }
        if let exitCode = exitCode {
            return exitCode == 0 ? .green : .red
        }
        return .gray
    }
}

extension TerminalBlock {
    static var example: TerminalBlock {
        TerminalBlock(
            input: "ls -l",
            output: "total 0\ndrwxr-xr-x  2 user  staff  64 Aug 22 10:00 Documents",
            timestamp: Date(),
            workingDirectory: "/Users/user",
            success: true,
            exitCode: 0,
            durationMs: 42
        )
    }
}
