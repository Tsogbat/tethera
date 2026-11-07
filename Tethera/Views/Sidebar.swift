import SwiftUI
import TetheraKit

struct SidebarView: View {
    @ObservedObject private var client = DaemonClient.shared
    @ObservedObject private var workspace = Workspace.shared
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                Spacer()
                NewSessionMenu()
            }
            .padding(.trailing, 8)
            .frame(height: Metrics.titlebarHeight)
            .background(WindowDragArea())

            HStack {
                SectionLabel(text: "Sessions")
                Spacer()
                if !client.sessions.isEmpty {
                    Text("\(client.sessions.count)")
                        .font(TypeScale.mono(10))
                        .foregroundStyle(theme.text3.color)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 6)

            List {
                ForEach(client.sessions) { session in
                    SessionRow(session: session,
                               isSelected: session.id == workspace.focusedSessionID,
                               isOnScreen: workspace.panes.contains { $0.session == session.id })
                        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .onMove { source, destination in
                    var ids = client.sessions.map(\.id)
                    ids.move(fromOffsets: source, toOffset: destination)
                    client.reorder(ids)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, Metrics.rowHeight)

            SidebarFooter()
        }
        .background(theme.surface.color)
    }
}

struct SessionRow: View {
    let session: SessionInfo
    let isSelected: Bool
    let isOnScreen: Bool
    @ObservedObject private var workspace = Workspace.shared
    @Environment(\.theme) private var theme
    @State private var hovering = false
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: 9) {
            SessionGlyph(agent: session.agent?.kind, size: 13, color: glyphColor)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                nameView
                Text(session.subtitle.text)
                    .font(TypeScale.ui(11))
                    .foregroundStyle(session.subtitle.tone.color(theme))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 8)
        .frame(height: Metrics.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Metrics.panelRadius)
                .fill(isSelected ? theme.raised.color : (hovering ? theme.raised.color.opacity(0.5) : .clear))
        )
        .overlay(alignment: .leading) {
            // A 2pt amber edge marks a session waiting on you, even when it's selected.
            if session.needsYou {
                Capsule().fill(theme.accent.color).frame(width: 2, height: 18).offset(x: -1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { startRename() }
        .onTapGesture { workspace.show(session.id) }
        .contextMenu { menu }
    }

    @ViewBuilder
    private var nameView: some View {
        if workspace.renaming == session.id {
            TextField("Name", text: $draftName)
                .textFieldStyle(.plain)
                .font(TypeScale.ui(13, .medium))
                .focused($nameFocused)
                .onSubmit(commitRename)
                .onExitCommand { workspace.renaming = nil }
                .onAppear {
                    draftName = session.name
                    nameFocused = true
                }
                .onChange(of: nameFocused) { _, focused in if !focused { commitRename() } }
        } else {
            Text(session.name)
                .font(TypeScale.ui(13, isSelected ? .semibold : .medium))
                .foregroundStyle(session.isAlive ? theme.text.color : theme.text2.color)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if let agent = session.agent {
            switch agent.state {
            case .working:
                WorkingSpinner(color: theme.text3.color)
            case .needsInput:
                Text(Elapsed.short(since: agent.since))
                    .font(TypeScale.mono(10))
                    .foregroundStyle(theme.accent.color)
            case .done where agent.unseen:
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.success.color)
            case .error:
                Image(systemName: "exclamationmark").font(.system(size: 10, weight: .bold)).foregroundStyle(theme.danger.color)
            default:
                Text(Elapsed.short(since: agent.since))
                    .font(TypeScale.mono(10))
                    .foregroundStyle(theme.text3.color)
            }
        } else if isOnScreen && !isSelected {
            Circle().stroke(theme.text3.color, lineWidth: 1).frame(width: 5, height: 5)
        }
    }

    private var glyphColor: Color {
        guard let agent = session.agent else { return isSelected ? theme.text2.color : theme.text3.color }
        switch agent.state {
        case .needsInput: return theme.accent.color
        case .error: return theme.danger.color
        case .working: return theme.text.color
        default: return theme.text2.color
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Rename…") { startRename() }
        Button("Open in Split Right") {
            workspace.axis = .horizontal
            if !workspace.panes.contains(where: { $0.session == session.id }) {
                workspace.panes.append(Workspace.Pane(session: session.id))
                workspace.focus(pane: workspace.panes.last!.id)
            }
        }
        Button("New Session Here") { workspace.newSession(cwd: session.cwd) }
        Divider()
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: session.cwd)]) }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(session.cwd, forType: .string)
        }
        if session.agent != nil {
            Button("Interrupt (⌃C)") { DaemonClient.shared.interrupt(session.id) }
        }
        Divider()
        Button("End Session", role: .destructive) { SessionActions.confirmEnd(session) }
    }

    private func startRename() {
        workspace.renaming = session.id
    }

    private func commitRename() {
        guard workspace.renaming == session.id else { return }
        workspace.renaming = nil
        DaemonClient.shared.rename(session.id, to: draftName)
    }
}

/// "+" menu: a shell, or any installed agent, in the focused session's folder.
struct NewSessionMenu: View {
    @ObservedObject private var detector = AgentDetector.shared
    @Environment(\.theme) private var theme

    var body: some View {
        Menu {
            Button("Shell") { Workspace.shared.newSession() }
                .keyboardShortcut("t", modifiers: .command)
            let agents = detector.installed.filter { $0 != .ollama }
            if !agents.isEmpty {
                Section("Agents") {
                    ForEach(agents, id: \.self) { kind in
                        Button(kind.displayName) { Workspace.shared.newSession(agent: kind) }
                    }
                }
            }
            if detector.status(for: .ollama)?.isInstalled == true {
                Menu("Ollama (local models)") {
                    ForEach([AgentKind.claude, .codex, .opencode], id: \.self) { kind in
                        Button(kind.displayName) { Workspace.shared.newSession(command: "ollama launch \(kind.rawValue)") }
                    }
                    Button("Chat") { Workspace.shared.newSession(command: "ollama run llama3.2") }
                }
            }
            Divider()
            Button("Shell in Folder…") { SessionActions.newSessionInChosenFolder() }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.text2.color)
                .frame(width: 24, height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("New session")
    }
}

private struct SidebarFooter: View {
    @ObservedObject private var client = DaemonClient.shared
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            switch client.status {
            case .connected:
                Circle().fill(theme.success.color.opacity(0.8)).frame(width: 5, height: 5)
                Text("Sessions persist when you quit")
            case .connecting:
                ProgressView().controlSize(.mini)
                Text("Connecting to sessions…")
            case .failed(let message):
                Circle().fill(theme.danger.color).frame(width: 5, height: 5)
                Text(message).lineLimit(2)
            }
            Spacer()
        }
        .font(TypeScale.ui(10.5))
        .foregroundStyle(theme.text3.color)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(theme.hairline.color).frame(height: 1) }
    }
}

/// Actions that need a confirmation or a panel.
@MainActor
enum SessionActions {
    static func confirmEnd(_ session: SessionInfo) {
        let busy = session.agent != nil || session.isCommandRunning
        guard busy else {
            DaemonClient.shared.close(session.id)
            return
        }
        let alert = NSAlert()
        alert.messageText = "End “\(session.name)”?"
        alert.informativeText = session.agent.map { "\($0.kind.displayName) is running in this session. Ending it stops the agent." }
            ?? "\(session.foreground ?? "A command") is still running."
        alert.addButton(withTitle: "End Session")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            DaemonClient.shared.close(session.id)
        }
    }

    static func newSessionInChosenFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Open Session"
        if panel.runModal() == .OK, let url = panel.url {
            Workspace.shared.newSession(cwd: url.path)
        }
    }
}
