import Foundation

class AutocompleteEngine: ObservableObject {
    @Published var suggestions: [AutocompleteSuggestion] = []
    @Published var isShowingSuggestions = false
    @Published var inlineCompletion: String = ""
    @Published var selectedSuggestionIndex = 0
    
    private let commonCommands = [
        "ls", "cd", "pwd", "mkdir", "rmdir", "rm", "cp", "mv", "cat", "less", "more",
        "grep", "find", "which", "whereis", "man", "help", "clear", "exit", "history",
        "ps", "top", "kill", "killall", "jobs", "bg", "fg", "nohup",
        "chmod", "chown", "chgrp", "umask", "ln", "touch", "file", "stat",
        "tar", "gzip", "gunzip", "zip", "unzip", "curl", "wget", "ssh", "scp",
        "git", "npm", "node", "python", "python3", "pip", "pip3", "ruby", "gem",
        "docker", "kubectl", "brew", "make", "cmake", "gcc", "clang", "swift",
        "vim", "nano", "emacs", "code", "open", "pbcopy", "pbpaste"
    ]
    
    private let commandCompletions: [String: [String]] = [
        "git": ["status", "add", "commit", "push", "pull", "clone", "branch", "checkout", "merge", "log"],
        "npm": ["install", "start", "run", "test", "build", "init", "publish", "update"],
        "docker": ["run", "build", "pull", "push", "ps", "images", "stop", "start", "rm", "rmi"],
        "ls": ["-la", "-l", "-a", "-h", "-R"],
        "cd": ["~", "..", "../..", "/"],
        "mkdir": ["-p"],
        "rm": ["-rf", "-r", "-f"],
        "cp": ["-r", "-f"],
        "mv": ["-f"],
        "grep": ["-r", "-i", "-n", "-v"]
    ]
    
    private let fileManager = FileManager.default
    
    func getSuggestions(for input: String, in workingDirectory: String, forceShow: Bool = false) {
        guard !input.isEmpty else {
            clearSuggestions()
            return
        }
        
        let components = input.split(separator: " ", omittingEmptySubsequences: false)
        guard let lastComponent = components.last else {
            clearSuggestions()
            return
        }
        
        let prefix = String(lastComponent)
        
        // Check if input exactly matches a command - if so, clear everything (unless forced)
        if !forceShow && components.count == 1 && commonCommands.contains(prefix.lowercased()) {
            clearSuggestions()
            return
        }
        
        // Smart autocomplete logic - be less aggressive (unless forced)
        let shouldShowSuggestions = forceShow || shouldTriggerAutocomplete(for: input, components: components, prefix: prefix)
        
        if !shouldShowSuggestions {
            // Only show inline completion for commands without dropdown
            DispatchQueue.main.async {
                self.suggestions = []
                self.isShowingSuggestions = false
                self.selectedSuggestionIndex = 0
                
                // Show inline completion for commands only - show remaining part
                if components.count == 1 {
                    let matchingCommand = self.commonCommands.first { $0.hasPrefix(prefix.lowercased()) && $0 != prefix.lowercased() }
                    if let command = matchingCommand {
                        self.inlineCompletion = input + String(command.dropFirst(prefix.count))
                    } else if let completions = self.commandCompletions[prefix.lowercased()], let firstCompletion = completions.first {
                        self.inlineCompletion = input + " " + firstCompletion
                    } else {
                        self.inlineCompletion = ""
                    }
                } else {
                    self.inlineCompletion = ""
                }
            }
            return
        }
        
        var newSuggestions: [AutocompleteSuggestion] = []
        
        // If it's the first word, suggest commands
        if components.count == 1 {
            newSuggestions.append(contentsOf: getCommandSuggestions(for: prefix))
        } else {
            // For multi-word commands, check if we should suggest command completions
            let firstWord = String(components.first ?? "").lowercased()
            if let commandCompletions = commandCompletions[firstWord] {
                let commandSuggestions = commandCompletions
                    .filter { $0.hasPrefix(prefix.lowercased()) }
                    .map { AutocompleteSuggestion(text: $0, type: .command, description: "Option") }
                newSuggestions.append(contentsOf: commandSuggestions)
            }
        }
        
        // Suggest file/directory paths only when appropriate
        if shouldSuggestPaths(for: input, components: components) {
            newSuggestions.append(contentsOf: getPathSuggestions(for: prefix, in: workingDirectory))
        }
        
        // Remove exact matches to avoid redundancy
        let filteredSuggestions = newSuggestions.filter { $0.text.lowercased() != prefix.lowercased() }
        
        // Remove duplicates and sort
        let uniqueSuggestions = Array(Set(filteredSuggestions)).sorted { $0.text < $1.text }
        
        DispatchQueue.main.async {
            self.suggestions = Array(uniqueSuggestions.prefix(20)) // Increased to 20 suggestions
            self.isShowingSuggestions = !self.suggestions.isEmpty
            self.selectedSuggestionIndex = 0
            
            // Set inline completion for first suggestion
            if let firstSuggestion = self.suggestions.first {
                self.inlineCompletion = self.getInlineCompletion(for: input, suggestion: firstSuggestion)
            } else if components.count == 1 {
                let matchingCommand = self.commonCommands.first { $0.hasPrefix(prefix.lowercased()) && $0 != prefix.lowercased() }
                if let command = matchingCommand {
                    self.inlineCompletion = input + String(command.dropFirst(prefix.count))
                } else if let completions = self.commandCompletions[prefix.lowercased()], let firstCompletion = completions.first {
                    self.inlineCompletion = input + " " + firstCompletion
                } else {
                    self.inlineCompletion = ""
                }
            } else {
                self.inlineCompletion = ""
            }
        }
    }
    
    private func shouldTriggerAutocomplete(for input: String, components: [Substring], prefix: String) -> Bool {
        // For first word (commands), be very restrictive
        if components.count == 1 {
            // Only show dropdown if prefix is substantial and doesn't exactly match a command
            return prefix.count >= 3 && !commonCommands.contains(prefix.lowercased())
        }
        
        // For path completion, be more lenient to allow filtering
        let firstWord = String(components.first ?? "").lowercased()
        
        // Commands that commonly use paths - show suggestions
        let pathCommands = ["cd", "vim", "nano", "emacs", "code", "cat", "less", "more", "ls", "rm", "cp", "mv", "mkdir", "rmdir", "touch", "open", "grep", "find"]
        
        if pathCommands.contains(firstWord) {
            // Show suggestions even for short prefixes to allow filtering
            return prefix.count >= 1 || prefix.isEmpty
        }
        
        // Show suggestions if the prefix looks like a path
        return prefix.contains("/") || prefix.hasPrefix("~") || prefix.count >= 2
    }
    
    private func shouldSuggestPaths(for input: String, components: [Substring]) -> Bool {
        let firstWord = String(components.first ?? "").lowercased()
        
        // Commands that work with files/directories
        let fileCommands = ["cd", "ls", "cat", "less", "more", "rm", "cp", "mv", "mkdir", "rmdir", "touch", "open", "vim", "nano", "emacs", "code", "grep", "find"]
        
        return fileCommands.contains(firstWord) || components.count > 2
    }
    
    private func getCommandSuggestions(for prefix: String) -> [AutocompleteSuggestion] {
        return commonCommands
            .filter { $0.hasPrefix(prefix.lowercased()) }
            .map { AutocompleteSuggestion(text: $0, type: .command, description: "Command") }
    }
    
    private func getPathSuggestions(for prefix: String, in workingDirectory: String) -> [AutocompleteSuggestion] {
        var suggestions: [AutocompleteSuggestion] = []
        
        // Determine the directory to search in
        let searchDirectory: String
        let searchPrefix: String
        
        if prefix.contains("/") {
            // Handle paths with directory separators
            let pathComponents = prefix.split(separator: "/", omittingEmptySubsequences: false)
            if prefix.hasPrefix("/") {
                // Absolute path
                searchDirectory = "/" + pathComponents.dropLast().joined(separator: "/")
                searchPrefix = String(pathComponents.last ?? "")
            } else if prefix.hasPrefix("~/") {
                // Home directory path
                let homePath = fileManager.homeDirectoryForCurrentUser.path
                searchDirectory = homePath + "/" + pathComponents.dropFirst().dropLast().joined(separator: "/")
                searchPrefix = String(pathComponents.last ?? "")
            } else {
                // Relative path
                searchDirectory = workingDirectory + "/" + pathComponents.dropLast().joined(separator: "/")
                searchPrefix = String(pathComponents.last ?? "")
            }
        } else {
            // No directory separator, search in current directory
            searchDirectory = workingDirectory
            searchPrefix = prefix
        }
        
        // Get directory contents with smart filtering
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: searchDirectory)
            let filteredContents = contents.filter { item in
                // Always skip hidden files/folders starting with .
                if item.hasPrefix(".") {
                    return false
                }
                return item.hasPrefix(searchPrefix)
            }
            
            // Limit results to prevent overwhelming dropdown
            let limitedContents = Array(filteredContents.prefix(20))
            
            for item in limitedContents {
                let fullPath = searchDirectory + "/" + item
                var isDirectory: ObjCBool = false
                
                if fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory) {
                    let type: AutocompleteSuggestion.SuggestionType = isDirectory.boolValue ? .directory : .file
                    let displayText = isDirectory.boolValue ? item + "/" : item
                    suggestions.append(AutocompleteSuggestion(
                        text: displayText,
                        type: type,
                        description: type == .directory ? "Directory" : "File"
                    ))
                }
            }
        } catch {
            // Silently ignore errors (e.g., permission denied)
        }
        
        return suggestions
    }
    
    func clearSuggestions() {
        DispatchQueue.main.async {
            self.suggestions = []
            self.isShowingSuggestions = false
            self.inlineCompletion = ""
            self.selectedSuggestionIndex = 0
        }
    }
    
    func updateSelectedIndex(_ index: Int, currentInput: String = "") {
        DispatchQueue.main.async {
            self.selectedSuggestionIndex = index
            if index < self.suggestions.count {
                let suggestion = self.suggestions[index]
                // Update inline completion based on selected suggestion
                self.inlineCompletion = self.getInlineCompletion(for: currentInput, suggestion: suggestion)
            }
        }
    }
    
    func getCompletion(for input: String, suggestion: AutocompleteSuggestion) -> String {
        let components = input.split(separator: " ", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return suggestion.text }
        
        let lastComponent = String(components.last ?? "")
        
        // Handle path completion - append to existing path instead of replacing
        if suggestion.type == .directory || suggestion.type == .file {
            if lastComponent.contains("/") {
                // Extract the directory part and append the suggestion
                let pathComponents = lastComponent.split(separator: "/", omittingEmptySubsequences: false)
                let directoryPart = pathComponents.dropLast().joined(separator: "/")
                let newPath = directoryPart.isEmpty ? suggestion.text : directoryPart + "/" + suggestion.text
                
                var newComponents = Array(components.dropLast())
                newComponents.append(Substring(newPath))
                return newComponents.joined(separator: " ")
            }
        }
        
        // Default behavior for commands and simple completions
        var newComponents = Array(components.dropLast())
        newComponents.append(Substring(suggestion.text))
        
        return newComponents.joined(separator: " ")
    }
    
    private func getInlineCompletion(for input: String, suggestion: AutocompleteSuggestion) -> String {
        let components = input.split(separator: " ", omittingEmptySubsequences: false)
        guard let lastComponent = components.last else { return "" }
        
        let prefix = String(lastComponent)
        
        // For paths, show only the remaining part
        if suggestion.text.hasPrefix(prefix) && suggestion.text.count > prefix.count {
            let completion = String(suggestion.text.dropFirst(prefix.count))
            return input + completion
        }
        
        return ""
    }
}

struct AutocompleteSuggestion: Hashable, Identifiable {
    let id = UUID()
    let text: String
    let type: SuggestionType
    let description: String
    
    enum SuggestionType {
        case command
        case file
        case directory
        
        var icon: String {
            switch self {
            case .command: return "terminal"
            case .file: return "doc"
            case .directory: return "folder"
            }
        }
        
        var color: String {
            switch self {
            case .command: return "green"
            case .file: return "blue"
            case .directory: return "orange"
            }
        }
    }
}
