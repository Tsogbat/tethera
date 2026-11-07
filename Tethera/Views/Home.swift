import AppKit
import SwiftUI
import TetheraKit

/// Where Tethera opens: start an agent, pick up a folder, see who's running and who needs you.
/// Lists and type only, no cards.
struct HomeView: View {
    @ObservedObject private var client = DaemonClient.shared
    @ObservedObject private var workspace = Workspace.shared
    @ObservedObject private var detector = AgentDetector.shared
    @Environment(\.theme) private var theme
    @State private var connected: [AgentIntegrations.Target: Bool] = [:]
    @State private var recents: [String] = []

    private var needsYou: [SessionInfo] { client.sessions.filter(\.needsYou) }
    private var working: [SessionInfo] { client.sessions.filter(\.isWorking) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                RetroComputerView(screen: screen, dark: theme.isDark, onKey: pressed)
                    .frame(width: 440, height: 290)
                    .padding(.top, 12)
                greeting
                    .padding(.top, 6)
                    .padding(.bottom, 30)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 36, alignment: .top)],
                          alignment: .leading, spacing: 28) {
                    start
                    recent
                    agents
                }
                .frame(maxWidth: 1000)
                running
                    .frame(maxWidth: 1000)
                    .padding(.top, 30)
                Text("⌘K command palette   ·   ⇧⌘A agents overview   ·   ⇧⌘U next that needs you   ·   ⇧⌘H home")
                    .font(TypeScale.mono(10.5))
                    .foregroundStyle(theme.text3.color)
                    .padding(.top, 34)
                    .padding(.bottom, 28)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .background(theme.bg.color)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private var screen: RetroScreenState {
        if !needsYou.isEmpty { return .count(needsYou.count, needsYou.count == 1 ? "needs you" : "need you") }
        if !working.isEmpty { return .count(working.count, "working") }
        return .prompt
    }

    private func refresh() {
        recents = RecentFolders.all
        for target in AgentIntegrations.Target.allCases { connected[target] = AgentIntegrations.isConnected(target) }
    }

    /// The keyboard does things: `t` opens a shell, `⌘`/`K` the palette, `return` an agent.
    private func pressed(_ key: String) {
        switch key {
        case "t": workspace.newSession()
        case "⌘", "K": workspace.showPalette = true
        case "D": workspace.split(.horizontal)
        case "return":
            if let first = needsYou.first { workspace.show(first.id) } else { workspace.newSession(agent: detector.installed.first ?? .claude) }
        default: break
        }
    }

    // MARK: Greeting

    private var greeting: some View {
        VStack(spacing: 6) {
            Text(salutation)
                .font(TypeScale.ui(22, .semibold))
                .foregroundStyle(theme.text.color)
            Text(summary)
                .font(TypeScale.ui(13))
                .foregroundStyle(theme.text2.color)
        }
    }

    private var salutation: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning."
        case 12..<18: return "Good afternoon."
        default: return "Good evening."
        }
    }

    private var summary: String {
        var parts: [String] = []
        if !needsYou.isEmpty { parts.append(needsYou.count == 1 ? "1 agent needs you" : "\(needsYou.count) agents need you") }
        if !working.isEmpty { parts.append("\(working.count) working") }
        let others = client.sessions.count - needsYou.count - working.count
        if others > 0 {
            let noun = others == 1 ? "session" : "sessions"
            parts.append(parts.isEmpty ? "\(others) \(noun) running" : "\(others) other \(noun)")
        }
        return parts.isEmpty ? "Nothing running. Start something below." : parts.joined(separator: " · ")
    }

    // MARK: Columns

    private var start: some View {
        HomeColumn(title: "Start") {
            HomeRow(title: "Shell", shortcut: "⌘T") { workspace.newSession() }
            ForEach(Array(AgentDetector.launchable.filter { $0 != .ollama }.enumerated()), id: \.element) { index, kind in
                let installed = detector.status(for: kind)?.isInstalled ?? false
                HomeRow(glyph: kind, title: kind.displayName,
                        detail: installed ? nil : "not installed",
                        shortcut: index < 4 ? "⌥⌘\(index + 1)" : nil, dimmed: !installed) {
                    workspace.newSession(agent: kind)
                }
            }
            if detector.status(for: .ollama)?.isInstalled == true {
                HomeRow(glyph: .ollama, title: "Ollama", detail: "local models", shortcut: "▸") {
                    var items = [AgentKind.claude, .codex, .opencode].map { kind in
                        ("\(kind.displayName) on a local model", { workspace.newSession(command: "ollama launch \(kind.rawValue)") })
                    }
                    items.append(("Chat", { workspace.newSession(command: "ollama run llama3.2") }))
                    ActionMenu.popUp(items)
                }
            }
        }
    }

    private var recent: some View {
        HomeColumn(title: "Recent") {
            if recents.isEmpty {
                Text("Folders you work in show up here.")
                    .font(TypeScale.ui(12))
                    .foregroundStyle(theme.text3.color)
                    .frame(height: 30)
            }
            ForEach(recents, id: \.self) { path in
                HomeRow(title: (path as NSString).lastPathComponent, detail: Self.abbreviate((path as NSString).deletingLastPathComponent)) {
                    workspace.newSession(cwd: path)
                }
                .contextMenu {
                    Button("New Shell Here") { workspace.newSession(cwd: path) }
                    ForEach(detector.installed.filter { $0 != .ollama }, id: \.self) { kind in
                        Button("New \(kind.displayName) Session Here") { workspace.newSession(agent: kind, cwd: path) }
                    }
                    Divider()
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                }
            }
            HomeRow(title: "Open folder…", shortcut: "⇧⌘O", dimmed: true) { SessionActions.newSessionInChosenFolder() }
        }
    }

    private var agents: some View {
        HomeColumn(title: "Agents") {
            ForEach(AgentIntegrations.Target.allCases, id: \.self) { target in
                let isConnected = connected[target] ?? false
                HomeRowLabel(glyph: target.kind, title: target.kind.displayName,
                             detail: isConnected ? "connected" : nil,
                             trailing: isConnected ? "●" : "○", dimmed: !isConnected)
            }
            HomeRow(title: "Connect agents…", detail: "Settings → Agents", dimmed: true) { SettingsOpener.open() }
        }
    }

    private var running: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: "Running")
                .padding(.bottom, 4)
            if client.sessions.isEmpty {
                Text("Sessions keep running when you quit Tethera. Start one above.")
                    .font(TypeScale.ui(12))
                    .foregroundStyle(theme.text3.color)
            }
            let ordered = client.sessions.sorted { ($0.agent?.state.attentionRank ?? 9) < ($1.agent?.state.attentionRank ?? 9) }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 0) {
                    ForEach(ordered) { session in
                        HomeRunningRow(session: session, now: context.date) { workspace.show(session.id) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

private struct HomeColumn<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: title)
                .padding(.bottom, 6)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A clickable list row: glyph, title, quiet detail, and a shortcut or marker on the right.
private struct HomeRow: View {
    var glyph: AgentKind?
    let title: String
    var detail: String?
    var shortcut: String?
    var dimmed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HomeRowLabel(glyph: glyph, title: title, detail: detail, trailing: shortcut, dimmed: dimmed)
        }
        .buttonStyle(HomeRowStyle())
    }
}

private struct HomeRowLabel: View {
    var glyph: AgentKind?
    let title: String
    var detail: String?
    var trailing: String?
    var dimmed = false
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 9) {
            if let glyph {
                SessionGlyph(agent: glyph, size: 12, color: dimmed ? theme.text3.color : theme.text2.color)
                    .frame(width: 14)
            }
            Text(title)
                .font(TypeScale.ui(13, .medium))
                .foregroundStyle(dimmed ? theme.text2.color : theme.text.color)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(TypeScale.ui(11.5))
                    .foregroundStyle(theme.text3.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing)
                    .font(TypeScale.mono(10.5))
                    .foregroundStyle(theme.text3.color)
            }
        }
        .frame(height: 30)
        .contentShape(Rectangle())
    }
}

private struct HomeRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HomeRowBackground(pressed: configuration.isPressed) { configuration.label }
    }
}

private struct HomeRowBackground<Label: View>: View {
    let pressed: Bool
    @ViewBuilder let label: Label
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        label
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: Metrics.controlRadius)
                    .fill(pressed ? theme.raised.color : (hovering ? theme.raised.color.opacity(0.6) : .clear))
            )
            .padding(.horizontal, -8)
            .onHover { hovering = $0 }
    }
}

private struct HomeRunningRow: View {
    let session: SessionInfo
    let now: Date
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SessionGlyph(agent: session.agent?.kind, size: 12,
                             color: session.needsYou ? theme.accent.color : theme.text2.color)
                    .frame(width: 14)
                Text(session.name)
                    .font(TypeScale.ui(13, session.needsYou ? .semibold : .medium))
                    .foregroundStyle(theme.text.color)
                    .frame(width: 170, alignment: .leading)
                    .lineLimit(1)
                if session.isWorking { WorkingSpinner(color: theme.text2.color) }
                Text(session.subtitle.text)
                    .font(TypeScale.ui(12, session.subtitle.tone.weight))
                    .foregroundStyle(session.subtitle.tone.color(theme))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if let agent = session.agent {
                    Text(Elapsed.short(since: agent.since, now: now))
                        .font(TypeScale.mono(10.5))
                        .foregroundStyle(theme.text3.color)
                }
                if session.needsYou {
                    Circle().fill(theme.accent.color).frame(width: 7, height: 7)
                }
            }
            .frame(height: 32)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline.color).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeRowStyle())
    }
}

/// A pop-up menu of closures at the mouse, for rows that offer a few choices.
@MainActor
enum ActionMenu {
    private final class Item: NSMenuItem {
        var handler: (() -> Void)?
        @objc func fire() { handler?() }
    }

    static func popUp(_ items: [(String, () -> Void)]) {
        let menu = NSMenu()
        for (title, handler) in items {
            let item = Item(title: title, action: #selector(Item.fire), keyEquivalent: "")
            item.handler = handler
            item.target = item
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}
