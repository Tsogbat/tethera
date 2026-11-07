import AppKit
import SwiftUI
import TetheraKit

/// The strip above the panes: what the focused session is, where, and what its agent is doing.
struct TitleBar: View {
    @ObservedObject private var client = DaemonClient.shared
    @ObservedObject private var workspace = Workspace.shared
    @ObservedObject private var git = GitMonitor.shared
    @ObservedObject private var preferences = PreferencesStore.shared
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            if let session = workspace.focusedSession {
                Breadcrumb(session: session, git: git.status(for: session.cwd))
                Spacer(minLength: 12)
                AgentStateLabel(session: session)
            } else {
                Spacer()
            }
            HStack(spacing: 2) {
                IconButton(systemName: "rectangle.split.2x1", help: "Split right (⌘D)") { workspace.split(.horizontal) }
                IconButton(systemName: "rectangle.split.1x2", help: "Split down (⇧⌘D)") { workspace.split(.vertical) }
                IconButton(systemName: "sidebar.right", help: "Inspector (⌥⌘I)", active: preferences.value.showInspector) {
                    preferences.value.showInspector.toggle()
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Metrics.titlebarHeight)
        .background(WindowDragArea())
        .background(theme.bg.color)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline.color).frame(height: 1) }
    }
}

struct Breadcrumb: View {
    let session: SessionInfo
    let git: GitStatus?
    var compact = false
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 7) {
            Text(session.name)
                .font(TypeScale.ui(compact ? 11.5 : 12.5, .semibold))
                .foregroundStyle(theme.text.color)
                .lineLimit(1)
            Text(session.displayPath)
                .font(TypeScale.ui(compact ? 11 : 12))
                .foregroundStyle(theme.text3.color)
                .lineLimit(1)
                .truncationMode(.head)
            if let git {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: compact ? 9 : 10))
                    Text(git.info.branch).lineLimit(1)
                    if git.info.isDirty { Text("±\(git.files.count)").foregroundStyle(theme.text3.color) }
                    if let ab = git.info.aheadBehindText { Text(ab).foregroundStyle(theme.text3.color) }
                }
                .font(TypeScale.ui(compact ? 11 : 12))
                .foregroundStyle(theme.text2.color)
            }
        }
    }
}

/// "Needs you · permission 2m", a spinner and "Working 41s", "Done"… as words, not badges.
struct AgentStateLabel: View {
    let session: SessionInfo
    @Environment(\.theme) private var theme

    var body: some View {
        if let agent = session.agent {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 6) {
                    SessionGlyph(agent: agent.kind, size: 11, color: tone.color(theme))
                    if agent.state == .working { WorkingSpinner(color: theme.text2.color) }
                    Text(text(now: context.date))
                        .font(TypeScale.ui(11.5, tone == .attention ? .semibold : .medium))
                        .foregroundStyle(tone.color(theme))
                        .lineLimit(1)
                }
            }
        }
    }

    private var tone: Tone {
        switch session.agent?.state {
        case .needsInput: return .attention
        case .error: return .danger
        case .done: return .strong
        default: return .plain
        }
    }

    private func text(now: Date) -> String {
        guard let agent = session.agent else { return "" }
        var parts = [agent.kind.displayName, agent.state.label]
        if let reason = agent.reason, agent.state == .needsInput { parts[1] = "Needs \(reason)" }
        parts.append(Elapsed.short(since: agent.since, now: now))
        return parts.joined(separator: " · ")
    }
}

/// One or more panes; split panes are resizable and each gets a slim header.
struct PaneArea: View {
    @ObservedObject private var workspace = Workspace.shared
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if workspace.panes.count == 1, let pane = workspace.panes.first {
                PaneView(pane: pane, showsHeader: false)
            } else if workspace.axis == .horizontal {
                HSplitView {
                    ForEach(workspace.panes) { PaneView(pane: $0, showsHeader: true) }
                }
            } else {
                VSplitView {
                    ForEach(workspace.panes) { PaneView(pane: $0, showsHeader: true) }
                }
            }
        }
        .background(theme.bg.color)
    }
}

struct PaneView: View {
    let pane: Workspace.Pane
    let showsHeader: Bool
    @ObservedObject private var client = DaemonClient.shared
    @ObservedObject private var workspace = Workspace.shared
    @ObservedObject private var git = GitMonitor.shared
    @Environment(\.theme) private var theme

    private var isFocused: Bool { workspace.focusedPane == pane.id }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader, let session = client.session(pane.session) {
                HStack(spacing: 8) {
                    Breadcrumb(session: session, git: git.status(for: session.cwd), compact: true)
                    Spacer(minLength: 8)
                    if session.agent != nil {
                        Text(session.subtitle.text)
                            .font(TypeScale.ui(11, session.subtitle.tone.weight))
                            .foregroundStyle(session.subtitle.tone.color(theme))
                            .lineLimit(1)
                    }
                    IconButton(systemName: "xmark", help: "Close pane (⌘W) — the session keeps running") {
                        workspace.focus(pane: pane.id)
                        workspace.closeFocusedPane()
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(theme.surface.color)
                .overlay(alignment: .top) {
                    Rectangle().fill(isFocused ? theme.accent.color.opacity(0.6) : .clear).frame(height: 1)
                }
                .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline.color).frame(height: 1) }
                .contentShape(Rectangle())
                .onTapGesture { workspace.focus(pane: pane.id); workspace.focusTerminalSoon() }
            }
            switch pane.content {
            case .home:
                if showsHeader { homeHeader }
                HomeView()
                    .simultaneousGesture(TapGesture().onEnded { workspace.focus(pane: pane.id) })
            case .session(let id):
                TerminalHost(sessionID: id, paneID: pane.id)
            }
        }
        .frame(minWidth: 240, minHeight: 120)
    }

    private var homeHeader: some View {
        HStack(spacing: 8) {
            Text("Home").font(TypeScale.ui(11.5, .medium)).foregroundStyle(theme.text2.color)
            Spacer(minLength: 8)
            IconButton(systemName: "xmark", help: "Close pane (⌘W)") {
                workspace.focus(pane: pane.id)
                workspace.closeFocusedPane()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(theme.surface.color)
        .overlay(alignment: .top) {
            Rectangle().fill(isFocused ? theme.accent.color.opacity(0.6) : .clear).frame(height: 1)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline.color).frame(height: 1) }
    }
}

/// Puts the session's terminal view in this pane. Views are kept per session, so switching is
/// instant and scrollback survives.
struct TerminalHost: NSViewRepresentable {
    let sessionID: UUID
    let paneID: UUID

    func makeNSView(context: Context) -> TerminalSlot {
        TerminalSlot()
    }

    func updateNSView(_ slot: TerminalSlot, context: Context) {
        let terminal = TerminalStore.shared.terminal(for: sessionID)
        terminal.onFocus = { Workspace.shared.focus(pane: paneID) }
        slot.show(terminal.hostView)
        terminal.attachIfNeeded()
    }
}

final class TerminalSlot: NSView {
    func show(_ view: NSView) {
        guard view.superview !== self else { return }
        subviews.forEach { $0.removeFromSuperview() }
        view.removeFromSuperview()
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }
}

/// The bottom strip: what needs you across every session, and the focused agent's numbers.
struct StatusBar: View {
    @ObservedObject private var client = DaemonClient.shared
    @ObservedObject private var workspace = Workspace.shared
    @Environment(\.theme) private var theme

    var body: some View {
        let needsYou = client.sessions.filter(\.needsYou)
        let working = client.sessions.filter(\.isWorking)
        HStack(spacing: 16) {
            if !needsYou.isEmpty {
                Button {
                    workspace.jumpToNeedsYou()
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(theme.accent.color).frame(width: 6, height: 6)
                        Text(needsYou.count == 1 ? "\(needsYou[0].name) needs you" : "\(needsYou.count) sessions need you")
                        Text("⇧⌘U").foregroundStyle(theme.text3.color)
                    }
                    .font(TypeScale.ui(11, .semibold))
                    .foregroundStyle(theme.accent.color)
                }
                .buttonStyle(.plain)
            }
            if !working.isEmpty {
                HStack(spacing: 5) {
                    WorkingSpinner(color: theme.text3.color)
                    Text("\(working.count) working")
                }
            }
            Spacer()
            if let agent = workspace.focusedSession?.agent {
                Text(agentDetail(agent))
            }
            Text("\(client.sessions.count) sessions")
            Text("⌘K").foregroundStyle(theme.text3.color.opacity(0.8))
        }
        .font(TypeScale.ui(11))
        .foregroundStyle(theme.text3.color)
        .padding(.horizontal, 12)
        .frame(height: Metrics.statusBarHeight)
        .background(theme.surface.color)
        .overlay(alignment: .top) { Rectangle().fill(theme.hairline.color).frame(height: 1) }
    }

    private func agentDetail(_ agent: AgentInfo) -> String {
        var parts: [String] = []
        if let model = agent.model { parts.append(model) }
        if let context = agent.contextPercent { parts.append("ctx \(Int(context.rounded()))%") }
        if let cost = agent.costUSD { parts.append(String(format: "$%.2f", cost)) }
        if let tool = agent.lastTool { parts.append(tool) }
        return parts.joined(separator: " · ")
    }
}
