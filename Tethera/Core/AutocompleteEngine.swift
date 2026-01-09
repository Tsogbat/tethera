import Foundation

/// Warp-style autocompletion engine with two modes:
/// 1. Inline ghost completion (→ to accept)
/// 2. Tab dropdown suggestions (Tab to show, arrows to navigate)
class AutocompleteEngine: ObservableObject {
    // MARK: - Published State
    
    /// Ghost text shown inline after cursor (accept with → key)
    @Published var inlineCompletion: String = ""
    
    /// Dropdown suggestions shown when Tab is pressed
    @Published var dropdownSuggestions: [AutocompleteSuggestion] = []
    
    /// Whether dropdown is currently visible
    @Published var isDropdownVisible = false
    
    /// Currently selected suggestion in dropdown
    @Published var selectedIndex = 0
    
    // MARK: - Static Data
    
    private let commonCommands = [
        "ls", "cd", "pwd", "mkdir", "rmdir", "rm", "cp", "mv", "cat", "less", "more",
        "grep", "find", "which", "man", "clear", "exit", "history",
        "chmod", "chown", "touch", "file", "tar", "curl", "wget", "ssh", "scp",
        "git", "npm", "node", "python", "python3", "pip", "brew", "make", "swift",
        "vim", "nano", "code", "open", "pbcopy", "pbpaste", "echo", "export"
    ]
    
    private let commandSubcommands: [String: [String]] = [
        "git": ["status", "add", "commit", "push", "pull", "clone", "branch", "checkout", "merge", "log", "diff", "stash", "reset"],
        "npm": ["install", "start", "run", "test", "build", "init", "update", "uninstall"],
        "docker": ["run", "build", "pull", "push", "ps", "images", "stop", "start", "rm"],
        "brew": ["install", "uninstall", "update", "upgrade", "list", "search", "info"],
    ]
    
    private let fileManager = FileManager.default
    
    // MARK: - Inline Completion (Ghost Text)
    
    /// Update inline ghost text based on current input
    /// Called on every keystroke
    func updateInlineCompletion(for input: String, history: [String]) {
        guard !input.isEmpty else {
            DispatchQueue.main.async { self.inlineCompletion = "" }
            return
        }
        
        // Priority 1: Match from command history
        if let historyMatch = findHistoryMatch(input: input, history: history) {
            DispatchQueue.main.async { self.inlineCompletion = historyMatch }
            return
        }
        
        // Priority 2: Complete command names
        let components = input.split(separator: " ", omittingEmptySubsequences: false)
        if components.count == 1, let command = components.first {
            if let match = commonCommands.first(where: { $0.hasPrefix(String(command).lowercased()) && $0 != String(command).lowercased() }) {
                let completion = String(match.dropFirst(command.count))
                DispatchQueue.main.async { self.inlineCompletion = input + completion }
                return
            }
        }
        
        // Priority 3: Command subcommands (e.g., "git " -> "git status")
        if components.count == 2, let cmd = components.first, components.last?.isEmpty == true {
            if let subcommands = commandSubcommands[String(cmd).lowercased()], let first = subcommands.first {
                DispatchQueue.main.async { self.inlineCompletion = input + first }
                return
            }
        }
        
        DispatchQueue.main.async { self.inlineCompletion = "" }
    }
    
    private func findHistoryMatch(input: String, history: [String]) -> String? {
        // Find most recent history entry that starts with input
        let lowercaseInput = input.lowercased()
        for entry in history.reversed() {
            if entry.lowercased().hasPrefix(lowercaseInput) && entry.lowercased() != lowercaseInput {
                return entry
            }
        }
        return nil
    }
    
    // MARK: - Dropdown Suggestions (Tab Menu)
    
    /// Show dropdown suggestions when Tab is pressed
    func showDropdownSuggestions(for input: String, workingDirectory: String) {
        let suggestions = generateSuggestions(for: input, workingDirectory: workingDirectory)
        
        DispatchQueue.main.async {
            self.dropdownSuggestions = suggestions
            self.isDropdownVisible = !suggestions.isEmpty
            self.selectedIndex = 0
        }
    }
    
    /// Hide the dropdown
    func hideDropdown() {
        DispatchQueue.main.async {
            self.isDropdownVisible = false
            self.dropdownSuggestions = []
            self.selectedIndex = 0
        }
    }
    
    /// Toggle dropdown visibility
    func toggleDropdown(for input: String, workingDirectory: String) {
        if isDropdownVisible {
            hideDropdown()
        } else {
            showDropdownSuggestions(for: input, workingDirectory: workingDirectory)
        }
    }
    
    /// Navigate dropdown with arrow keys
    func navigateDown() {
        guard !dropdownSuggestions.isEmpty else { return }
        DispatchQueue.main.async {
            self.selectedIndex = min(self.selectedIndex + 1, self.dropdownSuggestions.count - 1)
        }
    }
    
    func navigateUp() {
        guard !dropdownSuggestions.isEmpty else { return }
        DispatchQueue.main.async {
            self.selectedIndex = max(self.selectedIndex - 1, 0)
        }
    }
    
    /// Get currently selected suggestion
    func getSelectedSuggestion() -> AutocompleteSuggestion? {
        guard isDropdownVisible, selectedIndex < dropdownSuggestions.count else { return nil }
        return dropdownSuggestions[selectedIndex]
    }
    
    /// Apply a suggestion to the input, preserving path prefix for directory traversal
    func applySuggestion(_ suggestion: AutocompleteSuggestion, to input: String) -> String {
        let components = input.split(separator: " ", omittingEmptySubsequences: false)
        
        guard components.count > 1, let lastComponent = components.last else {
            // Single word - replace entirely
            return suggestion.text + (suggestion.type == .directory ? "/" : "")
        }
        
        let prefix = String(lastComponent)
        let suffix = suggestion.type == .directory ? "/" : ""
        
        // Check if the prefix contains a path (has /)
        if prefix.contains("/") {
            // Preserve the directory path, only replace the last segment
            let pathParts = prefix.split(separator: "/", omittingEmptySubsequences: false)
            if pathParts.count > 1 {
                // Keep everything before the last segment
                let pathPrefix = pathParts.dropLast().joined(separator: "/") + "/"
                var newComponents = Array(components.dropLast())
                newComponents.append(Substring(pathPrefix + suggestion.text + suffix))
                return newComponents.joined(separator: " ")
            }
        }
        
        // No path prefix - just replace last component
        var newComponents = Array(components.dropLast())
        newComponents.append(Substring(suggestion.text + suffix))
        return newComponents.joined(separator: " ")
    }
    
    // MARK: - Suggestion Generation
    
    private func generateSuggestions(for input: String, workingDirectory: String) -> [AutocompleteSuggestion] {
        guard !input.isEmpty else { return [] }
        
        let components = input.split(separator: " ", omittingEmptySubsequences: false)
        let lastComponent = String(components.last ?? "")
        
        var suggestions: [AutocompleteSuggestion] = []
        
        if components.count == 1 {
            // Suggest commands
            suggestions = commonCommands
                .filter { $0.hasPrefix(lastComponent.lowercased()) }
                .prefix(15)
                .map { AutocompleteSuggestion(text: $0, type: .command, description: "Command") }
        } else {
            // Suggest paths/files
            suggestions = getPathSuggestions(prefix: lastComponent, workingDirectory: workingDirectory)
            
            // Also suggest subcommands
            let cmd = String(components.first ?? "").lowercased()
            if let subcommands = commandSubcommands[cmd] {
                let subcmdSuggestions = subcommands
                    .filter { $0.hasPrefix(lastComponent.lowercased()) }
                    .map { AutocompleteSuggestion(text: $0, type: .command, description: "Subcommand") }
                suggestions.insert(contentsOf: subcmdSuggestions, at: 0)
            }
        }
        
        return Array(suggestions.prefix(20))
    }
    
    private func getPathSuggestions(prefix: String, workingDirectory: String) -> [AutocompleteSuggestion] {
        var suggestions: [AutocompleteSuggestion] = []
        
        let searchDir: String
        let searchPrefix: String
        
        if prefix.contains("/") {
            let parts = prefix.split(separator: "/", omittingEmptySubsequences: false)
            searchPrefix = String(parts.last ?? "")
            
            if prefix.hasPrefix("/") {
                searchDir = "/" + parts.dropLast().joined(separator: "/")
            } else if prefix.hasPrefix("~") {
                let home = fileManager.homeDirectoryForCurrentUser.path
                searchDir = home + "/" + parts.dropFirst().dropLast().joined(separator: "/")
            } else {
                searchDir = workingDirectory + "/" + parts.dropLast().joined(separator: "/")
            }
        } else {
            searchDir = workingDirectory
            searchPrefix = prefix
        }
        
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: searchDir)
            for item in contents where !item.hasPrefix(".") {
                if searchPrefix.isEmpty || item.lowercased().hasPrefix(searchPrefix.lowercased()) {
                    var isDirectory: ObjCBool = false
                    let fullPath = (searchDir as NSString).appendingPathComponent(item)
                    fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory)
                    
                    suggestions.append(AutocompleteSuggestion(
                        text: item,
                        type: isDirectory.boolValue ? .directory : .file,
                        description: isDirectory.boolValue ? "Directory" : "File"
                    ))
                }
            }
        } catch {
            // Ignore errors
        }
        
        return suggestions.sorted { $0.text < $1.text }
    }
    
    /// Clear all completion state
    func clear() {
        DispatchQueue.main.async {
            self.inlineCompletion = ""
            self.dropdownSuggestions = []
            self.isDropdownVisible = false
            self.selectedIndex = 0
        }
    }
}

// MARK: - Models

struct AutocompleteSuggestion: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let type: SuggestionType
    let description: String
    
    enum SuggestionType: String, Hashable {
        case command
        case file
        case directory
        
        var icon: String {
            switch self {
            case .command: return "terminal"
            case .file: return "doc"
            case .directory: return "folder.fill"
            }
        }
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(type)
    }
    
    static func == (lhs: AutocompleteSuggestion, rhs: AutocompleteSuggestion) -> Bool {
        lhs.text == rhs.text && lhs.type == rhs.type
    }
}
