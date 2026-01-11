import Foundation
import SwiftUI
import CoreText

@MainActor
class BlockTerminalViewModel: ObservableObject, TerminalBlockDelegate {
    @Published var workingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path {
        didSet { 
            _displayWorkingDirectory = nil // Invalidate cache
            refreshGitInfo() // Refresh Git info on directory change
        }
    }
    @Published var blocks: [TerminalBlock] = []
    @Published var selectedBlockID: UUID? = nil
    @Published var isPalettePresented: Bool = false
    @Published var isSettingsPresented: Bool = false
    @Published var theme: TerminalTheme
    @Published var isRunningCommand: Bool = false // Loading state
    @Published var paletteActions: [String] = ["New Tab", "Split Pane", "Settings"]
    
    // Git integration
    @Published var gitInfo: GitInfo?
    
    // Command history with persistence
    @Published var commandHistory: [String] = []
    private var historyIndex: Int? = nil
    private var historyDraft: String = ""
    
    // PTY session for persistent shell
    private var terminalSession: TerminalSession?
    private var pendingCommand: String = ""
    private var currentBlockOutput = ""
    private var commandStartTime: Date?
    
    // Cached values for performance
    private var _displayWorkingDirectory: String?
    private static var _cachedFont: Font?
    private static let maxHistorySize = 500
    
    init() {
        // Initialize theme
        self.theme = TerminalTheme.defaultTheme
        
        // Load command history
        if let saved = UserDefaults.standard.stringArray(forKey: "command_history") {
            commandHistory = saved
        }
        
        // Initialize PTY session
        terminalSession = TerminalSession()
        terminalSession?.blockDelegate = self
        
        // Listen for settings changes
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SettingsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                if let settings = notification.object as? UserSettings {
                    self?.theme = TerminalTheme(from: settings.themeConfiguration)
                }
            }
        }
        
        // Listen for Git info changes
        NotificationCenter.default.addObserver(
            forName: .gitInfoDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.gitInfo = notification.object as? GitInfo
            }
        }
        
        // Initial Git info refresh
        refreshGitInfo()
    }
    
    // MARK: - TerminalBlockDelegate
    
    private var executingBlockID: UUID?
    
    // MARK: - TerminalBlockDelegate
    
    nonisolated func terminalDidStartPrompt() {
        Task { @MainActor in
            self.isRunningCommand = false
        }
    }
    
    nonisolated func terminalDidStartCommand() {
        Task { @MainActor in
            self.isRunningCommand = true
            self.currentBlockOutput = ""
            self.commandStartTime = Date()
        }
    }
    
    nonisolated func terminalDidReceiveOutput(_ output: String) {
        Task { @MainActor in
            self.currentBlockOutput += output
            
            // Real-time update for in-place execution
            if let id = self.executingBlockID, 
               let index = self.blocks.firstIndex(where: { $0.id == id }) {
                self.blocks[index].output += output
            }
        }
    }
    
    nonisolated func terminalDidEndCommand(exitCode: Int) {
        Task { @MainActor in
            // Calculate duration in milliseconds
            var durationMs: Int64? = nil
            if let startTime = self.commandStartTime {
                durationMs = Int64(Date().timeIntervalSince(startTime) * 1000)
            }
            
            if let id = self.executingBlockID,
               let index = self.blocks.firstIndex(where: { $0.id == id }) {
                // Update existing block
                self.blocks[index].success = exitCode == 0
                self.blocks[index].exitCode = Int32(exitCode)
                self.blocks[index].durationMs = durationMs
                self.blocks[index].timestamp = Date() // Update time to now
                
                // Ensure output is synced (though real-time should have handled it)
                if self.blocks[index].output != self.currentBlockOutput {
                   self.blocks[index].output = self.currentBlockOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                self.executingBlockID = nil
            } else {
                // Create new block
                let block = TerminalBlock(
                    input: self.pendingCommand,
                    output: self.currentBlockOutput.trimmingCharacters(in: .whitespacesAndNewlines),
                    timestamp: Date(),
                    workingDirectory: self.workingDirectory,
                    success: exitCode == 0,
                    exitCode: Int32(exitCode),
                    durationMs: durationMs
                )
                self.blocks.append(block)
                CommandHistoryManager.shared.addEntry(from: block)
            }
            
            self.pendingCommand = ""
            self.currentBlockOutput = ""
            self.commandStartTime = nil
            self.isRunningCommand = false
        }
    }
    
    nonisolated func terminalDidUpdateWorkingDirectory(_ directory: String) {
        Task { @MainActor in
            // Only update if directory actually changed and exists
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: directory, isDirectory: &isDir), isDir.boolValue {
                if self.workingDirectory != directory {
                    self.workingDirectory = directory
                }
            }
        }
    }
    
    private func saveHistoryAsync() {
        let history = Array(commandHistory.suffix(Self.maxHistorySize))
        Task.detached(priority: .utility) {
            UserDefaults.standard.set(history, forKey: "command_history")
        }
    }
    
    // MARK: - Block Management
    
    func addBlock(input: String, output: String, success: Bool? = nil) {
        let block = TerminalBlock(
            input: input,
            output: output,
            timestamp: Date(),
            workingDirectory: workingDirectory,
            success: success
        )
        blocks.append(block)
        
        // Add to global history (async internally)
        CommandHistoryManager.shared.addEntry(from: block)
    }
    
    /// Update a block's input command without running it (e.g. while editing)
    func updateBlock(id: UUID, input: String) {
        if let index = blocks.firstIndex(where: { $0.id == id }) {
            blocks[index].input = input
        }
    }
    
    /// Rerun a specific block in-place
    func rerunBlock(id: UUID, command: String) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        
        // Update input
        blocks[index].input = command
        // Clear output to prepare for new run
        blocks[index].output = ""
        blocks[index].success = nil
        blocks[index].exitCode = nil
        blocks[index].durationMs = nil
        blocks[index].timestamp = Date()
        
        // Set execution context
        executingBlockID = id
        
        // Use standard run logic (which will set pendingCommand etc)
        // Note: we must clear pendingCommand after runShellCommand returns? 
        // No, pendingCommand is used in terminalDidEndCommand.
        // runShellCommand sets pendingCommand.
        runShellCommand(command)
    }

    // MARK: - Async Command Execution (Non-blocking)
    
    func runShellCommand(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Push to history (avoid consecutive duplicates)
        if commandHistory.last != trimmed {
            commandHistory.append(trimmed)
            saveHistoryAsync()
        }
        historyIndex = nil
        historyDraft = ""
        
        // Built-in commands (instant)
        if trimmed == "clear" {
            blocks.removeAll()
            return
        }
        
        // Store pending command for block creation in delegate
        pendingCommand = trimmed
        
        // Send command to PTY session
        if let session = terminalSession {
            session.write(trimmed + "\n")
        } else {
            // Fallback to one-off Process if PTY not available
            fallbackRunCommand(trimmed, originalInput: input)
        }
    }
    
    private func fallbackRunCommand(_ command: String, originalInput: String) {
        isRunningCommand = true
        let directory = workingDirectory
        
        Task.detached(priority: .userInitiated) {
            let output = Self.runCommand(command, in: directory)
            await MainActor.run {
                self.addBlock(input: originalInput, output: output, success: nil)
                self.isRunningCommand = false
            }
        }
    }
    
    private func handleCdCommand(_ trimmed: String, originalInput: String) {
        let path = trimmed == "cd" ? "" : String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        
        let newDir: String
        if path.isEmpty || path == "~" {
            newDir = home
        } else if path.hasPrefix("/") {
            newDir = path
        } else if path.hasPrefix("~/") {
            newDir = home + String(path.dropFirst(1))
        } else {
            let tentative = (workingDirectory as NSString).appendingPathComponent(path)
            newDir = (tentative as NSString).standardizingPath
        }
        
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: newDir, isDirectory: &isDir), isDir.boolValue {
            workingDirectory = newDir
            addBlock(input: originalInput, output: "", success: true)
        } else {
            addBlock(input: originalInput, output: "cd: no such directory: \(path)", success: false)
        }
    }

    // MARK: - History Navigation
    
    func historyPrevious(currentInput: String) -> String? {
        guard !commandHistory.isEmpty else { return nil }
        if historyIndex == nil {
            historyDraft = currentInput
            historyIndex = commandHistory.count - 1
        } else if let idx = historyIndex, idx > 0 {
            historyIndex = idx - 1
        }
        return historyIndex.map { commandHistory[$0] }
    }
    
    func historyNext() -> String? {
        guard let idx = historyIndex else { return nil }
        if idx < commandHistory.count - 1 {
            historyIndex = idx + 1
            return commandHistory[historyIndex!]
        } else {
            historyIndex = nil
            let draft = historyDraft
            historyDraft = ""
            return draft
        }
    }

    // MARK: - Command Execution (Background Thread - nonisolated)
    
    nonisolated private static func runCommand(_ command: String, in directory: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.launchPath = "/bin/bash"
        process.arguments = ["-c", command]
        process.currentDirectoryPath = directory
        
        do {
            try process.run()
        } catch {
            return "Error: \(error.localizedDescription)"
        }
        
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    // MARK: - Cached Properties
    
    /// Cached display working directory (computed once, invalidated on change)
    var displayWorkingDirectory: String {
        if let cached = _displayWorkingDirectory {
            return cached
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let result: String
        if workingDirectory.hasPrefix(home) {
            let relative = String(workingDirectory.dropFirst(home.count))
            result = relative.isEmpty ? "~" : "~\(relative)"
        } else {
            result = workingDirectory
        }
        _displayWorkingDirectory = result
        return result
    }
    
    /// Cached terminal font (computed once per app lifecycle)
    func getTerminalFont() -> Font {
        if let cached = Self._cachedFont {
            return cached
        }
        let font: Font
        if FontLoader.shared.isFontAvailable("JetBrainsMono-Medium") {
            font = .custom("JetBrainsMono-Medium", size: 15)
        } else if FontLoader.shared.isFontAvailable("JetBrainsMono-Regular") {
            font = .custom("JetBrainsMono-Regular", size: 15)
        } else {
            font = .system(.body, design: .monospaced)
        }
        Self._cachedFont = font
        return font
    }
    
    // MARK: - Git Integration
    
    /// Refresh Git info for current directory (background, non-blocking)
    func refreshGitInfo() {
        Task {
            GitService.shared.refresh(for: workingDirectory)
            // Observe GitService changes
            self.gitInfo = GitService.shared.currentInfo
        }
    }
}
