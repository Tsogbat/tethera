import Foundation
import SwiftUI

/// Manages extensive command history with search functionality
@MainActor
class CommandHistoryManager: ObservableObject {
    static let shared = CommandHistoryManager()
    
    @Published var allEntries: [HistoryEntry] = []
    @Published var searchQuery: String = ""
    @Published var searchResults: [HistoryEntry] = []
    @Published var selectedResultIndex: Int = 0
    @Published var isSearching: Bool = false
    
    private let maxHistorySize = 10000
    private let historyFileURL: URL
    
    struct HistoryEntry: Identifiable, Codable, Equatable {
        let id: UUID
        let command: String
        let output: String
        let timestamp: Date
        let workingDirectory: String
        let success: Bool?
        let executionDuration: TimeInterval?
        let tabId: UUID?
        
        init(from block: TerminalBlock, tabId: UUID? = nil) {
            self.id = block.id
            self.command = block.input
            self.output = block.output
            self.timestamp = block.timestamp
            self.workingDirectory = block.workingDirectory ?? "~"
            self.success = block.success
            self.executionDuration = block.executionDuration
            self.tabId = tabId
        }
        
        init(id: UUID = UUID(), command: String, output: String, timestamp: Date, workingDirectory: String, success: Bool?, executionDuration: TimeInterval?, tabId: UUID?) {
            self.id = id
            self.command = command
            self.output = output
            self.timestamp = timestamp
            self.workingDirectory = workingDirectory
            self.success = success
            self.executionDuration = executionDuration
            self.tabId = tabId
        }
    }
    
    private init() {
        // Store history in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let tetheraDir = appSupport.appendingPathComponent("Tethera", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: tetheraDir, withIntermediateDirectories: true)
        
        historyFileURL = tetheraDir.appendingPathComponent("command_history.json")
        load()
    }
    
    // MARK: - History Management
    
    func addEntry(from block: TerminalBlock, tabId: UUID? = nil) {
        let entry = HistoryEntry(from: block, tabId: tabId)
        allEntries.append(entry)
        
        // Trim if over max size
        if allEntries.count > maxHistorySize {
            allEntries.removeFirst(allEntries.count - maxHistorySize)
        }
        
        // Auto-save periodically
        if allEntries.count % 10 == 0 {
            save()
        }
    }
    
    func clearHistory() {
        allEntries.removeAll()
        save()
    }
    
    // MARK: - Search
    
    func search(query: String) {
        searchQuery = query
        
        guard !query.isEmpty else {
            searchResults = []
            selectedResultIndex = 0
            return
        }
        
        let lowercasedQuery = query.lowercased()
        
        // Fuzzy search: match command or output containing query terms
        searchResults = allEntries.filter { entry in
            entry.command.lowercased().contains(lowercasedQuery) ||
            entry.output.lowercased().contains(lowercasedQuery)
        }.reversed() // Most recent first
        
        selectedResultIndex = 0
    }
    
    func selectNextResult() {
        if selectedResultIndex < searchResults.count - 1 {
            selectedResultIndex += 1
        }
    }
    
    func selectPreviousResult() {
        if selectedResultIndex > 0 {
            selectedResultIndex -= 1
        }
    }
    
    var currentResult: HistoryEntry? {
        guard !searchResults.isEmpty, selectedResultIndex < searchResults.count else { return nil }
        return searchResults[selectedResultIndex]
    }
    
    func openSearch() {
        isSearching = true
        searchQuery = ""
        searchResults = []
        selectedResultIndex = 0
    }
    
    func closeSearch() {
        isSearching = false
    }
    
    // MARK: - Persistence
    
    func save() {
        do {
            let data = try JSONEncoder().encode(allEntries)
            try data.write(to: historyFileURL, options: .atomic)
        } catch {
            print("Failed to save command history: \(error)")
        }
    }
    
    func load() {
        guard FileManager.default.fileExists(atPath: historyFileURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: historyFileURL)
            allEntries = try JSONDecoder().decode([HistoryEntry].self, from: data)
        } catch {
            print("Failed to load command history: \(error)")
            allEntries = []
        }
    }
}
