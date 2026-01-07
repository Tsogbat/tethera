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
        
        // Load persisted command history from UserDefaults
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
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateTheme()
            }
        }
    }
    
    private func saveHistory() {
        let trimmed = Array(commandHistory.suffix(500))
        UserDefaults.standard.set(trimmed, forKey: "command_history")
    }
    
    private func updateTheme() {
        theme = TerminalTheme(from: userSettings.themeConfiguration)
    }

    func addBlock(input: String, output: String, success: Bool? = nil) {
        let block = TerminalBlock(input: input, output: output, timestamp: Date(), workingDirectory: workingDirectory, success: success)
        blocks.append(block)
        
        // Add to global history for search
        CommandHistoryManager.shared.addEntry(from: block)
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
            let path = trimmed == "cd" ? "" : String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            let newDir: String
            
            if path.isEmpty || path == "~" {
                // cd with no arguments or cd ~ goes to home directory
                newDir = FileManager.default.homeDirectoryForCurrentUser.path
            } else if path.hasPrefix("/") {
                // Absolute path
                newDir = path
            } else if path.hasPrefix("~/") {
                // Home directory relative path
                let homePath = FileManager.default.homeDirectoryForCurrentUser.path
                newDir = homePath + String(path.dropFirst(1))
            } else {
                // Relative path - use NSString.standardizingPath to resolve .. and .
                let tentativePath = (workingDirectory as NSString).appendingPathComponent(path)
                newDir = (tentativePath as NSString).standardizingPath
            }
            
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: newDir, isDirectory: &isDir), isDir.boolValue {
                workingDirectory = newDir
                addBlock(input: input, output: "", success: true)
            } else {
                addBlock(input: input, output: "cd: no such directory: \(path)", success: false)
            }
            return
        }
        let output = Self.runCommandSync(input, in: workingDirectory)
        addBlock(input: input, output: output, success: nil)
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
