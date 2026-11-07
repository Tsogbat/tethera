import SwiftUI

/// History search across every tab (⌘F / ⌃R).
struct SearchOverlayView: View {
    @EnvironmentObject private var settings: UserSettings
    @ObservedObject var historyManager: CommandHistoryManager
    let onJump: (CommandHistoryManager.HistoryEntry) -> Void
    let onDismiss: () -> Void

    @FocusState private var fieldFocused: Bool
    @State private var appeared = false
    @Namespace private var selection

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(settings.theme.isDark ? 0.28 : 0.12)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(settings.theme.accent)
                    TextField("Search commands and output", text: $historyManager.searchQuery)
                        .textFieldStyle(.plain)
                        .font(Typography.ui(15))
                        .foregroundStyle(settings.theme.textPrimary)
                        .focused($fieldFocused)
                        .onChange(of: historyManager.searchQuery) { _, value in historyManager.search(query: value) }
                        .onSubmit(jumpToSelection)
                    if !historyManager.searchResults.isEmpty {
                        Text("\(historyManager.selectedResultIndex + 1) of \(historyManager.searchResults.count)")
                            .font(Typography.ui(11).monospacedDigit())
                            .foregroundStyle(settings.theme.textTertiary)
                            .contentTransition(.numericText())
                    }
                    KeyHint(keys: "esc", label: "")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

                Rectangle().fill(settings.theme.hairline).frame(height: 0.5)

                Group {
                    if historyManager.searchQuery.isEmpty {
                        emptyState("Search everything you've run", detail: "↑↓ to move · ↩ to jump to the block or insert the command")
                    } else if historyManager.searchResults.isEmpty {
                        emptyState("No matches", detail: "Try part of a command or something it printed")
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(spacing: 1) {
                                    ForEach(Array(historyManager.searchResults.enumerated()), id: \.element.id) { index, entry in
                                        SearchResultRow(entry: entry,
                                                        isSelected: index == historyManager.selectedResultIndex,
                                                        query: historyManager.searchQuery,
                                                        selection: selection)
                                            .id(entry.id)
                                            .onTapGesture {
                                                historyManager.selectedResultIndex = index
                                                jumpToSelection()
                                            }
                                            .onHover { inside in if inside { historyManager.selectedResultIndex = index } }
                                    }
                                }
                                .padding(6)
                                .animation(Motion.snappy, value: historyManager.selectedResultIndex)
                            }
                            .onChange(of: historyManager.selectedResultIndex) { _, index in
                                guard historyManager.searchResults.indices.contains(index) else { return }
                                withAnimation(Motion.quick) {
                                    proxy.scrollTo(historyManager.searchResults[index].id, anchor: .center)
                                }
                            }
                        }
                    }
                }
                .frame(height: 360)
            }
            .frame(width: 640)
            .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), elevated: true)
            .padding(.top, 90)
            .scaleEffect(appeared ? 1 : 0.97)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            fieldFocused = true
            withAnimation(Motion.snappy) { appeared = true }
        }
        .onKeyPress(.upArrow) {
            historyManager.selectPreviousResult()
            return .handled
        }
        .onKeyPress(.downArrow) {
            historyManager.selectNextResult()
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    private func emptyState(_ title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(Typography.ui(13, weight: .medium))
                .foregroundStyle(settings.theme.textSecondary)
            Text(detail)
                .font(Typography.ui(11.5))
                .foregroundStyle(settings.theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func jumpToSelection() {
        if let result = historyManager.currentResult {
            onJump(result)
        }
    }
}

struct SearchResultRow: View {
    @EnvironmentObject private var settings: UserSettings
    let entry: CommandHistoryManager.HistoryEntry
    let isSelected: Bool
    let query: String
    let selection: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(entry.success == false ? settings.theme.danger : settings.theme.success.opacity(0.8))
                    .frame(width: 5, height: 5)
                Text(entry.command)
                    .font(Typography.mono(settings.themeConfiguration.fontFamily, size: 12.5, weight: .medium))
                    .foregroundStyle(settings.theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(BlockTerminalViewModel.abbreviate(entry.workingDirectory))
                    .font(Typography.mono(settings.themeConfiguration.fontFamily, size: 10.5))
                    .foregroundStyle(settings.theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: 160, alignment: .trailing)
                Text(entry.timestamp, format: .relative(presentation: .named))
                    .font(Typography.ui(10.5))
                    .foregroundStyle(settings.theme.textTertiary)
            }
            if let snippet = matchingLine {
                Text(snippet)
                    .font(Typography.mono(settings.themeConfiguration.fontFamily, size: 11))
                    .foregroundStyle(settings.theme.textSecondary)
                    .lineLimit(1)
                    .padding(.leading, 13)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(settings.theme.accentSoft)
                    .matchedGeometryEffect(id: "selection", in: selection)
            }
        }
        .contentShape(Rectangle())
    }

    private var matchingLine: String? {
        guard !query.isEmpty, !entry.command.lowercased().contains(query.lowercased()) else { return nil }
        return entry.output.split(separator: "\n").first { $0.lowercased().contains(query.lowercased()) }
            .map { String($0.trimmingCharacters(in: .whitespaces).prefix(160)) }
    }
}
