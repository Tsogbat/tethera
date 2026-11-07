import Foundation

/// Warp-style autocompletion engine with two modes:
/// 1. Inline ghost completion (→ to accept)
/// 2. Tab dropdown suggestions (Tab to show, arrows to navigate)
@MainActor
final class AutocompleteEngine: ObservableObject {
    // MARK: - Published State
    
    /// Ghost text shown inline after cursor (accept with → key)
    @Published var inlineCompletion: String = ""
    
    /// Dropdown suggestions shown when Tab is pressed
    @Published var dropdownSuggestions: [AutocompleteSuggestion] = []
    
    /// Whether dropdown is currently visible
    @Published var isDropdownVisible = false
    
    /// Currently selected suggestion in dropdown
    @Published var selectedIndex = 0
    
    // MARK: - Static Data (Shared across all instances)
    
    private static let commonCommands = [
        "ls", "cd", "pwd", "mkdir", "rmdir", "rm", "cp", "mv", "cat", "less", "more",
        "grep", "find", "which", "man", "clear", "exit", "history", "head", "tail", "wc",
        "chmod", "chown", "touch", "file", "tar", "curl", "wget", "ssh", "scp", "rsync",
        "git", "npm", "node", "yarn", "pnpm", "python", "python3", "pip", "pip3", "brew", "make", "swift",
        "vim", "nano", "code", "open", "pbcopy", "pbpaste", "echo", "export", "source",
        "docker", "kubectl", "cargo", "go", "ruby", "gem", "pip3"
    ]
    
    // Command category sets for filtering (static to avoid per-keystroke allocation)
    private static let noCompletionCommands = Set(["clear", "exit", "pwd", "history", "whoami", "date", "uptime", "hostname"])
    private static let dirOnlyCommands = Set(["cd", "pushd", "popd", "rmdir"])
    private static let fileOnlyCommands = Set(["cat", "less", "more", "head", "tail", "nano", "vim", "vi", "code", "source"])
    private static let noPathCommands = Set(["git", "brew", "npm", "yarn", "pip", "pip3", "cargo", "docker", "kubectl", "make", "swift", "go"])
    private static let flagCommands = Set(["ls", "grep", "find", "ps", "top", "chmod", "chown", "tar", "curl", "ssh", "rsync"])
    
    /// Comprehensive command completions with flags, subcommands, and descriptions
    private static let commandCompletions: [String: [(text: String, desc: String)]] = [
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
            self.inlineCompletion = ""
            return
        }
        
        let components = input.split(separator: " ", omittingEmptySubsequences: false)
        
        // Commands that take no arguments - no ghost text after command is typed
        if components.count >= 2, let cmd = components.first {
            let cmdStr = String(cmd).lowercased()
            if Self.noCompletionCommands.contains(cmdStr) {
                self.inlineCompletion = ""
                return
            }
        }
        
        // Priority 1: Match from command history (context-aware)
        if let historyMatch = findHistoryMatch(input: input, history: history, workingDirectory: workingDirectory) {
            self.inlineCompletion = historyMatch
            return
        }
        
        // Priority 2: Complete command names
        if components.count == 1, let command = components.first {
            if let match = Self.commonCommands.first(where: { $0.hasPrefix(String(command).lowercased()) && $0 != String(command).lowercased() }) {
                let completion = String(match.dropFirst(command.count))
                self.inlineCompletion = input + completion
                return
            }
        }
        
        // Priority 3: Command subcommands (e.g., "git " -> "git status")
        if components.count == 2, let cmd = components.first, components.last?.isEmpty == true {
            let cmdStr = String(cmd).lowercased()
            // Skip if it's a standalone command
            if !Self.noCompletionCommands.contains(cmdStr) {
                if let completions = Self.commandCompletions[cmdStr], let first = completions.first {
                    self.inlineCompletion = input + first.text
                    return
                }
            }
        }
        
        self.inlineCompletion = ""
    }
    
    private func findHistoryMatch(input: String, history: [String], workingDirectory: String) -> String? {
        let currentDirName = (workingDirectory as NSString).lastPathComponent.lowercased()
        
        // Command type categories (use static sets)
        let createCommands = Set(["mkdir", "touch"]) // Target should NOT exist
        
        for entry in history.reversed() {
            // Case-sensitive so the ghost text always continues exactly what was typed.
            guard entry.hasPrefix(input) && entry != input, !entry.contains("\n") else { continue }
            
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
            if Self.dirOnlyCommands.contains(cmd) {
                // Skip if target is current directory name
                if target.lowercased() == currentDirName { continue }
                if target.lowercased().hasSuffix("/\(currentDirName)") { continue }
                
                // Skip if doesn't exist as directory
                if !exists || !isDir.boolValue { continue }
            }
            
            // Context filter: cat/vim only to files that exist
            if Self.fileOnlyCommands.contains(cmd) {
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
        
        // Skip dropdown for standalone commands (use static sets)
        if Self.noCompletionCommands.contains(cmd) {
            hideDropdown()
            return
        }
        
        // Generate filtered suggestions
        let fallbackSuggestions = generateSuggestions(for: input, workingDirectory: workingDirectory)
        
        dropdownSuggestions = fallbackSuggestions
        isDropdownVisible = !fallbackSuggestions.isEmpty
        selectedIndex = 0
        
        // Skip shell completions for directory-only commands (cd, pushd, etc)
        // Our path resolution handles these better with home directory fallback
        if Self.dirOnlyCommands.contains(cmd) {
            return
        }
        
        // For other commands, try real shell completions (async)
        ShellCompletionProvider.shared.queryCompletions(for: input, workingDirectory: workingDirectory) { [weak self] shellSuggestions in
            guard let self = self, !shellSuggestions.isEmpty else { return }
            
            // Filter shell suggestions based on command type
            let filteredShell = shellSuggestions.filter { suggestion in
                if Self.fileOnlyCommands.contains(cmd) && suggestion.type == .directory {
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
            
            if self.isDropdownVisible {
                self.dropdownSuggestions = merged
            }
        }
    }
    
    /// Hide the dropdown
    func hideDropdown() {
        isDropdownVisible = false
        dropdownSuggestions = []
        selectedIndex = 0
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
        selectedIndex = min(selectedIndex + 1, dropdownSuggestions.count - 1)
    }
    
    func navigateUp() {
        guard !dropdownSuggestions.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
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
        let text = suggestion.type == .command ? suggestion.text : suggestion.text.replacingOccurrences(of: " ", with: "\\ ")
        
        // Check if the prefix contains a path (has /)
        if prefix.contains("/") {
            // Preserve the directory path, only replace the last segment
            let pathParts = prefix.split(separator: "/", omittingEmptySubsequences: false)
            if pathParts.count > 1 {
                // Keep everything before the last segment
                let pathPrefix = pathParts.dropLast().joined(separator: "/") + "/"
                var newComponents = Array(components.dropLast())
                newComponents.append(Substring(pathPrefix + text + suffix))
                return newComponents.joined(separator: " ")
            }
        }
        
        // No path prefix - just replace last component
        var newComponents = Array(components.dropLast())
        newComponents.append(Substring(text + suffix))
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
            suggestions = Self.commonCommands
                .filter { $0.hasPrefix(lastComponent.lowercased()) && !standaloneCommands.contains($0) }
                .prefix(15)
                .map { AutocompleteSuggestion(text: $0, type: .command, description: "Command") }
        } else {
            let cmd = String(components.first ?? "").lowercased()
            
            // Commands that need NO completions at all (standalone) - use static sets
            if Self.noCompletionCommands.contains(cmd) {
                return [] // These commands take no arguments
            }
            
            // For cd-like commands: show directories FIRST, then shortcuts
            if Self.dirOnlyCommands.contains(cmd) {
                // Add directory suggestions first
                let pathSuggestions = getPathSuggestions(
                    prefix: lastComponent,
                    workingDirectory: workingDirectory,
                    directoriesOnly: true,
                    filesOnly: false
                )
                suggestions.append(contentsOf: pathSuggestions)
                
                // Add shortcuts (like ~, -, ..) only if no prefix typed
                if lastComponent.isEmpty, let completions = Self.commandCompletions[cmd] {
                    let shortcuts = completions.map { 
                        AutocompleteSuggestion(text: $0.text, type: .directory, description: $0.desc) 
                    }
                    suggestions.append(contentsOf: shortcuts)
                }
            } else {
                // For other commands: flags first, then paths
                if let completions = Self.commandCompletions[cmd] {
                    let flagLimit = Self.flagCommands.contains(cmd) ? 5 : 3
                    let cmdSuggestions = completions
                        .filter { lastComponent.isEmpty || $0.text.lowercased().hasPrefix(lastComponent.lowercased()) }
                        .prefix(flagLimit)
                        .map { AutocompleteSuggestion(text: $0.text, type: .command, description: $0.desc) }
                    suggestions.append(contentsOf: cmdSuggestions)
                }
                
                // Add path suggestions for non-git-like commands
                if !Self.noPathCommands.contains(cmd) || !lastComponent.isEmpty {
                    let filesOnly = Self.fileOnlyCommands.contains(cmd)
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
                // Relative path: resolve against the working directory, then home.
                let tryWorkingDir = (workingDirectory as NSString).appendingPathComponent(pathPart)
                let tryHomeDir = (home as NSString).appendingPathComponent(pathPart)

                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: tryWorkingDir, isDirectory: &isDir) && isDir.boolValue {
                    searchDir = tryWorkingDir
                } else if fileManager.fileExists(atPath: tryHomeDir, isDirectory: &isDir) && isDir.boolValue {
                    searchDir = tryHomeDir
                } else {
                    searchDir = tryWorkingDir
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
            for item in contents where !item.hasPrefix(".") || searchPrefix.hasPrefix(".") {
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
        inlineCompletion = ""
        dropdownSuggestions = []
        isDropdownVisible = false
        selectedIndex = 0
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

/// Asks bash's `compgen` (zsh has no scriptable equivalent) for command and
/// subcommand completions. Runs off the main thread with a short timeout.
final class ShellCompletionProvider: @unchecked Sendable {
    static let shared = ShellCompletionProvider()

    private let queue = DispatchQueue(label: "com.tethera.completion", qos: .userInitiated)
    private var cache: [String: (completions: [String], timestamp: Date)] = [:]
    private let cacheTimeout: TimeInterval = 30

    private init() {}

    func queryCompletions(for input: String, workingDirectory: String, completion: @escaping ([AutocompleteSuggestion]) -> Void) {
        guard !input.isEmpty else {
            completion([])
            return
        }
        queue.async { [weak self] in
            guard let self else { return }
            let key = "\(workingDirectory)\u{0}\(input)"
            let results: [String]
            if let cached = self.cache[key], Date().timeIntervalSince(cached.timestamp) < self.cacheTimeout {
                results = cached.completions
            } else {
                results = self.execute(input: input, workingDirectory: workingDirectory)
                self.cache[key] = (results, Date())
                if self.cache.count > 200 { self.cache.removeAll() }
            }
            let suggestions = results.map { Self.parse($0, workingDirectory: workingDirectory) }
            DispatchQueue.main.async {
                completion(suggestions)
            }
        }
    }

    private func execute(input: String, workingDirectory: String) -> [String] {
        let quoted = ShellQuoting.singleQuote(input)
        let script = """
        input=\(quoted)
        cmd="${input%% *}"
        if [[ "$input" == *" "* ]]; then
            rest="${input#* }"
            word="${rest##* }"
            case "$cmd" in
                git) compgen -W "$(git --list-cmds=main,others,alias 2>/dev/null)" -- "$word" ;;
                brew) compgen -W "$(brew commands --quiet 2>/dev/null)" -- "$word" ;;
                *) compgen -f -- "$word" ;;
            esac
        else
            compgen -c -- "$input" | sort -u
        fi
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["--noprofile", "--norc", "-c", script]
        if FileManager.default.fileExists(atPath: workingDirectory) {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.6, execute: timer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()
        return String(decoding: data, as: UTF8.self)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(24)
            .map { String($0) }
    }

    private static func parse(_ completion: String, workingDirectory: String) -> AutocompleteSuggestion {
        let fullPath = completion.hasPrefix("/") ? completion : (workingDirectory as NSString).appendingPathComponent(completion)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir) {
            return isDir.boolValue
                ? AutocompleteSuggestion(text: completion, type: .directory, description: "Folder")
                : AutocompleteSuggestion(text: completion, type: .file, description: "File")
        }
        return AutocompleteSuggestion(text: completion, type: .command, description: "")
    }
}
