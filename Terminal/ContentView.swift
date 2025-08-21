import SwiftUI

struct ContentView: View {
    @StateObject private var terminalSession = TerminalSession()
    @State private var terminalText = "Foundation Terminal - Ready!\n\n$ "
    @State private var currentInput = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Terminal display area
            ScrollView {
                Text(terminalText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(20)
                    .textSelection(.enabled)
            }
            .background(.black)
            
            // Input area
            HStack {
                Text("$ ")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.green)
                
                TextField("Type here...", text: $currentInput)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.green)
                    .background(.black)
                    .onSubmit {
                        handleInput()
                    }
            }
            .padding(20)
            .background(.black)
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(.black)
        .onTapGesture {
            // When clicked, make sure we're focused
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.keyWindow ?? NSApp.windows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }
        .onAppear {
            // Focus the input field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Make sure the window is active and focused
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.keyWindow ?? NSApp.windows.first {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
    }
    
    private func handleInput() {
        guard !currentInput.isEmpty else { return }
        
        // Add input to terminal display
        terminalText += currentInput + "\n"
        
        // Process the command and add output
        let output = processCommand(currentInput)
        if !output.isEmpty {
            terminalText += output + "\n"
        }
        
        // Send to terminal session
        terminalSession.write(currentInput + "\r\n")
        
        // Add new prompt
        terminalText += "$ "
        
        // Clear input
        currentInput = ""
    }
    
    private func processCommand(_ command: String) -> String {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmedCommand.split(separator: " ").map(String.init)
        
        guard let firstComponent = components.first else { return "" }
        
        switch firstComponent.lowercased() {
        case "ls":
            // List directory contents with proper permissions and filtering
            let fileManager = FileManager.default
            do {
                let currentPath = fileManager.currentDirectoryPath
                let contents = try fileManager.contentsOfDirectory(atPath: currentPath)
                
                // Check for flags
                let showAll = components.contains("-a") || components.contains("--all")
                let longFormat = components.contains("-l") || components.contains("--long")
                
                // Filter files based on flags
                let visibleFiles: [String]
                if showAll {
                    visibleFiles = contents
                } else {
                    visibleFiles = contents.filter { !$0.hasPrefix(".") }
                }
                
                // Sort alphabetically
                let sortedFiles = visibleFiles.sorted()
                
                // Limit output to prevent overwhelming display
                if sortedFiles.count > 100 {
                    let limitedFiles = Array(sortedFiles.prefix(100))
                    return limitedFiles.joined(separator: "  ") + "\n... and \(sortedFiles.count - 100) more files"
                }
                
                if longFormat {
                    // Long format with file info
                    var longOutput = ""
                    for file in sortedFiles {
                        let filePath = (currentPath as NSString).appendingPathComponent(file)
                        let attributes = try fileManager.attributesOfItem(atPath: filePath)
                        
                        let size = attributes[.size] as? Int64 ?? 0
                        let isDirectory = (attributes[.type] as? FileAttributeType) == .typeDirectory
                        let permissions = attributes[.posixPermissions] as? Int ?? 0
                        
                        let typeChar = isDirectory ? "d" : "-"
                        let permString = String(format: "%c%c%c%c%c%c%c%c%c", 
                            typeChar,
                            (permissions & 0o400) != 0 ? "r" : "-",
                            (permissions & 0o200) != 0 ? "w" : "-",
                            (permissions & 0o100) != 0 ? "x" : "-",
                            (permissions & 0o040) != 0 ? "r" : "-",
                            (permissions & 0o020) != 0 ? "w" : "-",
                            (permissions & 0o010) != 0 ? "x" : "-",
                            (permissions & 0o004) != 0 ? "r" : "-",
                            (permissions & 0o002) != 0 ? "w" : "-",
                            (permissions & 0o001) != 0 ? "x" : "-")
                        
                        longOutput += String(format: "%s %8lld %s\n", permString, size, file)
                    }
                    return longOutput
                } else {
                    return sortedFiles.joined(separator: "  ")
                }
            } catch {
                return "ls: cannot access directory: \(error.localizedDescription)"
            }
            
        case "pwd":
            // Print working directory
            return FileManager.default.currentDirectoryPath
            
        case "cd":
            // Change directory with permission checks
            if components.count > 1 {
                let path = components[1]
                let fileManager = FileManager.default
                
                // Handle special cases
                let targetPath: String
                if path == "~" {
                    targetPath = NSHomeDirectory()
                } else if path.hasPrefix("~/") {
                    targetPath = NSHomeDirectory() + String(path.dropFirst(1))
                } else if path.hasPrefix("/") {
                    // Be more restrictive with absolute paths
                    if path.hasPrefix("/System") || path.hasPrefix("/bin") || path.hasPrefix("/sbin") {
                        return "cd: access denied: \(path) (system directories restricted)"
                    }
                    targetPath = path
                } else {
                    targetPath = fileManager.currentDirectoryPath + "/" + path
                }
                
                // Check if directory exists and is accessible
                var isDirectory: ObjCBool = false
                let exists = fileManager.fileExists(atPath: targetPath, isDirectory: &isDirectory)
                
                if !exists {
                    return "cd: no such file or directory: \(path)"
                }
                
                if !isDirectory.boolValue {
                    return "cd: not a directory: \(path)"
                }
                
                // Check read permissions
                if !fileManager.isReadableFile(atPath: targetPath) {
                    return "cd: permission denied: \(path)"
                }
                
                if fileManager.changeCurrentDirectoryPath(targetPath) {
                    return ""  // Success, no output
                } else {
                    return "cd: failed to change directory: \(path)"
                }
            } else {
                // cd with no arguments goes to home
                if FileManager.default.changeCurrentDirectoryPath(NSHomeDirectory()) {
                    return ""
                } else {
                    return "cd: failed to change to home directory"
                }
            }
            
        case "whoami":
            return NSUserName()
            
        case "date":
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            formatter.timeStyle = .medium
            return formatter.string(from: Date())
            
        case "echo":
            if components.count > 1 {
                return components.dropFirst().joined(separator: " ")
            } else {
                return ""
            }
            
        case "clear":
            // Clear the terminal
            DispatchQueue.main.async {
                self.terminalText = "Foundation Terminal - Ready!\n\n$ "
            }
            return ""
            
        case "help":
            return """
Available commands:
  ls        - list directory contents (filters hidden files by default)
  ls -a     - show all files including hidden ones
  ls -l     - long format with permissions and sizes
  ls -la    - show all files in long format
  cd [dir]  - change directory (with permission checks)
  pwd       - print working directory
  whoami    - print current user
  date      - show current date and time
  echo      - display text
  clear     - clear terminal
  help      - show this help
  exit      - quit terminal

Security features:
  - Hidden files (.files) are filtered by default
  - System directories are restricted
  - Permission checks are enforced
  - Output is limited to prevent overwhelming display
"""
            
        case "exit", "quit":
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
            return "Goodbye!"
            
        default:
            return "\(firstComponent): command not found"
        }
    }
}

#Preview {
    ContentView()
}
