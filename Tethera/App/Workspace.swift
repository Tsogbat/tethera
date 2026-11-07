import AppKit
import Foundation
import TetheraKit

/// The window's layout: which session each pane shows, which pane has focus, and the overlays.
@MainActor
final class Workspace: ObservableObject {
    static let shared = Workspace()

    struct Pane: Identifiable, Codable, Equatable {
        var id = UUID()
        var content: PaneContent = .home

        init(id: UUID = UUID(), content: PaneContent = .home) {
            self.id = id
            self.content = content
        }

        var session: UUID? { content.sessionID }

        private enum CodingKeys: String, CodingKey { case id, content, session }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            if let content = try? c.decode(PaneContent.self, forKey: .content) {
                self.content = content
            } else {
                // Layouts saved by 0.4 only had an optional session.
                self.content = (try? c.decodeIfPresent(UUID.self, forKey: .session)).flatMap { $0.map(PaneContent.session) } ?? .home
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(content, forKey: .content)
        }
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
    private static let layoutKey = "tethera.layout.v5"
    private static let legacyLayoutKey = "tethera.layout.v4"

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

    var isShowingHome: Bool {
        panes.first { $0.id == focusedPane }?.content == .home
    }

    // MARK: Showing sessions

    /// Shows a session: focuses the pane that already shows it, otherwise puts it in the focused pane.
    func show(_ id: UUID) {
        if let pane = panes.first(where: { $0.session == id }) {
            focusedPane = pane.id
        } else if let index = panes.firstIndex(where: { $0.id == focusedPane }) {
            panes[index].content = .session(id)
        }
        if let cwd = client.session(id)?.cwd { RecentFolders.note(cwd) }
        save()
        focusTerminalSoon()
    }

    /// Opens a tool beside the session that asked for it (or the focused pane): a pane that
    /// already shows it gets focus; Home is replaced; otherwise it splits, up to four panes,
    /// after which the last tool pane is reused.
    func open(_ content: PaneContent, besideSession session: UUID? = nil) {
        if let pane = panes.first(where: { $0.content == content }) {
            focusedPane = pane.id
            save()
            return
        }
        let anchor = session.flatMap { id in panes.firstIndex { $0.session == id } }
            ?? panes.firstIndex { $0.id == focusedPane } ?? 0
        if panes[anchor].content == .home {
            panes[anchor].content = content
            focusedPane = panes[anchor].id
        } else if panes.count < 4 {
            if panes.count == 1 { axis = .horizontal }
            let pane = Pane(content: content)
            panes.insert(pane, at: anchor + 1)
            focusedPane = pane.id
        } else {
            let index = panes.lastIndex { $0.content.isTool } ?? panes.count - 1
            panes[index].content = content
            focusedPane = panes[index].id
        }
        save()
    }

    /// Opens a file or folder path: folders get a new shell, files the editor or a viewer.
    func open(path: String, besideSession session: UUID? = nil) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return }
        if isDirectory.boolValue {
            newSession(cwd: path)
        } else {
            open(.file((path as NSString).standardizingPath), besideSession: session)
        }
    }

    /// A new browser tab beside the focused pane, with its address field focused (⌘L).
    func newBrowserTab(url: URL? = nil) {
        if let pane = panes.first(where: { $0.id == focusedPane }), case .browser = pane.content, url == nil {
            NotificationCenter.default.post(name: .focusAddressBar, object: pane.id)
            return
        }
        let tab = BrowserStore.shared.newTab(url: url)
        open(.browser(tab.id), besideSession: focusedSessionID)
    }

    /// The live diff for the focused session's repository.
    func showChanges() {
        guard let id = focusedSessionID ?? client.sessions.first?.id else { return }
        open(.changes(id), besideSession: id)
    }

    /// Asks for a file to open (⌘O).
    func chooseFileToOpen() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if let cwd = focusedSession?.cwd { panel.directoryURL = URL(fileURLWithPath: cwd) }
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { open(path: url.path, besideSession: focusedSessionID) }
    }

    /// Shows Home (⇧⌘H): focuses a pane that already shows it, otherwise the focused pane turns
    /// into Home. Its session keeps running and stays in the sidebar.
    func showHome() {
        if let pane = panes.first(where: { $0.content == .home }) {
            focusedPane = pane.id
        } else if let index = panes.firstIndex(where: { $0.id == focusedPane }) {
            panes[index].content = .home
        }
        save()
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
        RecentFolders.note(directory)
        client.create(spec) { [weak self] info in
            guard let self else { return }
            if let axis = inNewPane {
                self.axis = axis
                let pane = Pane(content: .session(info.id))
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
        guard let index = panes.firstIndex(where: { $0.id == focusedPane }) else { return }
        if panes.count == 1 {
            // A lone tool pane goes back to the last session, or Home.
            guard panes[0].content.isTool else { return }
            if case .browser(let id) = panes[0].content { BrowserStore.shared.close(id) }
            panes[0].content = client.sessions.first.map { .session($0.id) } ?? .home
            save()
            focusTerminalSoon()
            return
        }
        let removed = panes.remove(at: index)
        if case .browser(let id) = removed.content { BrowserStore.shared.close(id) }
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
        // A pane whose session ended shows the next session that isn't on screen. With none
        // left, the pane closes, or the last pane turns into Home.
        var changed = false
        for index in panes.indices.reversed() {
            if case .changes(let id) = panes[index].content, !ids.contains(id) {
                if panes.count > 1 { panes.remove(at: index) } else { panes[index].content = .home }
                changed = true
                continue
            }
            guard let id = panes[index].session, !ids.contains(id) else { continue }
            let shown = Set(panes.compactMap(\.session))
            if let next = sessions.first(where: { !shown.contains($0.id) }) {
                panes[index].content = .session(next.id)
            } else if panes.count > 1 {
                panes.remove(at: index)
            } else {
                panes[index].content = .home
            }
            changed = true
        }
        if !panes.contains(where: { $0.id == focusedPane }) {
            focusedPane = panes[0].id
            changed = true
        }
        if let cwd = focusedSession?.cwd { RecentFolders.note(cwd) }
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
            AppDefaults.store.set(data, forKey: Self.layoutKey)
        }
    }

    private func restore(valid ids: Set<UUID>) {
        let defaults = AppDefaults.store
        guard !PreferencesStore.shared.value.openHomeOnLaunch,
              let data = defaults.data(forKey: Self.layoutKey) ?? defaults.data(forKey: Self.legacyLayoutKey),
              let saved = try? JSONDecoder().decode(SavedLayout.self, from: data) else { return }
        let kept = Self.validPanes(saved.panes, sessions: ids, tabs: BrowserStore.shared.tabIDs)
        guard !kept.isEmpty else { return }
        panes = kept
        axis = saved.axis
        focusedPane = kept[min(saved.focusedIndex, kept.count - 1)].id
    }

    /// The saved panes that can still be shown: Home, live sessions, files that exist, browser
    /// tabs that were restored, and changes for live sessions.
    static func validPanes(_ panes: [Pane], sessions ids: Set<UUID>, tabs: Set<UUID> = [],
                           fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [Pane] {
        panes.filter { pane in
            switch pane.content {
            case .home: return true
            case .session(let id), .changes(let id): return ids.contains(id)
            case .file(let path): return fileExists(path)
            case .browser(let id): return tabs.contains(id)
            }
        }
    }
}

/// What a pane shows.
enum PaneContent: Codable, Equatable, Hashable {
    case home
    case session(UUID)
    /// A file in the editor or a viewer (absolute path).
    case file(String)
    /// A browser tab (`BrowserStore`).
    case browser(UUID)
    /// The live diff of a session's repository.
    case changes(UUID)

    var sessionID: UUID? {
        if case .session(let id) = self { return id }
        return nil
    }

    /// Tools are everything that isn't Home or a terminal.
    var isTool: Bool {
        switch self {
        case .home, .session: return false
        case .file, .browser, .changes: return true
        }
    }
}

/// The folders you've worked in lately, newest first, for Home.
enum RecentFolders {
    private static let key = "tethera.recentFolders"
    static let limit = 8

    static var all: [String] {
        AppDefaults.store.stringArray(forKey: key) ?? []
    }

    @MainActor
    static func note(_ path: String) {
        let updated = adding(path, to: all)
        if updated != all { AppDefaults.store.set(updated, forKey: key) }
    }

    /// Moves `path` to the front. Home and the filesystem root aren't worth listing.
    static func adding(_ path: String, to list: [String], home: String = NSHomeDirectory()) -> [String] {
        let trimmed = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        guard !trimmed.isEmpty, trimmed != "/", trimmed != home else { return list }
        return Array(([trimmed] + list.filter { $0 != trimmed }).prefix(limit))
    }
}
