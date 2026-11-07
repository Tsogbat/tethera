import AppKit
import CoreServices
import SwiftUI
import TetheraKit

/// What changed in a session's repository, live: files newest-first (what the agent just
/// touched), and the diff of the selected one.
@MainActor
final class ChangesModel: ObservableObject {
    struct Entry: Identifiable, Equatable {
        let file: GitFile
        let modified: Date
        var id: String { file.path }
    }

    @Published private(set) var root: String?
    @Published private(set) var branch = ""
    @Published private(set) var entries: [Entry] = []
    @Published var selected: String?
    @Published private(set) var diff = ""
    @Published private(set) var stats: (added: Int, removed: Int) = (0, 0)

    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?
    private var cwd = ""

    func start(cwd: String) {
        guard cwd != self.cwd else { return }
        self.cwd = cwd
        Task {
            let top = await GitService.run(["rev-parse", "--show-toplevel"], in: cwd)
            root = top.ok ? top.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil
            if let root { watch(root) }
            await refresh()
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
    }

    func refresh() async {
        guard let root else { return }
        if let status = await GitService.status(for: root) {
            branch = status.info.branch
            let fm = FileManager.default
            entries = status.files.map { file in
                let modified = (try? fm.attributesOfItem(atPath: (root as NSString).appendingPathComponent(file.path)))?[.modificationDate] as? Date
                return Entry(file: file, modified: modified ?? .distantPast)
            }
            .sorted { $0.modified > $1.modified }
        }
        let numstat = await GitService.run(["diff", "HEAD", "--numstat"], in: root)
        var added = 0, removed = 0
        for line in numstat.output.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            if parts.count >= 2 { added += Int(parts[0]) ?? 0; removed += Int(parts[1]) ?? 0 }
        }
        // Untracked files aren't in `git diff`; count their lines as added.
        for entry in entries where entry.file.isUntracked {
            let path = (root as NSString).appendingPathComponent(entry.file.path)
            if let data = FileManager.default.contents(atPath: path), data.count < 1_000_000, !data.contains(0) {
                added += data.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
            }
        }
        stats = (added, removed)
        if selected == nil || !entries.contains(where: { $0.id == selected }) { selected = entries.first?.id }
        await loadDiff()
    }

    func loadDiff() async {
        guard let root, let path = selected, let entry = entries.first(where: { $0.id == path }) else {
            diff = ""
            return
        }
        let result = entry.file.isUntracked
            ? await GitService.run(["diff", "--no-color", "--no-index", "--", "/dev/null", path], in: root)
            : await GitService.run(["diff", "--no-color", "HEAD", "--", path], in: root)
        // `--no-index` exits 1 when files differ; the output is still the diff.
        diff = result.output.isEmpty ? "No changes." : result.output
    }

    func stage(_ entry: Entry) async {
        guard let root else { return }
        _ = await GitService.run(entry.file.isStaged ? ["restore", "--staged", "--", entry.file.path] : ["add", "--", entry.file.path], in: root)
        await refresh()
    }

    func discard(_ entry: Entry) async {
        guard let root else { return }
        if entry.file.isUntracked {
            try? FileManager.default.trashItem(at: URL(fileURLWithPath: (root as NSString).appendingPathComponent(entry.file.path)), resultingItemURL: nil)
        } else {
            _ = await GitService.run(["restore", "--staged", "--worktree", "--source=HEAD", "--", entry.file.path], in: root)
        }
        await refresh()
    }

    // MARK: Watching

    private func watch(_ root: String) {
        stop()
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            // Git's own bookkeeping isn't a change you made; the index is (staging).
            let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            let relevant = list.prefix(count).contains { !$0.contains("/.git/") || $0.hasSuffix("/.git/index") || $0.hasSuffix("/.git/HEAD") }
            guard relevant else { return }
            let model = Unmanaged<ChangesModel>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { model.changed() }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        guard let stream = FSEventStreamCreate(nil, callback, &context, [root] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in Task { await self?.refresh() } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}

struct ChangesPane: View {
    let sessionID: UUID
    let paneID: UUID
    @ObservedObject private var client = DaemonClient.shared
    @StateObject private var model = ChangesModel()
    @Environment(\.theme) private var theme
    @State private var confirmDiscard: ChangesModel.Entry?

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(paneID: paneID, icon: "plusminus", title: "Changes",
                       detail: header) {
                IconButton(systemName: "arrow.clockwise", help: "Refresh") { Task { await model.refresh() } }
            }
            if model.root == nil {
                Text("Not a git repository.")
                    .font(TypeScale.ui(12))
                    .foregroundStyle(theme.text3.color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.entries.isEmpty {
                Text("No changes. Edits show up here as they happen.")
                    .font(TypeScale.ui(12))
                    .foregroundStyle(theme.text3.color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    fileList.frame(minWidth: 180, idealWidth: 240, maxWidth: 360)
                    DiffText(diff: model.diff).frame(minWidth: 240)
                }
            }
        }
        .background(theme.bg.color)
        .onAppear { if let cwd = client.session(sessionID)?.cwd { model.start(cwd: cwd) } }
        .onChange(of: client.session(sessionID)?.cwd) { _, cwd in if let cwd { model.start(cwd: cwd) } }
        .onChange(of: model.selected) { _, _ in Task { await model.loadDiff() } }
        .onDisappear { model.stop() }
        .confirmationDialog("Discard changes to \(confirmDiscard?.file.path ?? "")?", isPresented: Binding(
            get: { confirmDiscard != nil }, set: { if !$0 { confirmDiscard = nil } })) {
            Button("Discard", role: .destructive) {
                if let entry = confirmDiscard { Task { await model.discard(entry) } }
            }
        } message: {
            Text(confirmDiscard?.file.isUntracked == true ? "The file moves to the Trash." : "This can't be undone.")
        }
    }

    private var header: String {
        var parts = [model.branch]
        if !model.entries.isEmpty { parts.append("\(model.entries.count) files  +\(model.stats.added) −\(model.stats.removed)") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var fileList: some View {
        List(selection: $model.selected) {
            ForEach(model.entries) { entry in
                HStack(spacing: 8) {
                    Text(entry.file.letter)
                        .font(TypeScale.mono(10.5, .semibold))
                        .foregroundStyle(entry.file.isStaged ? theme.text.color : theme.text2.color)
                        .frame(width: 12)
                    VStack(alignment: .leading, spacing: 1) {
                        Text((entry.file.path as NSString).lastPathComponent)
                            .font(TypeScale.ui(12, .medium))
                            .foregroundStyle(theme.text.color)
                        let folder = (entry.file.path as NSString).deletingLastPathComponent
                        if !folder.isEmpty {
                            Text(folder).font(TypeScale.ui(10.5)).foregroundStyle(theme.text3.color).lineLimit(1).truncationMode(.head)
                        }
                    }
                    Spacer(minLength: 4)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(Elapsed.short(since: entry.modified, now: context.date))
                            .font(TypeScale.mono(10))
                            .foregroundStyle(theme.text3.color)
                    }
                }
                .tag(entry.id)
                .contextMenu {
                    Button("Open") { open(entry) }
                    Button(entry.file.isStaged ? "Unstage" : "Stage") { Task { await model.stage(entry) } }
                    Divider()
                    Button("Discard Changes…", role: .destructive) { confirmDiscard = entry }
                }
                .onTapGesture(count: 2) { open(entry) }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(theme.surface.color)
    }

    private func open(_ entry: ChangesModel.Entry) {
        guard let root = model.root else { return }
        Workspace.shared.open(.file((root as NSString).appendingPathComponent(entry.file.path)), besideSession: nil)
    }
}
