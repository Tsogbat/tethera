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
        "grep", "find", "which", "man", "clear", "exit", "history", "head", "tail", "wc",
        "chmod", "chown", "touch", "file", "tar", "curl", "wget", "ssh", "scp", "rsync",
        "git", "npm", "node", "yarn", "pnpm", "python", "python3", "pip", "pip3", "brew", "make", "swift",
        "vim", "nano", "code", "open", "pbcopy", "pbpaste", "echo", "export", "source",
        "docker", "kubectl", "cargo", "go", "ruby", "gem", "pip3"
    ]
    
    /// Comprehensive command completions with flags, subcommands, and descriptions
    private let commandCompletions: [String: [(text: String, desc: String)]] = [
        // File system commands
        "ls": [
            ("-la", "List all with details"),
            ("-l", "Long format"),
            ("-a", "Show hidden files"),
            ("-lh", "Human readable sizes"),
            ("-R", "Recursive listing"),
            ("-t", "Sort by time"),
            ("-S", "Sort by size"),
            ("-1", "One file per line"),
        ],
        "cd": [
            ("..", "Parent directory"),
            ("~", "Home directory"),
            ("-", "Previous directory"),
            ("/", "Root directory"),
        ],
        "mkdir": [
            ("-p", "Create parents"),
            ("-v", "Verbose output"),
        ],
        "rm": [
            ("-rf", "Force recursive delete"),
            ("-r", "Recursive delete"),
            ("-f", "Force delete"),
            ("-i", "Interactive mode"),
            ("-v", "Verbose output"),
        ],
        "cp": [
            ("-r", "Recursive copy"),
            ("-v", "Verbose output"),
            ("-i", "Interactive mode"),
            ("-n", "No overwrite"),
            ("-a", "Archive mode"),
        ],
        "mv": [
            ("-v", "Verbose output"),
            ("-i", "Interactive mode"),
            ("-n", "No overwrite"),
        ],
        "chmod": [
            ("+x", "Add execute"),
            ("755", "rwxr-xr-x"),
            ("644", "rw-r--r--"),
            ("-R", "Recursive"),
        ],
        "cat": [
            ("-n", "Number lines"),
            ("-b", "Number non-blank"),
        ],
        "grep": [
            ("-r", "Recursive search"),
            ("-i", "Case insensitive"),
            ("-n", "Show line numbers"),
            ("-v", "Invert match"),
            ("-l", "List files only"),
            ("-c", "Count matches"),
            ("-E", "Extended regex"),
            ("--color", "Colorize output"),
        ],
        "find": [
            ("-name", "Match filename"),
            ("-type f", "Find files"),
            ("-type d", "Find directories"),
            ("-mtime", "Modified time"),
            ("-size", "By file size"),
            ("-exec", "Execute command"),
        ],
        "tar": [
            ("-xvf", "Extract verbose"),
            ("-cvf", "Create verbose"),
            ("-xzf", "Extract gzip"),
            ("-czf", "Create gzip"),
            ("-tvf", "List contents"),
        ],
        "curl": [
            ("-X GET", "GET request"),
            ("-X POST", "POST request"),
            ("-H", "Add header"),
            ("-d", "POST data"),
            ("-o", "Output to file"),
            ("-O", "Save as remote name"),
            ("-L", "Follow redirects"),
            ("-v", "Verbose output"),
            ("-s", "Silent mode"),
        ],
        "ssh": [
            ("-i", "Identity file"),
            ("-p", "Port number"),
            ("-v", "Verbose mode"),
            ("-L", "Local port forward"),
            ("-R", "Remote port forward"),
        ],
        "rsync": [
            ("-avz", "Archive verbose compressed"),
            ("-r", "Recursive"),
            ("--progress", "Show progress"),
            ("--delete", "Delete extra files"),
            ("-n", "Dry run"),
        ],
        
        // Git
        "git": [
            ("status", "Show status"),
            ("add", "Stage changes"),
            ("add .", "Stage all"),
            ("commit", "Commit changes"),
            ("commit -m", "Commit with message"),
            ("push", "Push to remote"),
            ("push origin", "Push to origin"),
            ("pull", "Pull from remote"),
            ("clone", "Clone repository"),
            ("checkout", "Switch branch"),
            ("checkout -b", "Create branch"),
            ("branch", "List branches"),
            ("branch -d", "Delete branch"),
            ("merge", "Merge branch"),
            ("log", "Show history"),
            ("log --oneline", "Compact log"),
            ("diff", "Show changes"),
            ("stash", "Stash changes"),
            ("stash pop", "Apply stash"),
            ("reset", "Reset changes"),
            ("reset --hard", "Hard reset"),
            ("fetch", "Fetch remote"),
            ("remote -v", "List remotes"),
            ("rebase", "Rebase branch"),
            ("cherry-pick", "Cherry pick"),
        ],
        
        // Package managers
        "npm": [
            ("install", "Install packages"),
            ("install --save-dev", "Install as dev"),
            ("uninstall", "Remove package"),
            ("start", "Run start script"),
            ("run", "Run script"),
            ("run dev", "Run dev script"),
            ("run build", "Build project"),
            ("test", "Run tests"),
            ("init", "Initialize project"),
            ("init -y", "Init with defaults"),
            ("update", "Update packages"),
            ("outdated", "Check outdated"),
            ("audit", "Security audit"),
            ("ci", "Clean install"),
            ("publish", "Publish package"),
        ],
        "yarn": [
            ("install", "Install packages"),
            ("add", "Add package"),
            ("add -D", "Add as dev"),
            ("remove", "Remove package"),
            ("dev", "Run dev"),
            ("build", "Build project"),
            ("start", "Start project"),
            ("test", "Run tests"),
        ],
        "pip": [
            ("install", "Install package"),
            ("install -r requirements.txt", "Install from requirements"),
            ("install --upgrade", "Upgrade package"),
            ("uninstall", "Remove package"),
            ("freeze", "List packages"),
            ("list", "Show installed"),
            ("show", "Package info"),
            ("search", "Search packages"),
        ],
        "pip3": [
            ("install", "Install package"),
            ("install -r requirements.txt", "Install from requirements"),
            ("install --upgrade", "Upgrade package"),
            ("uninstall", "Remove package"),
            ("freeze", "List packages"),
            ("list", "Show installed"),
        ],
        "brew": [
            ("install", "Install package"),
            ("uninstall", "Remove package"),
            ("update", "Update Homebrew"),
            ("upgrade", "Upgrade packages"),
            ("list", "List installed"),
            ("search", "Search packages"),
            ("info", "Package info"),
            ("services", "Manage services"),
            ("services list", "List services"),
            ("services start", "Start service"),
            ("services stop", "Stop service"),
            ("doctor", "Check issues"),
            ("cleanup", "Remove old versions"),
            ("cask install", "Install app"),
        ],
        
        // Python
        "python": [
            ("-m venv venv", "Create virtualenv"),
            ("-m pip install", "Install with pip"),
            ("-m http.server", "Start HTTP server"),
            ("-c", "Run command"),
            ("-i", "Interactive mode"),
            ("--version", "Show version"),
        ],
        "python3": [
            ("-m venv venv", "Create virtualenv"),
            ("-m pip install", "Install with pip"),
            ("-m http.server", "Start HTTP server"),
            ("-c", "Run command"),
            ("-i", "Interactive mode"),
            ("--version", "Show version"),
        ],
        
        // Docker
        "docker": [
            ("run", "Run container"),
            ("run -it", "Interactive container"),
            ("run -d", "Detached container"),
            ("build", "Build image"),
            ("build -t", "Build with tag"),
            ("ps", "List containers"),
            ("ps -a", "List all containers"),
            ("images", "List images"),
            ("pull", "Pull image"),
            ("push", "Push image"),
            ("stop", "Stop container"),
            ("rm", "Remove container"),
            ("rmi", "Remove image"),
            ("exec -it", "Execute in container"),
            ("logs", "View logs"),
            ("logs -f", "Follow logs"),
            ("compose up", "Start compose"),
            ("compose down", "Stop compose"),
            ("compose build", "Build compose"),
        ],
        
        // Node/JS
        "node": [
            ("--version", "Show version"),
            ("-e", "Evaluate code"),
            ("--inspect", "Debug mode"),
        ],
        
        // Cargo/Rust
        "cargo": [
            ("build", "Build project"),
            ("build --release", "Release build"),
            ("run", "Run project"),
            ("test", "Run tests"),
            ("new", "New project"),
            ("init", "Init in directory"),
            ("add", "Add dependency"),
            ("update", "Update deps"),
            ("clippy", "Lint code"),
            ("fmt", "Format code"),
        ],
        
        // Go
        "go": [
            ("run", "Run program"),
            ("build", "Build binary"),
            ("test", "Run tests"),
            ("mod init", "Init module"),
            ("mod tidy", "Clean deps"),
            ("get", "Get package"),
            ("fmt", "Format code"),
            ("vet", "Check code"),
        ],
        
        // Swift
        "swift": [
            ("build", "Build package"),
            ("run", "Run package"),
            ("test", "Run tests"),
            ("package init", "Init package"),
            ("package update", "Update deps"),
        ],
        
        // Make
        "make": [
            ("all", "Build all"),
            ("clean", "Clean build"),
            ("install", "Install"),
            ("test", "Run tests"),
            ("build", "Build target"),
            ("run", "Run target"),
        ],
        
        // System
        "open": [
            (".", "Open current dir"),
            ("-a", "Open with app"),
        ],
        "code": [
            (".", "Open current dir"),
            ("-n", "New window"),
            ("-r", "Reuse window"),
        ],
        "man": [
            ("ls", "ls manual"),
            ("grep", "grep manual"),
            ("find", "find manual"),
        ],
    ]
    
    private let fileManager = FileManager.default
    
    // MARK: - Inline Completion (Ghost Text)
    
    /// Update inline ghost text based on current input
    /// Called on every keystroke
    func updateInlineCompletion(for input: String, history: [String], workingDirectory: String = "") {
        guard !input.isEmpty else {
            DispatchQueue.main.async { self.inlineCompletion = "" }
            return
        }
        
        let components = input.split(separator: " ", omittingEmptySubsequences: false)
        
        // Commands that take no arguments - no ghost text after command is typed
        let noCompletionCommands = Set(["clear", "exit", "pwd", "history", "whoami", "date", "uptime", "hostname", "ls", "ll"])
        if components.count >= 2, let cmd = components.first {
            let cmdStr = String(cmd).lowercased()
            if noCompletionCommands.contains(cmdStr) {
                DispatchQueue.main.async { self.inlineCompletion = "" }
                return
            }
        }
        
        // Priority 1: Match from command history (context-aware)
        if let historyMatch = findHistoryMatch(input: input, history: history, workingDirectory: workingDirectory) {
            DispatchQueue.main.async { self.inlineCompletion = historyMatch }
            return
        }
        
        // Priority 2: Complete command names
        if components.count == 1, let command = components.first {
            if let match = commonCommands.first(where: { $0.hasPrefix(String(command).lowercased()) && $0 != String(command).lowercased() }) {
                let completion = String(match.dropFirst(command.count))
                DispatchQueue.main.async { self.inlineCompletion = input + completion }
                return
            }
        }
        
        // Priority 3: Command subcommands (e.g., "git " -> "git status")
        if components.count == 2, let cmd = components.first, components.last?.isEmpty == true {
            let cmdStr = String(cmd).lowercased()
            // Skip if it's a standalone command
            if !noCompletionCommands.contains(cmdStr) {
                if let completions = commandCompletions[cmdStr], let first = completions.first {
                    DispatchQueue.main.async { self.inlineCompletion = input + first.text }
                    return
                }
            }
        }
        
        DispatchQueue.main.async { self.inlineCompletion = "" }
    }
    
    private func findHistoryMatch(input: String, history: [String], workingDirectory: String) -> String? {
        let lowercaseInput = input.lowercased()
        let currentDirName = (workingDirectory as NSString).lastPathComponent.lowercased()
        let parentDirName = ((workingDirectory as NSString).deletingLastPathComponent as NSString).lastPathComponent.lowercased()
        
        // Command type categories
        let dirOnlyCommands = Set(["cd", "pushd", "popd", "rmdir"])
        let fileOnlyCommands = Set(["cat", "less", "more", "head", "tail", "nano", "vim", "vi", "source"])
        let createCommands = Set(["mkdir", "touch"]) // Target should NOT exist
        
        for entry in history.reversed() {
            let lowercaseEntry = entry.lowercased()
            
            // Skip if doesn't match prefix
            guard lowercaseEntry.hasPrefix(lowercaseInput) && lowercaseEntry != lowercaseInput else { continue }
            
            // Extract command and target
            let parts = entry.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { 
                return entry // No argument, safe to suggest
            }
            let cmd = String(parts[0]).lowercased()
            let target = String(parts[1]).trimmingCharacters(in: .whitespaces)
            
            // Build full path
            let fullPath: String
            if target.hasPrefix("/") {
                fullPath = target
            } else if target.hasPrefix("~") {
                fullPath = NSString(string: target).expandingTildeInPath
            } else {
                fullPath = (workingDirectory as NSString).appendingPathComponent(target)
            }
            
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir)
            
            // Context filter: cd only to directories that exist
            if dirOnlyCommands.contains(cmd) {
                // Skip if target is current directory name
                if target.lowercased() == currentDirName { continue }
                if target.lowercased().hasSuffix("/\(currentDirName)") { continue }
                
                // Skip if doesn't exist as directory
                if !exists || !isDir.boolValue { continue }
            }
            
            // Context filter: cat/vim only to files that exist
            if fileOnlyCommands.contains(cmd) {
                // Skip if doesn't exist as file
                if !exists || isDir.boolValue { continue }
            }
            
            // Context filter: mkdir/touch target should NOT exist
            if createCommands.contains(cmd) {
                if exists { continue }
            }
            
            return entry
        }
        return nil
    }
    
    // MARK: - Dropdown Suggestions (Tab Menu)
    
    /// Show dropdown suggestions when Tab is pressed
    /// Uses real shell completions with fallback to hardcoded
    func showDropdownSuggestions(for input: String, workingDirectory: String) {
        guard !input.isEmpty else {
            hideDropdown()
            return
        }
        
        // Extract command for filtering
        let components = input.split(separator: " ", omittingEmptySubsequences: false)
        let cmd = components.count > 1 ? String(components.first ?? "").lowercased() : ""
        
        // Command type sets for filtering
        let noCompletionCommands = Set(["clear", "exit", "pwd", "history", "whoami", "date", "uptime", "hostname"])
        let dirOnlyCommands = Set(["cd", "pushd", "popd", "rmdir"])
        let fileOnlyCommands = Set(["cat", "less", "more", "head", "tail", "nano", "vim", "vi", "code", "source"])
        
        // Skip dropdown for standalone commands
        if noCompletionCommands.contains(cmd) {
            hideDropdown()
            return
        }
        
        // Generate filtered suggestions
        let fallbackSuggestions = generateSuggestions(for: input, workingDirectory: workingDirectory)
        
        DispatchQueue.main.async {
            self.dropdownSuggestions = fallbackSuggestions
            self.isDropdownVisible = !fallbackSuggestions.isEmpty
            self.selectedIndex = 0
        }
        
        // Then try to get real shell completions (async)
        ShellCompletionProvider.shared.queryCompletions(for: input, workingDirectory: workingDirectory) { [weak self] shellSuggestions in
            guard let self = self, !shellSuggestions.isEmpty else { return }
            
            // Filter shell suggestions based on command type
            let filteredShell = shellSuggestions.filter { suggestion in
                if dirOnlyCommands.contains(cmd) && suggestion.type == .file {
                    return false // Skip files for cd
                }
                if fileOnlyCommands.contains(cmd) && suggestion.type == .directory {
                    return false // Skip directories for cat
                }
                return true
            }
            
            // Merge: shell suggestions first, then add unique fallback items
            var merged = filteredShell
            let shellTexts = Set(filteredShell.map { $0.text.lowercased() })
            
            for suggestion in fallbackSuggestions {
                if !shellTexts.contains(suggestion.text.lowercased()) {
                    merged.append(suggestion)
                }
            }
            
            DispatchQueue.main.async {
                if self.isDropdownVisible {
                    self.dropdownSuggestions = merged // No limit - show all
                }
            }
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
        
        // Standalone commands that shouldn't appear in dropdown
        let standaloneCommands = Set(["clear", "exit", "pwd", "history", "whoami", "date", "uptime", "hostname"])
        
        var suggestions: [AutocompleteSuggestion] = []
        
        if components.count == 1 {
            // Suggest commands matching prefix - but filter out standalone commands
            suggestions = commonCommands
                .filter { $0.hasPrefix(lastComponent.lowercased()) && !standaloneCommands.contains($0) }
                .prefix(15)
                .map { AutocompleteSuggestion(text: $0, type: .command, description: "Command") }
        } else {
            let cmd = String(components.first ?? "").lowercased()
            
            // Commands that need NO completions at all (standalone)
            let noCompletionCommands = Set(["clear", "exit", "pwd", "history", "whoami", "date", "uptime", "hostname"])
            if noCompletionCommands.contains(cmd) {
                return [] // These commands take no arguments
            }
            
            // Commands that primarily use flags (show more flags)
            let flagCommands = Set(["ls", "grep", "find", "ps", "top", "chmod", "chown", "tar", "curl", "ssh", "rsync"])
            
            // Commands that only accept directories
            let dirOnlyCommands = Set(["cd", "pushd", "popd", "rmdir"])
            
            // Commands that only accept files (not directories)
            let fileOnlyCommands = Set(["cat", "less", "more", "head", "tail", "nano", "vim", "vi", "code", "source"])
            
            // Commands that don't need path suggestions (they have their own completions)
            let noPathCommands = Set(["git", "brew", "npm", "yarn", "pip", "pip3", "cargo", "docker", "kubectl", "make", "swift", "go"])
            
            // For cd-like commands: show directories FIRST, then shortcuts
            if dirOnlyCommands.contains(cmd) {
                // Add directory suggestions first
                let pathSuggestions = getPathSuggestions(
                    prefix: lastComponent,
                    workingDirectory: workingDirectory,
                    directoriesOnly: true,
                    filesOnly: false
                )
                suggestions.append(contentsOf: pathSuggestions)
                
                // Add shortcuts (like ~, -, ..) only if no prefix typed
                if lastComponent.isEmpty, let completions = commandCompletions[cmd] {
                    let shortcuts = completions.map { 
                        AutocompleteSuggestion(text: $0.text, type: .directory, description: $0.desc) 
                    }
                    suggestions.append(contentsOf: shortcuts)
                }
            } else {
                // For other commands: flags first, then paths
                if let completions = commandCompletions[cmd] {
                    let flagLimit = flagCommands.contains(cmd) ? 5 : 3
                    let cmdSuggestions = completions
                        .filter { lastComponent.isEmpty || $0.text.lowercased().hasPrefix(lastComponent.lowercased()) }
                        .prefix(flagLimit)
                        .map { AutocompleteSuggestion(text: $0.text, type: .command, description: $0.desc) }
                    suggestions.append(contentsOf: cmdSuggestions)
                }
                
                // Add path suggestions for non-git-like commands
                if !noPathCommands.contains(cmd) || !lastComponent.isEmpty {
                    let filesOnly = fileOnlyCommands.contains(cmd)
                    let pathSuggestions = getPathSuggestions(
                        prefix: lastComponent,
                        workingDirectory: workingDirectory,
                        directoriesOnly: false,
                        filesOnly: filesOnly
                    )
                    suggestions.append(contentsOf: pathSuggestions)
                }
            }
        }
        
        return suggestions // Return all - dropdown is scrollable
    }
    
    private func getPathSuggestions(prefix: String, workingDirectory: String, directoriesOnly: Bool = false, filesOnly: Bool = false) -> [AutocompleteSuggestion] {
        var suggestions: [AutocompleteSuggestion] = []
        let home = fileManager.homeDirectoryForCurrentUser.path
        
        var searchDir: String
        var searchPrefix: String
        
        // Handle ~ at the start (home directory)
        if prefix == "~" {
            searchDir = home
            searchPrefix = ""
        } else if prefix.hasPrefix("~/") {
            // ~/something - search in home subdirectory
            let pathAfterTilde = String(prefix.dropFirst(2)) // Remove ~/
            let parts = pathAfterTilde.split(separator: "/", omittingEmptySubsequences: false)
            searchPrefix = String(parts.last ?? "")
            if parts.count > 1 {
                searchDir = home + "/" + parts.dropLast().joined(separator: "/")
            } else {
                searchDir = home
            }
        } else if prefix.contains("/") {
            // Path with / - could be relative or absolute
            let parts = prefix.split(separator: "/", omittingEmptySubsequences: false)
            searchPrefix = String(parts.last ?? "")
            let pathPart = parts.dropLast().joined(separator: "/")
            
            if prefix.hasPrefix("/") {
                // Absolute path
                searchDir = "/" + pathPart
            } else {
                // Relative path - try HOME first (Projects, Documents etc are typically there)
                // then fall back to working directory
                let tryHomeDir = (home as NSString).appendingPathComponent(pathPart)
                let tryWorkingDir = (workingDirectory as NSString).appendingPathComponent(pathPart)
                
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: tryHomeDir, isDirectory: &isDir) && isDir.boolValue {
                    searchDir = tryHomeDir
                } else if fileManager.fileExists(atPath: tryWorkingDir, isDirectory: &isDir) && isDir.boolValue {
                    searchDir = tryWorkingDir
                } else {
                    // Neither exists, try home
                    searchDir = tryHomeDir
                }
            }
        } else {
            // Simple prefix, search in working directory
            searchDir = workingDirectory
            searchPrefix = prefix
        }
        
        // Normalize path
        searchDir = (searchDir as NSString).standardizingPath
        
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: searchDir)
            for item in contents where !item.hasPrefix(".") {
                if searchPrefix.isEmpty || item.lowercased().hasPrefix(searchPrefix.lowercased()) {
                    var isDirectory: ObjCBool = false
                    let fullPath = (searchDir as NSString).appendingPathComponent(item)
                    fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory)
                    
                    // Skip based on command requirements
                    if directoriesOnly && !isDirectory.boolValue { continue }
                    if filesOnly && isDirectory.boolValue { continue }
                    
                    suggestions.append(AutocompleteSuggestion(
                        text: item,
                        type: isDirectory.boolValue ? .directory : .file,
                        description: isDirectory.boolValue ? "Directory" : "File"
                    ))
                }
            }
        } catch {
            // Directory doesn't exist or can't be read
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

// MARK: - Shell Completion Provider

/// Queries the shell for real completions using zsh's completion system
class ShellCompletionProvider {
    static let shared = ShellCompletionProvider()
    
    private let completionQueue = DispatchQueue(label: "com.tethera.completion", qos: .userInitiated)
    private var cache: [String: (completions: [String], timestamp: Date)] = [:]
    private let cacheTimeout: TimeInterval = 30 // Cache for 30 seconds
    
    private init() {}
    
    /// Query zsh for completions (async with timeout)
    func queryCompletions(for input: String, workingDirectory: String, timeout: TimeInterval = 0.3, completion: @escaping ([AutocompleteSuggestion]) -> Void) {
        guard !input.isEmpty else {
            completion([])
            return
        }
        
        // Check cache first
        let cacheKey = "\(workingDirectory):\(input)"
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheTimeout {
            let suggestions = cached.completions.map { self.parseCompletion($0, workingDirectory: workingDirectory) }
            completion(suggestions)
            return
        }
        
        completionQueue.async { [weak self] in
            guard let self = self else { return }
            
            let result = self.executeCompletionQuery(input: input, workingDirectory: workingDirectory)
            
            // Cache the result
            self.cache[cacheKey] = (result, Date())
            
            let suggestions = result.map { self.parseCompletion($0, workingDirectory: workingDirectory) }
            
            DispatchQueue.main.async {
                completion(suggestions)
            }
        }
    }
    
    private func executeCompletionQuery(input: String, workingDirectory: String) -> [String] {
        // Use zsh's capture_completions to get real completions
        let script = """
        cd '\(workingDirectory.replacingOccurrences(of: "'", with: "'\\''"))' 2>/dev/null
        autoload -Uz compinit 2>/dev/null
        compinit -C 2>/dev/null
        
        # Capture completions for the input
        capture_completions() {
            local input="$1"
            local cmd="${input%% *}"
            local args="${input#* }"
            
            # For commands with arguments, try to get subcommand completions
            if [[ "$input" == *" "* ]]; then
                case "$cmd" in
                    git)
                        if [[ "$args" == "" ]] || [[ "$args" == "$input" ]]; then
                            git --list-cmds=main 2>/dev/null | head -20
                        else
                            # Get completions for git subcommands
                            compgen -W "$(git --list-cmds=main 2>/dev/null)" -- "${args%% *}" 2>/dev/null | head -15
                        fi
                        ;;
                    brew)
                        brew commands 2>/dev/null | head -20
                        ;;
                    npm)
                        echo "install\\nstart\\nrun\\ntest\\nbuild\\ninit\\npublish\\nversion\\nupdate\\naudit\\nci\\nlink\\nuninstall"
                        ;;
                    pip|pip3)
                        echo "install\\nuninstall\\nfreeze\\nlist\\nshow\\nsearch\\ndownload\\nwheel\\nhash\\ncompletion\\nconfig\\ncache\\nindex\\ncheck"
                        ;;
                    docker)
                        docker --help 2>/dev/null | grep -E '^  [a-z]' | awk '{print $1}' | head -20
                        ;;
                    cargo)
                        echo "build\\nrun\\ntest\\ncheck\\nclean\\ndoc\\nnew\\ninit\\nadd\\nremove\\nupdate\\nsearch\\npublish\\ninstall\\nuninstall"
                        ;;
                    *)
                        # For other commands, try to list files/directories
                        ls -1 2>/dev/null | head -20
                        ;;
                esac
            else
                # Complete command names
                compgen -c -- "$input" 2>/dev/null | sort -u | head -20
            fi
        }
        
        capture_completions '\(input.replacingOccurrences(of: "'", with: "'\\''"))'
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return output.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .prefix(20)
                    .map { String($0) }
            }
        } catch {
            // Silently fail - caller will use fallback
        }
        
        return []
    }
    
    private func parseCompletion(_ completion: String, workingDirectory: String) -> AutocompleteSuggestion {
        // Check if it's a directory
        let fullPath = (workingDirectory as NSString).appendingPathComponent(completion)
        var isDir: ObjCBool = false
        
        if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir) {
            if isDir.boolValue {
                return AutocompleteSuggestion(text: completion, type: .directory, description: "Directory")
            } else {
                return AutocompleteSuggestion(text: completion, type: .file, description: "File")
            }
        }
        
        // Default to command/subcommand
        return AutocompleteSuggestion(text: completion, type: .command, description: "")
    }
    
    /// Clear completion cache
    func clearCache() {
        cache.removeAll()
    }
}
