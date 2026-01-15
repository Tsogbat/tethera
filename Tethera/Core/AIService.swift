import Foundation
import OSLog

// MARK: - AI Service (Stage 2-6 Infrastructure)
// This service implements the roadmap's AI layer with strict safety rules

/// AI Service for terminal assistance (Never auto-executes - Stage 7 Rule 1)
@MainActor
class AIService: ObservableObject {
    static let shared = AIService()
    
    @Published var isProcessing = false
    @Published var lastResponse: AIResponse? = nil
    @Published var isOnline = true
    
    private var userSettings: UserSettings?
    private let logger = Logger(subsystem: "com.tethera.app", category: "AIService")
    
    private init() {}
    
    func configure(with settings: UserSettings) {
        self.userSettings = settings
    }
    
    // MARK: - Stage 2: Inline Command Help
    
    /// Get explanation for a command (Stage 2: Inline Command Help)
    /// Returns explanation without executing anything
    func explainCommand(_ command: String) async -> AIResponse {
        guard let settings = userSettings, settings.aiSettings.isEnabled else {
            return AIResponse(
                type: .explanation,
                content: "AI is disabled. Enable in Settings to use this feature.",
                isOffline: true
            )
        }
        
        // Try online first, fallback to offline if needed
        if settings.aiSettings.allowNetworkCalls && isOnline {
            return await getOnlineExplanation(command)
        } else if settings.aiSettings.enableOfflineFallback {
            return await getOfflineExplanation(command)
        }
        
        return AIResponse(
            type: .explanation,
            content: "AI is configured but offline mode is disabled.",
            isOffline: true
        )
    }
    
    /// Get explanation for command flags (Stage 2: Flag & Parameter Explanation)
    func explainFlags(for command: String) async -> AIResponse {
        guard let settings = userSettings, settings.aiSettings.isEnabled else {
            return .disabled
        }
        
        if settings.aiSettings.enableOfflineFallback {
            return await parseManPage(for: command)
        }
        
        return .disabled
    }
    
    // MARK: - Stage 2: Error Explanation
    
    /// Explain a command failure (Stage 2: Error Explanation + Fix Path)
    /// Returns diagnostic info without auto-running anything
    func explainError(command: String, output: String, exitCode: Int32) async -> AIResponse {
        guard let settings = userSettings,
              settings.aiSettings.isEnabled,
              settings.aiSettings.showErrorExplanations else {
            return .disabled
        }
        
        // Parse common error patterns locally first
        let localExplanation = parseLocalError(output: output, exitCode: exitCode)
        
        if !localExplanation.isEmpty {
            return AIResponse(
                type: .errorExplanation,
                content: localExplanation,
                suggestedCommands: suggestFixes(for: command, output: output),
                isOffline: true,
                requiresConfirmation: true // Stage 7 Rule 2: User sees command before execution
            )
        }
        
        // Fallback to man page parsing
        let baseCommand = command.split(separator: " ").first.map(String.init) ?? command
        return await parseManPage(for: baseCommand)
    }
    
    // MARK: - Stage 3: Command Generation
    
    /// Generate a command from natural language (Stage 3: Generate Commands with Guardrails)
    /// NEVER auto-executes - user must confirm (Stage 7 Rule 1)
    func generateCommand(from prompt: String, context: CommandContext) async -> AIResponse {
        guard let settings = userSettings,
              settings.aiSettings.isEnabled,
              settings.aiSettings.enableCommandGeneration else {
            return .disabled
        }
        
        // This would integrate with the AI provider
        // For now, return a placeholder that requires confirmation
        return AIResponse(
            type: .commandSuggestion,
            content: "Command generation requires AI provider configuration.",
            suggestedCommands: [],
            isOffline: true,
            requiresConfirmation: true
        )
    }
    
    // MARK: - Stage 7: Safety Checks
    
    /// Check if a command is potentially destructive (Stage 7 Rule 4)
    func isDestructiveCommand(_ command: String) -> Bool {
        guard let settings = userSettings else { return false }
        
        let firstWord = command.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
        return settings.aiSettings.destructiveCommands.contains(firstWord)
    }
    
    /// Get warning message for destructive commands
    func getDestructiveWarning(for command: String) -> String? {
        guard let settings = userSettings,
              settings.aiSettings.warnOnDestructiveOps,
              isDestructiveCommand(command) else {
            return nil
        }
        
        let firstWord = command.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
        
        switch firstWord {
        case "rm":
            if command.contains("-rf") || command.contains("-r") {
                return "⚠️ This command will recursively delete files. This action cannot be undone."
            }
            return "⚠️ This command will delete files. This action cannot be undone."
        case "sudo":
            return "⚠️ This command requires elevated privileges and may modify system files."
        case "kill", "killall":
            return "⚠️ This command will terminate processes."
        default:
            return "⚠️ This command may have destructive effects."
        }
    }
    
    // MARK: - Offline Fallback (Stage 2)
    
    /// Parse man page for command explanation (Offline fallback)
    private func parseManPage(for command: String) async -> AIResponse {
        let result = await Task.detached(priority: .utility) { () -> (output: String, status: Int32, error: Error?) in
            let process = Process()
            let pipe = Pipe()
            
            process.executableURL = URL(fileURLWithPath: "/usr/bin/man")
            process.arguments = [command]
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                return (output, process.terminationStatus, nil)
            } catch {
                return ("", -1, error)
            }
        }.value
        
        if let error = result.error {
            logger.error("man failed: \(error.localizedDescription)")
            return AIResponse(
                type: .explanation,
                content: "Could not retrieve manual page for '\(command)'.",
                isOffline: true
            )
        }
        
        if result.status != 0 || result.output.isEmpty {
            return AIResponse(
                type: .explanation,
                content: "No manual entry found for '\(command)'.",
                isOffline: true
            )
        }
        
        let summary = extractManSummary(from: result.output)
        return AIResponse(
            type: .explanation,
            content: summary.isEmpty ? "No manual entry found for '\(command)'." : summary,
            isOffline: true
        )
    }
    
    private func extractManSummary(from manOutput: String) -> String {
        // Remove ANSI escape codes and extract useful content
        let cleaned = manOutput.replacingOccurrences(of: ".\u{0008}", with: "")
            .replacingOccurrences(of: "_\u{0008}", with: "")
        
        // Extract first few paragraphs
        let lines = cleaned.components(separatedBy: .newlines)
        var result: [String] = []
        var foundName = false
        var lineCount = 0
        
        for line in lines {
            if line.contains("NAME") {
                foundName = true
                continue
            }
            if foundName && lineCount < 10 && !line.isEmpty {
                result.append(line.trimmingCharacters(in: .whitespaces))
                lineCount += 1
            }
            if line.contains("DESCRIPTION") && !result.isEmpty {
                break
            }
        }
        
        return result.joined(separator: "\n")
    }
    
    private func getOnlineExplanation(_ command: String) async -> AIResponse {
        // Placeholder for online AI provider integration
        // Would implement API calls to Claude/OpenAI/Gemini here
        return await parseManPage(for: command.split(separator: " ").first.map(String.init) ?? command)
    }
    
    private func getOfflineExplanation(_ command: String) async -> AIResponse {
        let baseCommand = command.split(separator: " ").first.map(String.init) ?? command
        return await parseManPage(for: baseCommand)
    }
    
    // MARK: - Local Error Parsing
    
    private func parseLocalError(output: String, exitCode: Int32) -> String {
        let lowercased = output.lowercased()
        
        if lowercased.contains("command not found") {
            return "The command was not found. It may not be installed or not in your PATH."
        }
        if lowercased.contains("permission denied") {
            return "Permission denied. You may need to use 'sudo' or check file permissions."
        }
        if lowercased.contains("no such file or directory") {
            return "The specified file or directory does not exist. Check the path and try again."
        }
        if lowercased.contains("is a directory") {
            return "The target is a directory, not a file. You may need different flags or commands."
        }
        if lowercased.contains("connection refused") {
            return "Connection was refused. The target service may not be running."
        }
        if lowercased.contains("timeout") {
            return "The operation timed out. Check network connectivity or try again."
        }
        
        return ""
    }
    
    private func suggestFixes(for command: String, output: String) -> [String] {
        var suggestions: [String] = []
        let lowercased = output.lowercased()
        
        if lowercased.contains("command not found") {
            let cmdName = command.split(separator: " ").first.map(String.init) ?? ""
            suggestions.append("which \(cmdName)")
            suggestions.append("brew search \(cmdName)")
        }
        
        if lowercased.contains("permission denied") {
            suggestions.append("sudo \(command)")
            let path = extractPath(from: output)
            if let path = path {
                suggestions.append("ls -la \(path)")
            }
        }
        
        if lowercased.contains("no such file or directory") {
            let path = extractPath(from: output)
            if let path = path {
                let parentPath = (path as NSString).deletingLastPathComponent
                suggestions.append("ls -la \(parentPath)")
            }
        }
        
        return suggestions
    }
    
    private func extractPath(from output: String) -> String? {
        // Try to extract a file path from error message
        let patterns = [
            #"'([^']+)'"#,  // Single quotes
            #""([^"]+)""#,   // Double quotes
            #": ([^\s:]+)"#  // After colon
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) {
                if match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: output) {
                    let path = String(output[range])
                    if path.contains("/") {
                        return path
                    }
                }
            }
        }
        return nil
    }
}

// MARK: - AI Response Model

struct AIResponse {
    enum ResponseType {
        case explanation
        case errorExplanation
        case commandSuggestion
        case blockSummary
        case disabled
    }
    
    let type: ResponseType
    let content: String
    var suggestedCommands: [String] = []
    let isOffline: Bool
    var requiresConfirmation: Bool = false
    
    static let disabled = AIResponse(
        type: .disabled,
        content: "AI features are disabled.",
        isOffline: true
    )
}

// MARK: - Command Context (for AI suggestions)

struct CommandContext {
    let workingDirectory: String
    let recentCommands: [String]
    let fileList: [String]?
    
    init(workingDirectory: String, recentCommands: [String] = [], fileList: [String]? = nil) {
        self.workingDirectory = workingDirectory
        self.recentCommands = recentCommands
        self.fileList = fileList
    }
}
