import Foundation
import SwiftUI
import CoreText

@MainActor
class BlockTerminalViewModel: ObservableObject {
    @Published var workingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path {
        didSet { _displayWorkingDirectory = nil } // Invalidate cache
    }
    @Published var blocks: [TerminalBlock] = []
    @Published var selectedBlockID: UUID? = nil
    @Published var isPalettePresented: Bool = false
    @Published var isSettingsPresented: Bool = false
    @Published var theme: TerminalTheme
    @Published var isRunningCommand: Bool = false // Loading state
    @Published var paletteActions: [String] = ["New Tab", "Split Pane", "Settings"]
    
    // Command history with persistence
    @Published var commandHistory: [String] = []
    private var historyIndex: Int? = nil
    private var historyDraft: String = ""
    
    // Cached values for performance
    private var _displayWorkingDirectory: String?
    private static var _cachedFont: Font?
    private static let maxHistorySize = 500
    
    init() {
        // Initialize theme - use shared UserSettings when available via EnvironmentObject
        self.theme = TerminalTheme.defaultTheme
        
        // Load command history (fonts loaded at app startup, not here)
        if let saved = UserDefaults.standard.stringArray(forKey: "command_history") {
            commandHistory = saved
        }
        
        // Demo block so UI is not blank
        blocks.append(TerminalBlock.example)
        
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
    }
    
    // MARK: - History Management (Async Save)
    
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
        
        // Handle cd command (instant, no async needed)
        if trimmed.hasPrefix("cd ") || trimmed == "cd" {
            handleCdCommand(trimmed, originalInput: input)
            return
        }
        
        // External commands - run async
        isRunningCommand = true
        let directory = workingDirectory
        
        Task.detached(priority: .userInitiated) {
            let output = Self.runCommand(trimmed, in: directory)
            await MainActor.run {
                self.addBlock(input: input, output: output, success: nil)
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
}
