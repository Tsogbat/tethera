import Foundation
import SwiftUI
import CoreText

class BlockTerminalViewModel: ObservableObject {
    @Published var workingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    @Published var blocks: [TerminalBlock] = []
    @Published var selectedBlockID: UUID? = nil
    @Published var isPalettePresented: Bool = false
    @Published var isSettingsPresented: Bool = false
    @Published var theme: TerminalTheme = .defaultTheme
    @Published var paletteActions: [String] = ["New Tab", "Split Pane", "Settings"]
    
    init() {
        // Load the JetBrains Mono font
        FontLoader.shared.loadJetBrainsMono()
        
        // Demo block so UI is not blank
        blocks.append(TerminalBlock.example)
    }

    func addBlock(input: String, output: String, success: Bool? = nil) {
        let block = TerminalBlock(input: input, output: output, timestamp: Date(), workingDirectory: workingDirectory, success: success)
        blocks.append(block)
    }

    /// Run a shell command and append a new block with the result
    func runShellCommand(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "clear" {
            blocks.removeAll()
            return
        }
        if trimmed.hasPrefix("cd ") {
            let path = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            let newDir: String
            if path.hasPrefix("/") {
                newDir = path
            } else {
                newDir = (workingDirectory as NSString).appendingPathComponent(path)
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
}
