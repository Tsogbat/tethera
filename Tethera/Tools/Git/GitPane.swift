import AppKit
import SwiftUI

/// Everyday git for a repository: branches, commit, sync, stashes and the history graph.
@MainActor
final class GitPaneModel: ObservableObject {
    struct Branch: Identifiable, Equatable {
        let name: String
        let isCurrent: Bool
        let upstream: String?
        let track: String
        var id: String { name }
    }

    struct Stash: Identifiable, Equatable {
        let ref: String
        let message: String
        var id: String { ref }
    }

    let root: String
    @Published private(set) var status: GitStatus?
    @Published private(set) var branches: [Branch] = []
    @Published private(set) var stashes: [Stash] = []
    @Published private(set) var graph: [String] = []
    @Published private(set) var busy: String?
    @Published var message = ""
    @Published var error: String?

    init(root: String) { self.root = root }

    func refresh() async {
        status = await GitService.status(for: root)
        let refs = await GitService.run(["for-each-ref", "--sort=-committerdate", "--format=%(HEAD)\t%(refname:short)\t%(upstream:short)\t%(upstream:track)", "refs/heads"], in: root)
        branches = refs.output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 4 else { return nil }
            return Branch(name: parts[1], isCurrent: parts[0] == "*", upstream: parts[2].isEmpty ? nil : parts[2], track: parts[3])
        }
        let stashList = await GitService.run(["stash", "list", "--format=%gd\t%s"], in: root)
        stashes = stashList.output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            return parts.count == 2 ? Stash(ref: parts[0], message: parts[1]) : nil
        }
        let log = await GitService.run(["log", "--graph", "--all", "-200", "--date=relative", "--format=%h  %s  ·  %an, %ad%d"], in: root)
        graph = log.output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// Runs a git command, shows it as busy, reports failures, refreshes.
    func run(_ label: String, _ arguments: [String]) async {
        busy = label
        error = nil
        let result = await GitService.run(arguments, in: root)
        busy = nil
        if !result.ok { error = result.output.trimmingCharacters(in: .whitespacesAndNewlines) }
        await refresh()
    }

    func commit(all: Bool) async {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { error = "Write a commit message first."; return }
        if all { await run("Staging", ["add", "-A"]) }
        await run("Committing", ["commit", "-m", text])
        if error == nil { message = "" }
    }
}

struct GitPane: View {
    let root: String
    let paneID: UUID
    @StateObject private var model: GitPaneModel
    @Environment(\.theme) private var theme
    @State private var newBranch = ""

    init(root: String, paneID: UUID) {
        self.root = root
        self.paneID = paneID
        _model = StateObject(wrappedValue: GitPaneModel(root: root))
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(paneID: paneID, icon: "arrow.triangle.branch", title: "Git",
                       detail: (root as NSString).lastPathComponent + (model.status.map { " · \($0.info.branch)" } ?? "")) {
                if let busy = model.busy {
                    Text(busy + "…").font(TypeScale.ui(11)).foregroundStyle(theme.text3.color)
                }
                syncButton("Fetch", "arrow.down.circle", ["fetch", "--all", "--prune"])
                syncButton("Pull", "arrow.down", ["pull", "--ff-only"])
                syncButton("Push", "arrow.up", ["push"])
                IconButton(systemName: "arrow.clockwise", help: "Refresh") { Task { await model.refresh() } }
            }
            if let error = model.error {
                Text(error)
                    .font(TypeScale.mono(11)).foregroundStyle(theme.danger.color)
                    .textSelection(.enabled)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.raised.color)
            }
            HSplitView {
                sidebar.frame(minWidth: 220, idealWidth: 260, maxWidth: 340)
                history.frame(minWidth: 300)
            }
        }
        .background(theme.bg.color)
        .task { await model.refresh() }
    }

    private func syncButton(_ title: String, _ icon: String, _ arguments: [String]) -> some View {
        Button { Task { await model.run(title + "ing", arguments) } } label: {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 10, weight: .medium))
                Text(title).font(TypeScale.ui(11.5, .medium))
            }
            .foregroundStyle(theme.text.color)
        }
        .buttonStyle(.plain)
        .disabled(model.busy != nil)
        .padding(.horizontal, 4)
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                commitBox
                SectionLabel(text: "Branches").padding(.top, 18).padding(.bottom, 6)
                ForEach(model.branches) { branch in
                    HStack(spacing: 7) {
                        Circle().fill(branch.isCurrent ? theme.accent.color : .clear)
                            .overlay(Circle().strokeBorder(theme.text3.color, lineWidth: branch.isCurrent ? 0 : 1))
                            .frame(width: 6, height: 6)
                        Text(branch.name).font(TypeScale.mono(11.5, branch.isCurrent ? .semibold : .regular))
                            .foregroundStyle(theme.text.color).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(branch.track.replacingOccurrences(of: "ahead ", with: "↑").replacingOccurrences(of: "behind ", with: "↓")
                            .trimmingCharacters(in: CharacterSet(charactersIn: "[]")))
                            .font(TypeScale.mono(10)).foregroundStyle(theme.text3.color)
                    }
                    .frame(height: 26)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { if !branch.isCurrent { Task { await model.run("Switching", ["switch", branch.name]) } } }
                    .contextMenu {
                        if !branch.isCurrent {
                            Button("Switch to \(branch.name)") { Task { await model.run("Switching", ["switch", branch.name]) } }
                            Button("Merge into Current Branch") { Task { await model.run("Merging", ["merge", "--no-edit", branch.name]) } }
                            Divider()
                            Button("Delete Branch", role: .destructive) { Task { await model.run("Deleting", ["branch", "-d", branch.name]) } }
                        }
                    }
                }
                HStack(spacing: 6) {
                    TextField("New branch", text: $newBranch)
                        .textFieldStyle(.plain).font(TypeScale.mono(11.5))
                        .onSubmit(createBranch)
                    Button("Create", action: createBranch).buttonStyle(.plain).font(TypeScale.ui(11.5, .medium))
                        .disabled(newBranch.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 8).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: Metrics.controlRadius).strokeBorder(theme.hairline.color))
                .padding(.top, 6)

                HStack {
                    SectionLabel(text: "Stashes")
                    Spacer()
                    Button("Stash Changes") { Task { await model.run("Stashing", ["stash", "push", "--include-untracked"]) } }
                        .buttonStyle(.plain).font(TypeScale.ui(11, .medium)).foregroundStyle(theme.text2.color)
                }
                .padding(.top, 18).padding(.bottom, 6)
                if model.stashes.isEmpty {
                    Text("No stashes.").font(TypeScale.ui(11.5)).foregroundStyle(theme.text3.color)
                }
                ForEach(model.stashes) { stash in
                    HStack {
                        Text(stash.message).font(TypeScale.ui(11.5)).foregroundStyle(theme.text.color).lineLimit(1)
                        Spacer()
                        Button("Pop") { Task { await model.run("Popping", ["stash", "pop", stash.ref]) } }
                            .buttonStyle(.plain).font(TypeScale.ui(11, .medium))
                    }
                    .frame(height: 24)
                    .contextMenu {
                        Button("Apply") { Task { await model.run("Applying", ["stash", "apply", stash.ref]) } }
                        Button("Drop", role: .destructive) { Task { await model.run("Dropping", ["stash", "drop", stash.ref]) } }
                    }
                }
            }
            .padding(14)
        }
        .background(theme.surface.color)
    }

    private var commitBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: changesLabel)
            TextField("Commit message", text: $model.message, axis: .vertical)
                .textFieldStyle(.plain)
                .font(TypeScale.ui(12.5))
                .lineLimit(2...5)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: Metrics.controlRadius).fill(theme.bg.color))
                .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius).strokeBorder(theme.hairline.color))
            HStack(spacing: 8) {
                Button("Commit All") { Task { await model.commit(all: true) } }
                    .buttonStyle(.plain).font(TypeScale.ui(12, .semibold))
                    .foregroundStyle(theme.bg.color)
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: Metrics.controlRadius).fill(theme.text.color))
                Button("Commit Staged") { Task { await model.commit(all: false) } }
                    .buttonStyle(.plain).font(TypeScale.ui(12, .medium)).foregroundStyle(theme.text.color)
            }
            .disabled(model.busy != nil || (model.status?.files.isEmpty ?? true))
            .opacity((model.status?.files.isEmpty ?? true) ? 0.45 : 1)
        }
    }

    private var changesLabel: String {
        let count = model.status?.files.count ?? 0
        return count == 0 ? "No changes" : (count == 1 ? "1 change" : "\(count) changes")
    }

    private func createBranch() {
        let name = newBranch.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        newBranch = ""
        Task { await model.run("Creating", ["switch", "-c", name]) }
    }

    /// `git log --graph`, as git draws it, in the terminal font: lanes stay exact.
    private var history: some View {
        MonoText(text: historyText, key: "\(model.graph.hashValue)")
    }

    private var historyText: NSAttributedString {
        let font = PreferencesStore.shared.terminalFont
        let regular = NSFont(descriptor: font.fontDescriptor, size: max(10, font.pointSize - 1.5)) ?? font
        let output = NSMutableAttributedString()
        for line in model.graph {
            let graphEnd = line.firstIndex { !"*|/\\_ .-".contains($0) } ?? line.endIndex
            output.append(NSAttributedString(string: String(line[..<graphEnd]), attributes: [.font: regular, .foregroundColor: theme.text3.nsColor]))
            let rest = String(line[graphEnd...])
            if let space = rest.firstIndex(of: " ") {
                output.append(NSAttributedString(string: String(rest[..<space]), attributes: [.font: regular, .foregroundColor: theme.text2.nsColor]))
                output.append(NSAttributedString(string: String(rest[space...]), attributes: [.font: regular, .foregroundColor: theme.text.nsColor]))
            } else {
                output.append(NSAttributedString(string: rest, attributes: [.font: regular, .foregroundColor: theme.text.nsColor]))
            }
            output.append(NSAttributedString(string: "\n"))
        }
        return output
    }
}
