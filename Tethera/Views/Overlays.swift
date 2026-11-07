import SwiftUI
import TetheraKit

/// Every session in one table: who's working, who's waiting on you, for how long.
struct AgentsOverview: View {
    @ObservedObject private var client = DaemonClient.shared
    @ObservedObject private var workspace = Workspace.shared
    @Environment(\.theme) private var theme
    @State private var selection: UUID?
    @State private var sortOrder = [KeyPathComparator(\SessionInfo.order)]

    private var rows: [SessionInfo] {
        client.sessions.sorted { lhs, rhs in
            let l = lhs.agent?.state.attentionRank ?? 9, r = rhs.agent?.state.attentionRank ?? 9
            return l != r ? l < r : lhs.order < rhs.order
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Agents").font(TypeScale.ui(15, .semibold)).foregroundStyle(theme.text.color)
                Text(summary).font(TypeScale.ui(12)).foregroundStyle(theme.text3.color)
                Spacer()
                Button("Done") { workspace.showOverview = false }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.small)
            }
            .padding(16)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Table(rows, selection: $selection) {
                    TableColumn("Session") { session in
                        HStack(spacing: 8) {
                            SessionGlyph(agent: session.agent?.kind, size: 12, color: theme.text2.color)
                            Text(session.name).font(TypeScale.ui(12.5, .medium))
                        }
                    }
                    .width(min: 120, ideal: 160)
                    TableColumn("Agent") { session in
                        Text(session.agent?.kind.displayName ?? (session.foreground ?? "shell"))
                            .foregroundStyle(theme.text2.color)
                    }
                    .width(min: 80, ideal: 100)
                    TableColumn("State") { session in
                        let subtitle = session.subtitle
                        Text(session.agent?.state.label ?? (session.isAlive ? "Shell" : "Restored"))
                            .foregroundStyle(session.agent == nil ? theme.text3.color : subtitle.tone.color(theme))
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn("For") { session in
                        Text(Elapsed.short(since: session.agent?.since ?? session.lastActivity, now: context.date))
                            .font(TypeScale.mono(11))
                            .foregroundStyle(theme.text2.color)
                    }
                    .width(48)
                    TableColumn("Message") { session in
                        Text(session.agent?.message ?? session.lastNotification ?? "")
                            .foregroundStyle(theme.text2.color)
                            .lineLimit(1)
                    }
                    TableColumn("Folder") { session in
                        Text(session.displayPath).font(TypeScale.mono(11)).foregroundStyle(theme.text3.color).lineLimit(1).truncationMode(.head)
                    }
                    .width(min: 120, ideal: 200)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: false))
                .scrollContentBackground(.hidden)
                .contextMenu(forSelectionType: UUID.self) { _ in } primaryAction: { ids in
                    if let id = ids.first {
                        workspace.showOverview = false
                        workspace.show(id)
                    }
                }
            }
        }
        .frame(maxWidth: 1000, maxHeight: 560)
        .background(theme.surface.color)
    }

    private var summary: String {
        let waiting = client.sessions.filter(\.needsYou).count
        let working = client.sessions.filter(\.isWorking).count
        return [waiting > 0 ? "\(waiting) need you" : nil, working > 0 ? "\(working) working" : nil, "\(client.sessions.count) sessions"]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

/// ⌘K: every action and every session, by typing a few letters.
struct CommandPalette: View {
    struct Item: Identifiable {
        let id: String
        let title: String
        var detail: String = ""
        var shortcut: String = ""
        var agent: AgentKind?
        var isSession = false
        let action: () -> Void
    }

    @ObservedObject private var client = DaemonClient.shared
    @ObservedObject private var workspace = Workspace.shared
    @ObservedObject private var detector = AgentDetector.shared
    @Environment(\.theme) private var theme
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private var items: [Item] {
        var items: [Item] = client.sessions.map { session in
            Item(id: "s-\(session.id)", title: session.name, detail: session.subtitle.text, agent: session.agent?.kind, isSession: true) {
                workspace.show(session.id)
            }
        }
        items.append(Item(id: "new", title: "New Shell", shortcut: "⌘T") { workspace.newSession() })
        for kind in detector.installed where kind != .ollama {
            items.append(Item(id: "agent-\(kind)", title: "New \(kind.displayName) Session", detail: kind.command, agent: kind) {
                workspace.newSession(agent: kind)
            })
        }
        items += [
            Item(id: "split-r", title: "Split Right", shortcut: "⌘D") { workspace.split(.horizontal) },
            Item(id: "split-d", title: "Split Down", shortcut: "⇧⌘D") { workspace.split(.vertical) },
            Item(id: "needs", title: "Go to Session That Needs You", shortcut: "⇧⌘U") { workspace.jumpToNeedsYou() },
            Item(id: "overview", title: "Agents Overview", shortcut: "⇧⌘A") { workspace.showOverview = true },
            Item(id: "inspector", title: "Toggle Inspector", shortcut: "⌥⌘I") { PreferencesStore.shared.value.showInspector.toggle() },
            Item(id: "rename", title: "Rename Session…", shortcut: "⇧⌘R") { workspace.renaming = workspace.focusedSessionID },
            Item(id: "folder", title: "New Shell in Folder…") { SessionActions.newSessionInChosenFolder() },
            Item(id: "end", title: "End Session…", shortcut: "⌥⌘W") {
                if let session = workspace.focusedSession { SessionActions.confirmEnd(session) }
            },
            Item(id: "appearance", title: "Toggle Light / Dark") {
                let store = PreferencesStore.shared
                store.value.appearance = store.isDark ? .light : .dark
            },
            Item(id: "settings", title: "Settings…", shortcut: "⌘,") { SettingsOpener.open() },
        ]
        guard !query.isEmpty else { return items }
        return items
            .compactMap { item -> (Item, Int)? in
                guard let score = Fuzzy.score(query, in: item.title + " " + item.detail) else { return nil }
                return (item, score)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    var body: some View {
        let results = items
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.text3.color)
                TextField("Sessions and commands", text: $query)
                    .textFieldStyle(.plain)
                    .font(TypeScale.ui(14))
                    .focused($focused)
                    .onSubmit { run(results) }
                    .onChange(of: query) { _, _ in selected = 0 }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            Rectangle().fill(theme.hairline.color).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                            PaletteRow(item: item, isSelected: index == selected)
                                .id(index)
                                .onTapGesture { selected = index; run(results) }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 340)
                .onChange(of: selected) { _, value in proxy.scrollTo(value) }
            }
        }
        .frame(width: 560)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.surface.color))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.hairline.color))
        .shadow(color: .black.opacity(theme.isDark ? 0.5 : 0.15), radius: 24, y: 12)
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { selected = min(selected + 1, max(results.count - 1, 0)); return .handled }
        .onKeyPress(.upArrow) { selected = max(selected - 1, 0); return .handled }
        .onExitCommand { workspace.showPalette = false }
    }

    private func run(_ results: [Item]) {
        guard results.indices.contains(selected) else { return }
        workspace.showPalette = false
        results[selected].action()
    }
}

private struct PaletteRow: View {
    let item: CommandPalette.Item
    let isSelected: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if item.isSession || item.agent != nil {
                    SessionGlyph(agent: item.agent, size: 12, color: theme.text2.color)
                } else {
                    Image(systemName: "command").font(.system(size: 10)).foregroundStyle(theme.text3.color)
                }
            }
            .frame(width: 16)
            Text(item.title).font(TypeScale.ui(13)).foregroundStyle(theme.text.color).lineLimit(1)
            if !item.detail.isEmpty {
                Text(item.detail).font(TypeScale.ui(12)).foregroundStyle(theme.text3.color).lineLimit(1)
            }
            Spacer()
            Text(item.shortcut).font(TypeScale.ui(11)).foregroundStyle(theme.text3.color)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: Metrics.controlRadius).fill(isSelected ? theme.raised.color : .clear))
        .contentShape(Rectangle())
    }
}

/// Subsequence match with bonuses for word starts and consecutive letters.
enum Fuzzy {
    static func score(_ query: String, in text: String) -> Int? {
        let needle = Array(query.lowercased().filter { !$0.isWhitespace })
        let hay = Array(text.lowercased())
        guard !needle.isEmpty else { return 0 }
        var score = 0, index = 0, last = -2
        for (position, character) in hay.enumerated() where index < needle.count && character == needle[index] {
            score += 1
            if position == last + 1 { score += 3 }
            if position == 0 || hay[position - 1] == " " { score += 5 }
            last = position
            index += 1
        }
        return index == needle.count ? score : nil
    }
}
