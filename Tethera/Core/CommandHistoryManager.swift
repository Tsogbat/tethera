import Foundation
import SwiftUI
import OSLog

/// Manages extensive command history with optimized search functionality
@MainActor
class CommandHistoryManager: ObservableObject {
    static let shared = CommandHistoryManager()
    
    @Published var allEntries: [HistoryEntry] = []
    @Published var searchQuery: String = ""
    @Published var searchResults: [HistoryEntry] = []
    @Published var selectedResultIndex: Int = 0
    @Published var isSearching: Bool = false
    
    private let maxHistorySize = 10000
    private let maxSearchResults = 50
    private let historyFileURL: URL
    private var searchDebounceTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.tethera.app", category: "CommandHistoryManager")
    
    struct HistoryEntry: Identifiable, Codable, Equatable, Hashable {
        let id: UUID
        let command: String
        let output: String
        let timestamp: Date
        let workingDirectory: String
        let success: Bool?
        let durationMs: Int64?
        let tabId: UUID?
        
        init(from block: TerminalBlock, tabId: UUID? = nil) {
            self.id = block.id
            self.command = block.input
            self.output = block.output
            self.timestamp = block.timestamp
            self.workingDirectory = block.workingDirectory ?? "~"
            self.success = block.success
            self.durationMs = block.durationMs
            self.tabId = tabId
        }
        
        init(id: UUID = UUID(), command: String, output: String, timestamp: Date, workingDirectory: String, success: Bool?, durationMs: Int64?, tabId: UUID?) {
            self.id = id
            self.command = command
            self.output = output
            self.timestamp = timestamp
            self.workingDirectory = workingDirectory
            self.success = success
            self.durationMs = durationMs
            self.tabId = tabId
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let tetheraDir = appSupport.appendingPathComponent("Tethera", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tetheraDir, withIntermediateDirectories: true)
        } catch {
            let message = "Could not create history directory at \(tetheraDir.path). History may not be saved."
            logger.error("\(message)")
            AppErrorReporter.shared.report(title: "History directory error", message: message)
        }
        historyFileURL = tetheraDir.appendingPathComponent("command_history.json")
        
        // Load history on background thread
        Task.detached(priority: .utility) {
            await self.loadAsync()
        }
    }
    
    // MARK: - History Management
    
    func addEntry(from block: TerminalBlock, tabId: UUID? = nil) {
        let entry = HistoryEntry(from: block, tabId: tabId)
        allEntries.append(entry)
        
        // Trim if over max size
        if allEntries.count > maxHistorySize {
            allEntries.removeFirst(allEntries.count - maxHistorySize)
        }
        
        // Auto-save periodically on background
        if allEntries.count % 10 == 0 {
            saveAsync()
        }
    }
    
    func clearHistory() {
        allEntries.removeAll()
        saveAsync()
    }
    
    // MARK: - Debounced Search (150ms delay)
    
    func search(query: String) {
        searchQuery = query
        
        // Cancel previous debounce
        searchDebounceTask?.cancel()
        
        guard !query.isEmpty else {
            searchResults = []
            selectedResultIndex = 0
            return
        }
        
        // Debounce: wait 150ms before searching
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
            guard !Task.isCancelled else { return }
            await performSearch(query: query)
        }
    }
    
    private func performSearch(query: String) async {
        let lowercasedQuery = query.lowercased()
        let entries = allEntries
        let maxResults = maxSearchResults
        
        // Search on background thread with early termination
        let results = await Task.detached(priority: .userInitiated) {
            var found: [HistoryEntry] = []
            found.reserveCapacity(maxResults)
            
            // Search from end (most recent first)
            for i in stride(from: entries.count - 1, through: 0, by: -1) {
                if found.count >= maxResults { break } // Early termination
                
                let entry = entries[i]
                if entry.command.lowercased().contains(lowercasedQuery) ||
                   entry.output.lowercased().contains(lowercasedQuery) {
                    found.append(entry)
                }
            }
            return found
        }.value
        
        await MainActor.run {
            self.searchResults = results
            self.selectedResultIndex = 0
        }
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
        searchDebounceTask?.cancel()
    }
    
    // MARK: - Async Persistence
    
    private func saveAsync() {
        let entries = allEntries
        let url = historyFileURL
        let log = logger
        
        Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(entries)
                try data.write(to: url, options: .atomic)
            } catch {
                let message = "Failed to save command history to \(url.path). Changes may not persist."
                log.error("\(message)")
                await MainActor.run {
                    AppErrorReporter.shared.report(title: "History save failed", message: message)
                }
            }
        }
    }
    
    private func loadAsync() async {
        guard FileManager.default.fileExists(atPath: historyFileURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: historyFileURL)
            let entries = try JSONDecoder().decode([HistoryEntry].self, from: data)
            await MainActor.run {
                self.allEntries = entries
            }
        } catch {
            let message = "Failed to load command history from \(historyFileURL.path)."
            logger.error("\(message)")
            await MainActor.run {
                AppErrorReporter.shared.report(title: "History load failed", message: message)
            }
        }
    }
}
