import SwiftUI

/// Overlay view for searching command history
struct SearchOverlayView: View {
    @ObservedObject var historyManager: CommandHistoryManager
    @EnvironmentObject private var userSettings: UserSettings
    @FocusState private var isSearchFocused: Bool
    let onJumpToBlock: (UUID) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            // Dimmed background
            SwiftUI.Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
            
            // Search panel
            VStack(spacing: 0) {
                // Search input
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.5))
                        .font(.system(size: 16))
                    
                    TextField("Search commands and output...", text: $historyManager.searchQuery)
                        .font(.system(size: 15))
                        .textFieldStyle(PlainTextFieldStyle())
                        .foregroundColor(userSettings.themeConfiguration.textColor.color)
                        .focused($isSearchFocused)
                        .onChange(of: historyManager.searchQuery) { _, newValue in
                            historyManager.search(query: newValue)
                        }
                        .onSubmit {
                            jumpToCurrentResult()
                        }
                    
                    // Result count
                    if !historyManager.searchResults.isEmpty {
                        Text("\(historyManager.selectedResultIndex + 1)/\(historyManager.searchResults.count)")
                            .font(.system(size: 12))
                            .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.5))
                    }
                    
                    // Navigation buttons
                    HStack(spacing: 4) {
                        Button(action: { historyManager.selectPreviousResult() }) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.6))
                                .frame(width: 24, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(userSettings.themeConfiguration.textColor.color.opacity(0.05))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(historyManager.selectedResultIndex == 0)
                        
                        Button(action: { historyManager.selectNextResult() }) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.6))
                                .frame(width: 24, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(userSettings.themeConfiguration.textColor.color.opacity(0.05))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(historyManager.selectedResultIndex >= historyManager.searchResults.count - 1)
                    }
                    
                    // Close button
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(userSettings.themeConfiguration.backgroundColor.color)
                
                // Separator
                Rectangle()
                    .fill(userSettings.themeConfiguration.textColor.color.opacity(0.1))
                    .frame(height: 1)
                
                // Results list
                if historyManager.searchResults.isEmpty && !historyManager.searchQuery.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.3))
                        Text("No results found")
                            .font(.system(size: 14))
                            .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(userSettings.themeConfiguration.backgroundColor.color.opacity(0.95))
                } else if !historyManager.searchResults.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(Array(historyManager.searchResults.enumerated()), id: \.element.id) { index, entry in
                                    SearchResultRow(
                                        entry: entry,
                                        isSelected: index == historyManager.selectedResultIndex,
                                        query: historyManager.searchQuery,
                                        onSelect: {
                                            historyManager.selectedResultIndex = index
                                            jumpToCurrentResult()
                                        }
                                    )
                                    .id(entry.id)
                                }
                            }
                            .padding(8)
                        }
                        .background(userSettings.themeConfiguration.backgroundColor.color.opacity(0.95))
                        .onChange(of: historyManager.selectedResultIndex) { _, newIndex in
                            if newIndex < historyManager.searchResults.count {
                                withAnimation {
                                    proxy.scrollTo(historyManager.searchResults[newIndex].id, anchor: .center)
                                }
                            }
                        }
                    }
                } else {
                    // Empty state when no query
                    VStack(spacing: 8) {
                        Text("Start typing to search command history")
                            .font(.system(size: 14))
                            .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.5))
                        Text("Press ↑↓ to navigate, Enter to jump")
                            .font(.system(size: 12))
                            .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.3))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(userSettings.themeConfiguration.backgroundColor.color.opacity(0.95))
                }
            }
            .frame(width: 600, height: 400)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(userSettings.themeConfiguration.textColor.color.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
        .onAppear {
            isSearchFocused = true
        }
        .onKeyPress(.upArrow) {
            historyManager.selectPreviousResult()
            return .handled
        }
        .onKeyPress(.downArrow) {
            historyManager.selectNextResult()
            return .handled
        }
    }
    
    private func jumpToCurrentResult() {
        if let result = historyManager.currentResult {
            onJumpToBlock(result.id)
            onDismiss()
        }
    }
}

// MARK: - Search Result Row
struct SearchResultRow: View {
    let entry: CommandHistoryManager.HistoryEntry
    let isSelected: Bool
    let query: String
    let onSelect: () -> Void
    @EnvironmentObject private var userSettings: UserSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Command
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(userSettings.themeConfiguration.accentColor.color)
                
                Text(entry.command)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(userSettings.themeConfiguration.textColor.color)
                    .lineLimit(1)
                
                Spacer()
                
                // Timestamp
                Text(formatDate(entry.timestamp))
                    .font(.system(size: 10))
                    .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.4))
            }
            
            // Output preview (if contains match)
            if !entry.output.isEmpty && entry.output.lowercased().contains(query.lowercased()) {
                Text(entry.output.prefix(100) + (entry.output.count > 100 ? "..." : ""))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.6))
                    .lineLimit(2)
                    .padding(.leading, 15)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected 
                    ? userSettings.themeConfiguration.accentColor.color.opacity(0.15)
                    : SwiftUI.Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isSelected ? userSettings.themeConfiguration.accentColor.color.opacity(0.3) : SwiftUI.Color.clear,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return "Today " + formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "HH:mm"
            return "Yesterday " + formatter.string(from: date)
        } else {
            formatter.dateFormat = "MMM d, HH:mm"
            return formatter.string(from: date)
        }
    }
}
