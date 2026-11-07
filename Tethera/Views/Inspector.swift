import SwiftUI
import TetheraKit

struct InspectorView: View {
    enum Tab: String, CaseIterable {
        case agent = "Agent"
        case git = "Git"
    }

    @ObservedObject private var workspace = Workspace.shared
    @ObservedObject private var client = DaemonClient.shared
    @Environment(\.theme) private var theme
    @State private var tab: Tab = .agent

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ForEach(Tab.allCases, id: \.self) { item in
                    Button { tab = item } label: {
                        VStack(spacing: 6) {
                            Text(item.rawValue)
                                .font(TypeScale.ui(12, tab == item ? .semibold : .regular))
                                .foregroundStyle(tab == item ? theme.text.color : theme.text3.color)
                            Rectangle().fill(tab == item ? theme.text.color : .clear).frame(height: 1)
                        }
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: Metrics.titlebarHeight, alignment: .bottom)
            .background(WindowDragArea())
            .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline.color).frame(height: 1) }

            ScrollView {
                if let session = workspace.focusedSession {
                    switch tab {
                    case .agent: AgentInspector(session: session)
                    case .git: GitInspector(cwd: session.cwd)
                    }
                }
            }
        }
        .frame(width: Metrics.inspectorWidth)
        .background(theme.surface.color)
    }
}

private struct Field: View {
    let label: String
    let value: String
    var tone: Tone = .plain
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(TypeScale.ui(11))
                .foregroundStyle(theme.text3.color)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(TypeScale.ui(12, tone.weight))
                .foregroundStyle(tone == .plain ? theme.text.color : tone.color(theme))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AgentInspector: View {
    let session: SessionInfo
    @ObservedObject private var detector = AgentDetector.shared
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let agent = session.agent {
                HStack(spacing: 10) {
                    SessionGlyph(agent: agent.kind, size: 18, color: theme.text.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.kind.displayName).font(TypeScale.ui(14, .semibold)).foregroundStyle(theme.text.color)
                        Text(session.foreground ?? agent.kind.command).font(TypeScale.mono(11)).foregroundStyle(theme.text3.color)
                    }
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 8) {
                        Field(label: "State", value: stateText(agent), tone: tone(agent))
                        Field(label: "For", value: Elapsed.short(since: agent.since, now: context.date))
                        if let message = agent.message, !message.isEmpty { Field(label: "Message", value: message) }
                        if let tool = agent.lastTool { Field(label: "Tool", value: tool) }
                        if let model = agent.model { Field(label: "Model", value: model) }
                        if let context = agent.contextPercent { Field(label: "Context", value: "\(Int(context.rounded()))% used") }
                        if let cost = agent.costUSD { Field(label: "Cost", value: String(format: "$%.2f", cost)) }
                    }
                }
                HStack(spacing: 8) {
                    Button("Interrupt  ⌃C") { DaemonClient.shared.interrupt(session.id) }
                    Button("Focus") { Workspace.shared.show(session.id) }
                }
                .controlSize(.small)
                if agent.model == nil && agent.kind == .claude {
                    Text("Connect Claude Code in Settings → Agents to see its model, context and cost here.")
                        .font(TypeScale.ui(11))
                        .foregroundStyle(theme.text3.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "No agent running")
                    Text("Start one in \(session.displayPath). It runs inside this session’s shell, so the history stays when it exits.")
                        .font(TypeScale.ui(12))
                        .foregroundStyle(theme.text2.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 0) {
                    ForEach(detector.installed.filter { $0 != .ollama }, id: \.self) { kind in
                        AgentLaunchRow(kind: kind) {
                            DaemonClient.shared.send(session.id, Data((kind.command + "\r").utf8))
                            Workspace.shared.focusTerminalSoon()
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Session")
                Field(label: "Folder", value: session.displayPath)
                Field(label: "Shell", value: (session.shell as NSString).lastPathComponent)
                if let pid = session.pid { Field(label: "PID", value: "\(pid)") }
                Field(label: "Started", value: session.createdAt.formatted(date: .abbreviated, time: .shortened))
                if let code = session.lastExitCode { Field(label: "Last exit", value: "\(code)", tone: code == 0 ? .plain : .danger) }
            }
        }
        .padding(16)
    }

    private func stateText(_ agent: AgentInfo) -> String {
        if agent.state == .needsInput, let reason = agent.reason { return "Needs \(reason)" }
        return agent.state.label
    }

    private func tone(_ agent: AgentInfo) -> Tone {
        switch agent.state {
        case .needsInput: return .attention
        case .error: return .danger
        case .done: return .strong
        default: return .plain
        }
    }
}

private struct AgentLaunchRow: View {
    let kind: AgentKind
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SessionGlyph(agent: kind, size: 13, color: theme.text2.color)
                Text(kind.displayName).font(TypeScale.ui(12.5)).foregroundStyle(theme.text.color)
                Spacer()
                Text(kind.command).font(TypeScale.mono(11)).foregroundStyle(theme.text3.color)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Metrics.controlRadius).fill(hovering ? theme.raised.color : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct GitInspector: View {
    let cwd: String
    @ObservedObject private var monitor = GitMonitor.shared
    @Environment(\.theme) private var theme
    @State private var message = ""
    @State private var busy: String?
    @State private var lastOutput: String?

    var body: some View {
        let status = monitor.status(for: cwd)
        VStack(alignment: .leading, spacing: 16) {
            if let status {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch").foregroundStyle(theme.text3.color)
                    Text(status.info.branch).font(TypeScale.ui(13, .semibold)).foregroundStyle(theme.text.color)
                    if let ab = status.info.aheadBehindText { Text(ab).font(TypeScale.ui(12)).foregroundStyle(theme.text2.color) }
                    Spacer()
                    if let busy { ProgressView().controlSize(.mini); Text(busy).font(TypeScale.ui(11)).foregroundStyle(theme.text3.color) }
                }
                HStack(spacing: 6) {
                    Button("Fetch") { run("Fetching", ["fetch", "--prune"]) }
                    Button("Pull") { run("Pulling", ["pull", "--ff-only"]) }
                    Button("Push") { run("Pushing", ["push"]) }
                }
                .controlSize(.small)
                .disabled(busy != nil)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        SectionLabel(text: status.files.isEmpty ? "No changes" : "\(status.files.count) changed")
                        Spacer()
                        if !status.files.isEmpty {
                            Button("Stage All") { run("Staging", ["add", "-A"]) }
                                .buttonStyle(.plain).font(TypeScale.ui(11)).foregroundStyle(theme.text2.color)
                        }
                    }
                    ForEach(status.files.prefix(200)) { file in
                        GitFileRow(file: file, cwd: cwd) { label, args in run(label, args) }
                    }
                }

                if !status.files.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Commit message", text: $message, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                        Button(status.files.contains(where: \.isStaged) ? "Commit Staged" : "Commit All") {
                            let staged = status.files.contains(where: \.isStaged)
                            run("Committing", staged ? ["commit", "-m", message] : ["commit", "-am", message]) { ok in
                                if ok { message = "" }
                            }
                        }
                        .controlSize(.small)
                        .disabled(message.trimmingCharacters(in: .whitespaces).isEmpty || busy != nil)
                    }
                }
                if let lastOutput, !lastOutput.isEmpty {
                    Text(lastOutput)
                        .font(TypeScale.mono(10.5))
                        .foregroundStyle(theme.text2.color)
                        .textSelection(.enabled)
                        .lineLimit(8)
                }
            } else {
                SectionLabel(text: "Not a git repository")
                Text(cwd).font(TypeScale.mono(11)).foregroundStyle(theme.text3.color)
                Button("Initialize Repository") { run("Initializing", ["init"]) }.controlSize(.small)
            }
        }
        .padding(16)
    }

    private func run(_ label: String, _ arguments: [String], then: ((Bool) -> Void)? = nil) {
        busy = label
        Task {
            let result = await GitService.run(arguments, in: cwd)
            busy = nil
            lastOutput = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            monitor.refresh(cwd)
            then?(result.ok)
        }
    }
}

private struct GitFileRow: View {
    let file: GitFile
    let cwd: String
    let run: (String, [String]) -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(file.letter)
                .font(TypeScale.mono(10.5, .semibold))
                .foregroundStyle(file.isStaged ? theme.text.color : (file.isUntracked ? theme.text3.color : theme.text2.color))
                .frame(width: 12)
            Text(file.path)
                .font(TypeScale.mono(11))
                .foregroundStyle(theme.text.color)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 4)
            if hovering {
                Button(file.isStaged ? "Unstage" : "Stage") {
                    run(file.isStaged ? "Unstaging" : "Staging", file.isStaged ? ["restore", "--staged", "--", file.path] : ["add", "--", file.path])
                }
                .buttonStyle(.plain)
                .font(TypeScale.ui(10.5))
                .foregroundStyle(theme.text2.color)
                if !file.isUntracked && !file.isStaged {
                    Button("Discard") { confirmDiscard() }
                        .buttonStyle(.plain)
                        .font(TypeScale.ui(10.5))
                        .foregroundStyle(theme.danger.color)
                }
            }
        }
        .frame(height: 20)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private func confirmDiscard() {
        let alert = NSAlert()
        alert.messageText = "Discard changes to \(file.path)?"
        alert.informativeText = "This can't be undone."
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            run("Discarding", ["restore", "--", file.path])
        }
    }
}
