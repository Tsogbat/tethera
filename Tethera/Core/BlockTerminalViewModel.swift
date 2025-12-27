import Foundation
import SwiftUI
import CoreText

@MainActor
class BlockTerminalViewModel: ObservableObject {
    @Published var workingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    @Published var blocks: [TerminalBlock] = []
    @Published var selectedBlockID: UUID? = nil
    @Published var isPalettePresented: Bool = false
    @Published var isSettingsPresented: Bool = false
    @Published var theme: TerminalTheme
    private var userSettings = UserSettings()
    @Published var paletteActions: [String] = ["New Tab", "Split Pane", "Settings"]
    
    // Command history with persistence (Stage 1: History metadata)
    @Published var commandHistory: [String] = []
    private var historyIndex: Int? = nil
    private var historyDraft: String = ""
    
    // Persistent history storage key
    private static let historyKey = "TetheraCommandHistory"
    private static let maxHistorySize = 500
    
    init() {
        // Initialize theme from user settings
        self.theme = TerminalTheme(from: userSettings.themeConfiguration)
        
        // Load the JetBrains Mono font
        FontLoader.shared.loadJetBrainsMono()
        
        // Load persisted command history (Stage 1: History persistence)
        loadHistory()
        
        // Demo block so UI is not blank
        blocks.append(TerminalBlock.example)
        
        // Listen for settings changes
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SettingsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateTheme()
            }
        }
    }
    
    // Note: History is saved immediately on each command via saveHistory()
    
    private func updateTheme() {
        theme = TerminalTheme(from: userSettings.themeConfiguration)
    }
    
    // MARK: - History Persistence (Stage 1)
    
    private func loadHistory() {
        if let savedHistory = UserDefaults.standard.stringArray(forKey: Self.historyKey) {
            commandHistory = savedHistory
        }
    }
    
    private static func saveHistoryToDefaults(_ history: [String]) {
        // Keep only the last N entries
        let trimmed = Array(history.suffix(maxHistorySize))
        UserDefaults.standard.set(trimmed, forKey: historyKey)
    }
    
    private func saveHistory() {
        Self.saveHistoryToDefaults(commandHistory)
    }

    func addBlock(input: String, output: String, success: Bool? = nil, exitCode: Int32? = nil, durationMs: Int64? = nil) {
        let block = TerminalBlock(
            input: input,
            output: output,
            timestamp: Date(),
            workingDirectory: workingDirectory,
            success: success ?? (exitCode == 0),
            exitCode: exitCode,
            durationMs: durationMs
        )
        blocks.append(block)
    }

    /// Run a shell command and append a new block with the result
    func runShellCommand(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Push to history (avoid consecutive duplicates)
        if !trimmed.isEmpty {
            if commandHistory.last != trimmed { 
                commandHistory.append(trimmed)
                saveHistory()
            }
            historyIndex = nil
            historyDraft = ""
        }
        
        // Built-in commands
        if trimmed == "clear" {
            blocks.removeAll()
            return
        }
        
        if trimmed.hasPrefix("cd ") || trimmed == "cd" {
            handleCdCommand(trimmed)
            return
        }
        
        // Execute external command with timing (Stage 2: Exit code capture)
        let result = Self.runCommandSyncWithMetadata(trimmed, in: workingDirectory)
        addBlock(
            input: trimmed,
            output: result.output,
            success: result.exitCode == 0,
            exitCode: result.exitCode,
            durationMs: result.durationMs
        )
    }
    
    /// Handle cd command separately
    private func handleCdCommand(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = trimmed == "cd" ? "" : String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        let newDir: String
        
        if path.isEmpty || path == "~" {
            newDir = FileManager.default.homeDirectoryForCurrentUser.path
        } else if path.hasPrefix("/") {
            newDir = path
        } else if path.hasPrefix("~/") {
            let homePath = FileManager.default.homeDirectoryForCurrentUser.path
            newDir = homePath + String(path.dropFirst(1))
        } else {
            let tentativePath = (workingDirectory as NSString).appendingPathComponent(path)
            newDir = (tentativePath as NSString).standardizingPath
        }
        
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: newDir, isDirectory: &isDir), isDir.boolValue {
            workingDirectory = newDir
            addBlock(input: input, output: "", success: true, exitCode: 0, durationMs: 0)
        } else {
            addBlock(input: input, output: "cd: no such directory: \(path)", success: false, exitCode: 1, durationMs: 0)
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
        if let idx = historyIndex { return commandHistory[idx] }
        return nil
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

    /// Synchronously run a shell command and return its output
    static func runCommandSync(_ command: String, in directory: String) -> String {
        let result = runCommandSyncWithMetadata(command, in: directory)
        return result.output
    }
    
    /// Command execution result with metadata (Stage 2: Enhanced command tracking)
    struct CommandResult {
        let output: String
        let exitCode: Int32
        let durationMs: Int64
    }
    
    /// Synchronously run a shell command and return output with metadata
    static func runCommandSyncWithMetadata(_ command: String, in directory: String) -> CommandResult {
        let startTime = DispatchTime.now()
        
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
            let endTime = DispatchTime.now()
            let durationMs = Int64((endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000)
            return CommandResult(output: "Error: \(error.localizedDescription)", exitCode: -1, durationMs: durationMs)
        }
        
        process.waitUntilExit()
        
        let endTime = DispatchTime.now()
        let durationMs = Int64((endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000)
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        return CommandResult(output: output, exitCode: process.terminationStatus, durationMs: durationMs)
    }


    
    /// Get a shortened working directory for display
    var displayWorkingDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if workingDirectory.hasPrefix(home) {
            let relativePath = String(workingDirectory.dropFirst(home.count))
            if relativePath.isEmpty {
                return "~"
            } else {
                return "~\(relativePath)"
            }
        }
        return workingDirectory
    }
    
    /// Get the appropriate font for the current system
    func getTerminalFont() -> Font {
        if FontLoader.shared.isFontAvailable("JetBrainsMono-Medium") {
            return .custom("JetBrainsMono-Medium", size: 15)
        } else if FontLoader.shared.isFontAvailable("JetBrainsMono-Regular") {
            return .custom("JetBrainsMono-Regular", size: 15)
        } else {
            return .system(.body, design: .monospaced)
        }
    }
}
