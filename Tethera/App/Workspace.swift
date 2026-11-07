import AppKit
import Foundation
import TetheraKit

/// The window's layout: which session each pane shows, which pane has focus, and the overlays.
@MainActor
final class Workspace: ObservableObject {
    static let shared = Workspace()

    struct Pane: Identifiable, Codable, Equatable {
        var id = UUID()
        var session: UUID?
    }

    enum Axis: String, Codable {
        case horizontal, vertical
    }

    @Published var panes: [Pane] = [Pane()]
    @Published var axis: Axis = .horizontal
    @Published var focusedPane: UUID
    @Published var showPalette = false
    @Published var showOverview = false
    /// The session whose name is being edited in the sidebar.
    @Published var renaming: UUID?

    private let client = DaemonClient.shared
    private var restored = false
    /// A session is on its way for an empty window; don't ask for another.
    private var creatingFirst = false
    private static let layoutKey = "tethera.layout.v4"

    private init() {
        let first = Pane()
        panes = [first]
        focusedPane = first.id
    }

    var focusedSessionID: UUID? {
        panes.first { $0.id == focusedPane }?.session
    }

    var focusedSession: SessionInfo? {
        client.session(focusedSessionID)
    }

    // MARK: Showing sessions

    /// Shows a session: focuses the pane that already shows it, otherwise puts it in the focused pane.
    func show(_ id: UUID) {
        if let pane = panes.first(where: { $0.session == id }) {
            focusedPane = pane.id
        } else if let index = panes.firstIndex(where: { $0.id == focusedPane }) {
            panes[index].session = id
        }
        save()
        focusTerminalSoon()
    }

    func focus(pane: UUID) {
        guard focusedPane != pane else { return }
        focusedPane = pane
        save()
    }

    func focusTerminalSoon() {
        DispatchQueue.main.async { [weak self] in
            guard let id = self?.focusedSessionID else { return }
            TerminalStore.shared.existing(id)?.focus()
        }
    }

    /// Steps through sessions in sidebar order (⌘] / ⌘[).
    func cycle(_ offset: Int) {
        let sessions = client.sessions
        guard !sessions.isEmpty else { return }
        let current = sessions.firstIndex { $0.id == focusedSessionID } ?? 0
        let next = (current + offset + sessions.count) % sessions.count
        show(sessions[next].id)
    }

    func show(index: Int) {
        let sessions = client.sessions
        guard sessions.indices.contains(index) else { return }
        show(sessions[index].id)
    }

    /// Goes to the session that has waited longest for you (⌘⇧U).
    func jumpToNeedsYou() {
        let waiting = client.sessions
            .filter { $0.agent?.state == .needsInput || $0.agent?.unseen == true }
            .sorted { ($0.agent?.state.attentionRank ?? 9, $0.agent?.since ?? .distantFuture) < ($1.agent?.state.attentionRank ?? 9, $1.agent?.since ?? .distantFuture) }
        if let first = waiting.first(where: { $0.id != focusedSessionID }) ?? waiting.first {
            show(first.id)
        }
    }

    // MARK: Creating and closing

    /// Starts a session in the focused session's folder. Agents are typed into the shell, so the
    /// session (and its scrollback) outlives the agent.
    func newSession(agent: AgentKind? = nil, command: String? = nil, cwd: String? = nil, inNewPane: Axis? = nil) {
        let preferences = PreferencesStore.shared.value
        let directory = cwd ?? focusedSession?.cwd ?? preferences.startDirectory ?? NSHomeDirectory()
        var spec = SessionSpec(cwd: directory, shell: preferences.shell)
        if let size = focusedSessionID.flatMap({ TerminalStore.shared.existing($0)?.gridSize }) {
            spec.cols = size.cols
            spec.rows = size.rows
        }
        if let command = command ?? agent?.command {
            spec.initialInput = command + "\r"
        }
        client.create(spec) { [weak self] info in
            guard let self else { return }
            if let axis = inNewPane {
                self.axis = axis
                let pane = Pane(session: info.id)
                let index = (self.panes.firstIndex { $0.id == self.focusedPane } ?? self.panes.count - 1) + 1
                self.panes.insert(pane, at: index)
                self.focusedPane = pane.id
                self.save()
                self.focusTerminalSoon()
            } else {
                self.show(info.id)
            }
        }
    }

    func split(_ axis: Axis) {
        guard panes.count < 4 else { return }
        newSession(inNewPane: axis)
    }

    /// Closes the focused pane (the session keeps running); the last pane can't be closed.
    func closeFocusedPane() {
        guard panes.count > 1, let index = panes.firstIndex(where: { $0.id == focusedPane }) else { return }
        panes.remove(at: index)
        focusedPane = panes[min(index, panes.count - 1)].id
        save()
        focusTerminalSoon()
    }

    /// Ends a session; its pane moves on to another one.
    func close(_ id: UUID) {
        client.close(id)
    }

    // MARK: Keeping the layout valid

    /// Called whenever the session list changes.
    func sessionsChanged() {
        let sessions = client.sessions
        let ids = Set(sessions.map(\.id))
        TerminalStore.shared.prune(keeping: ids)
        if !restored && client.hasLoaded {
            restored = true
            restore(valid: ids)
        }
        if !sessions.isEmpty { creatingFirst = false }
        // Panes whose session ended show the next session that isn't already on screen.
        var changed = false
        for index in panes.indices where panes[index].session.map({ !ids.contains($0) }) ?? true {
            let shown = Set(panes.compactMap(\.session))
            panes[index].session = sessions.first { !shown.contains($0.id) }?.id
            changed = true
        }
        if panes.count > 1 {
            let before = panes.count
            panes.removeAll { $0.session == nil }
            if panes.isEmpty { panes = [Pane()] }
            changed = changed || panes.count != before
        }
        if !panes.contains(where: { $0.id == focusedPane }) {
            focusedPane = panes[0].id
            changed = true
        }
        if client.hasLoaded && sessions.isEmpty && restored && !creatingFirst {
            creatingFirst = true
            newSession()
        }
        if changed { save() }
    }

    private struct SavedLayout: Codable {
        var panes: [Pane]
        var axis: Axis
        var focusedIndex: Int
    }

    private func save() {
        let focusedIndex = panes.firstIndex { $0.id == focusedPane } ?? 0
        if let data = try? JSONEncoder().encode(SavedLayout(panes: panes, axis: axis, focusedIndex: focusedIndex)) {
            UserDefaults.standard.set(data, forKey: Self.layoutKey)
        }
    }

    private func restore(valid ids: Set<UUID>) {
        guard let data = UserDefaults.standard.data(forKey: Self.layoutKey),
              let saved = try? JSONDecoder().decode(SavedLayout.self, from: data) else { return }
        let kept = saved.panes.filter { $0.session.map(ids.contains) ?? false }
        guard !kept.isEmpty else { return }
        panes = kept
        axis = saved.axis
        focusedPane = kept[min(saved.focusedIndex, kept.count - 1)].id
    }
}
