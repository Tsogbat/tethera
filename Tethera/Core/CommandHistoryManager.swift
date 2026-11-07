import Foundation
import SwiftUI
import OSLog

/// Command history shared by every tab: persisted Tethera blocks plus the user's
/// shell history (read-only) for suggestions.
@MainActor
final class CommandHistoryManager: ObservableObject {
    static let shared = CommandHistoryManager()

    @Published private(set) var allEntries: [HistoryEntry] = []
    @Published var searchQuery: String = ""
    @Published private(set) var searchResults: [HistoryEntry] = []
    @Published var selectedResultIndex: Int = 0
    @Published var isSearching: Bool = false

    /// Most-recent-last command lines from Tethera and ~/.zsh_history / ~/.bash_history, deduplicated.
    private(set) var suggestionCorpus: [String] = []

    private let maxHistorySize = 10_000
    private let maxSearchResults = 60
    private let historyFileURL: URL
    private var searchTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var shellHistory: [String] = []
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
            self.output = String(block.output.prefix(4_000))
            self.timestamp = block.timestamp
            self.workingDirectory = block.workingDirectory ?? "~"
            self.success = block.success
            self.durationMs = block.durationMs
            self.tabId = tabId
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let tetheraDir = appSupport.appendingPathComponent("Tethera", isDirectory: true)
        try? FileManager.default.createDirectory(at: tetheraDir, withIntermediateDirectories: true)
        historyFileURL = tetheraDir.appendingPathComponent("command_history.json")
        Task { await load() }
    }

    // MARK: - Entries

    func addEntry(from block: TerminalBlock, tabId: UUID? = nil) {
        guard block.kind == .command, !block.input.isEmpty else { return }
        allEntries.append(HistoryEntry(from: block, tabId: tabId))
        if allEntries.count > maxHistorySize {
            allEntries.removeFirst(allEntries.count - maxHistorySize)
        }
        appendToCorpus(block.input)
        scheduleSave()
    }

    func clearHistory() {
        allEntries.removeAll()
        rebuildCorpus()
        scheduleSave()
    }

    /// Command lines for ↑/↓ navigation, oldest first, without consecutive duplicates.
    var navigationHistory: [String] {
        var result: [String] = []
        for entry in allEntries where result.last != entry.command {
            result.append(entry.command)
        }
        return result
    }

    // MARK: - Search

    func openSearch() {
        searchQuery = ""
        searchResults = []
        selectedResultIndex = 0
        isSearching = true
    }

    func closeSearch() {
        isSearching = false
        searchTask?.cancel()
    }

    func search(query: String) {
        searchTask?.cancel()
        guard !query.isEmpty else {
            searchResults = []
            selectedResultIndex = 0
            return
        }
        let entries = allEntries
        let limit = maxSearchResults
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled else { return }
            let results = await Task.detached(priority: .userInitiated) { () -> [HistoryEntry] in
                let needle = query.lowercased()
                var found: [HistoryEntry] = []
                var seen = Set<String>()
                for entry in entries.reversed() {
                    if found.count >= limit { break }
                    if entry.command.lowercased().contains(needle) || entry.output.lowercased().contains(needle) {
                        if seen.insert(entry.command + entry.workingDirectory).inserted {
                            found.append(entry)
                        }
                    }
                }
                return found
            }.value
            guard !Task.isCancelled else { return }
            searchResults = results
            selectedResultIndex = 0
        }
    }

    func selectNextResult() {
        if selectedResultIndex < searchResults.count - 1 { selectedResultIndex += 1 }
    }

    func selectPreviousResult() {
        if selectedResultIndex > 0 { selectedResultIndex -= 1 }
    }

    var currentResult: HistoryEntry? {
        searchResults.indices.contains(selectedResultIndex) ? searchResults[selectedResultIndex] : nil
    }

    // MARK: - Persistence

    func saveNow() {
        saveTask?.cancel()
        let entries = allEntries
        let url = historyFileURL
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("History save failed: \(error.localizedDescription)")
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let entries = allEntries
        let url = historyFileURL
        let log = logger
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            do {
                let data = try JSONEncoder().encode(entries)
                try data.write(to: url, options: .atomic)
            } catch {
                log.error("History save failed: \(error.localizedDescription)")
            }
        }
    }

    private func load() async {
        let url = historyFileURL
        let (entries, shell) = await Task.detached(priority: .utility) { () -> ([HistoryEntry], [String]) in
            var entries: [HistoryEntry] = []
            if let data = try? Data(contentsOf: url) {
                entries = (try? JSONDecoder().decode([HistoryEntry].self, from: data)) ?? []
            }
            return (entries, ShellHistoryReader.read())
        }.value
        // Entries added before the load finished come after the saved ones.
        allEntries = entries + allEntries
        shellHistory = shell
        rebuildCorpus()
    }

    private func rebuildCorpus() {
        var seen = Set<String>()
        var corpus: [String] = []
        for command in (shellHistory + allEntries.map(\.command)).reversed() where seen.insert(command).inserted {
            corpus.append(command)
        }
        suggestionCorpus = corpus.reversed()
    }

    private func appendToCorpus(_ command: String) {
        if let index = suggestionCorpus.lastIndex(of: command) {
            suggestionCorpus.remove(at: index)
        }
        suggestionCorpus.append(command)
    }
}

/// Reads the user's zsh/bash history files (zsh extended format aware).
enum ShellHistoryReader {
    static func read(limit: Int = 5_000) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let env = ProcessInfo.processInfo.environment
        var candidates: [URL] = []
        if let histFile = env["HISTFILE"] { candidates.append(URL(fileURLWithPath: histFile)) }
        candidates.append(home.appendingPathComponent(".zsh_history"))
        candidates.append(home.appendingPathComponent(".bash_history"))
        for url in candidates {
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
            // zsh history isn't always valid UTF-8 (metafied bytes); decode leniently.
            let text = String(decoding: data, as: UTF8.self)
            let commands = parse(text)
            if !commands.isEmpty { return Array(commands.suffix(limit)) }
        }
        return []
    }

    static func parse(_ text: String) -> [String] {
        var commands: [String] = []
        var pending: String?
        for rawLine in text.components(separatedBy: "\n") {
            var line = rawLine
            if pending == nil, line.hasPrefix(": "), let semicolon = line.firstIndex(of: ";") {
                // ": 1700000000:0;command"
                line = String(line[line.index(after: semicolon)...])
            }
            if let current = pending {
                line = current + "\n" + line
            }
            if line.hasSuffix("\\") {
                pending = String(line.dropLast())
                continue
            }
            pending = nil
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed.count < 500 {
                commands.append(trimmed)
            }
        }
        return commands
    }
}
