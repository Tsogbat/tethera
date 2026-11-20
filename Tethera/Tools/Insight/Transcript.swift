import AppKit
import Foundation
import SwiftUI
import TetheraKit

/// One step an agent took: your prompt, its reply, a tool call, or the tool's result.
struct TranscriptStep: Identifiable, Equatable {
    enum Kind: String { case prompt, reply, tool, result, error }

    let id: Int
    let kind: Kind
    let title: String
    let text: String
    var tool: String?
    /// For edits: the text replaced and its replacement (or the whole file for a write).
    var before: String?
    var after: String?
    var file: String?
    var inputTokens = 0
    var outputTokens = 0
    var time: Date?

    var isEdit: Bool { after != nil }
}

/// Reads Claude Code and Codex session logs into steps. Both formats are internal to their
/// agents and change between versions, so anything unrecognized is skipped, never fatal.
enum TranscriptParser {
    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        return iso.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    static func text(_ content: Any?) -> String {
        if let string = content as? String { return string }
        if let items = content as? [[String: Any]] {
            return items.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return ""
    }

    static func json(_ value: Any?) -> String {
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
            return value.map { "\($0)" } ?? ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// A one-line title for a tool call: the command, file or URL it's about.
    static func toolTitle(_ name: String, _ input: [String: Any]) -> String {
        for key in ["command", "file_path", "path", "pattern", "url", "query", "description"] {
            if let value = input[key] as? String, !value.isEmpty {
                let short = key.contains("path") ? (value as NSString).lastPathComponent : value
                return "\(name)  \(short.replacingOccurrences(of: "\n", with: " "))"
            }
        }
        return name
    }

    /// Parses complete JSONL lines into steps, numbering from `firstID`.
    static func parse(lines: [Data], firstID: Int) -> [TranscriptStep] {
        var steps: [TranscriptStep] = []
        var next = firstID
        func add(_ step: TranscriptStep) {
            steps.append(step)
            next += 1
        }
        for line in lines {
            guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            let time = date(object["timestamp"])
            let type = object["type"] as? String ?? ""

            // Claude Code
            if type == "user" || type == "assistant", let message = object["message"] as? [String: Any] {
                let usage = message["usage"] as? [String: Any]
                let input = (usage?["input_tokens"] as? Int ?? 0) + (usage?["cache_read_input_tokens"] as? Int ?? 0)
                    + (usage?["cache_creation_input_tokens"] as? Int ?? 0)
                let output = usage?["output_tokens"] as? Int ?? 0
                var tokensGiven = false
                func tokens(_ step: inout TranscriptStep) {
                    guard !tokensGiven else { return }
                    step.inputTokens = input
                    step.outputTokens = output
                    tokensGiven = true
                }
                if let string = message["content"] as? String {
                    guard type == "user", !string.isEmpty, !string.hasPrefix("<") else { continue }
                    add(TranscriptStep(id: next, kind: .prompt, title: string, text: string, time: time))
                    continue
                }
                for item in message["content"] as? [[String: Any]] ?? [] {
                    switch item["type"] as? String {
                    case "text":
                        let body = item["text"] as? String ?? ""
                        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !body.hasPrefix("<") else { continue }
                        var step = TranscriptStep(id: next, kind: type == "user" ? .prompt : .reply, title: body, text: body, time: time)
                        tokens(&step)
                        add(step)
                    case "tool_use":
                        let name = item["name"] as? String ?? "tool"
                        let toolInput = item["input"] as? [String: Any] ?? [:]
                        var step = TranscriptStep(id: next, kind: .tool, title: toolTitle(name, toolInput), text: json(toolInput), tool: name, time: time)
                        if let file = toolInput["file_path"] as? String {
                            step.file = file
                            if let old = toolInput["old_string"] as? String, let new = toolInput["new_string"] as? String {
                                step.before = old
                                step.after = new
                            } else if let content = toolInput["content"] as? String, name == "Write" {
                                step.before = ""
                                step.after = content
                            }
                        }
                        tokens(&step)
                        add(step)
                    case "tool_result":
                        let body = text(item["content"])
                        let failed = item["is_error"] as? Bool ?? false
                        let first = body.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? (failed ? "Error" : "Done")
                        add(TranscriptStep(id: next, kind: failed ? .error : .result, title: first, text: body, time: time))
                    default:
                        continue
                    }
                }
                continue
            }

            // Codex
            if type == "response_item", let payload = object["payload"] as? [String: Any] {
                switch payload["type"] as? String {
                case "message":
                    let body = text(payload["content"])
                    guard !body.isEmpty, !body.hasPrefix("<") else { continue }
                    let role = payload["role"] as? String
                    guard role == "user" || role == "assistant" else { continue }
                    add(TranscriptStep(id: next, kind: role == "user" ? .prompt : .reply, title: body, text: body, time: time))
                case "function_call", "custom_tool_call", "local_shell_call":
                    let name = payload["name"] as? String ?? "tool"
                    let raw = payload["arguments"] as? String ?? payload["input"] as? String ?? json(payload["action"])
                    let parsed = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
                    add(TranscriptStep(id: next, kind: .tool, title: parsed.map { toolTitle(name, $0) } ?? "\(name)  \(raw.prefix(80))",
                                       text: parsed.map { json($0) } ?? raw, tool: name, time: time))
                case "function_call_output", "custom_tool_call_output":
                    let output = payload["output"]
                    let body = (output as? String) ?? text((output as? [String: Any])?["content"])
                    let first = body.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? "Done"
                    let failed = body.lowercased().contains("exit code: 1") || body.lowercased().hasPrefix("error")
                    add(TranscriptStep(id: next, kind: failed ? .error : .result, title: first, text: body, time: time))
                default:
                    continue
                }
                continue
            }
            if type == "token_usage_record", let usage = (object["payload"] as? [String: Any])?["usage"] as? [String: Any], !steps.isEmpty {
                steps[steps.count - 1].inputTokens += usage["input_tokens"] as? Int ?? 0
                steps[steps.count - 1].outputTokens += usage["output_tokens"] as? Int ?? 0
            }
        }
        return steps
    }

    // MARK: Finding the log

    /// Claude names a project's folder after its path, every non-alphanumeric turned into "-".
    static func claudeProjectFolder(for cwd: String) -> String {
        String(cwd.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    /// The newest log of the agent running in `cwd`.
    /// `home` is where the agents keep their data: your home folder, or `TETHERA_CONFIG_HOME`.
    static func locate(agent: AgentKind?, cwd: String, home: URL = AgentIntegrations.configHome) -> URL? {
        let fm = FileManager.default
        func newest(_ urls: [URL]) -> URL? {
            urls.max { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da < db
            }
        }
        if agent != .codex {
            let folder = home.appendingPathComponent(".claude/projects").appendingPathComponent(claudeProjectFolder(for: cwd))
            let logs = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]))?
                .filter { $0.pathExtension == "jsonl" } ?? []
            if let log = newest(logs) { return log }
        }
        if agent == .codex || agent == nil {
            // ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl; the first line names the folder it ran in.
            var day = Date()
            for _ in 0..<7 {
                let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
                let folder = home.appendingPathComponent(String(format: ".codex/sessions/%04d/%02d/%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0))
                let logs = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]))?
                    .filter { $0.pathExtension == "jsonl" }
                    .sorted { ($0.lastPathComponent) > ($1.lastPathComponent) } ?? []
                for log in logs {
                    guard let handle = try? FileHandle(forReadingFrom: log) else { continue }
                    let head = (try? handle.read(upToCount: 65_536)) ?? Data()
                    try? handle.close()
                    if let first = head.split(separator: 0x0A).first,
                       let object = (try? JSONSerialization.jsonObject(with: first)) as? [String: Any],
                       ((object["payload"] as? [String: Any])?["cwd"] as? String) == cwd {
                        return log
                    }
                }
                day = day.addingTimeInterval(-86_400)
            }
        }
        return nil
    }
}

/// A session's transcript, kept current while it's open.
@MainActor
final class TranscriptModel: ObservableObject {
    @Published private(set) var steps: [TranscriptStep] = []
    @Published private(set) var file: URL?
    @Published var selected: Int?
    private var offset: UInt64 = 0
    private var carry = Data()
    private var watcher: DispatchSourceFileSystemObject?

    func load(agent: AgentKind?, cwd: String) {
        guard file == nil else { return }
        file = TranscriptParser.locate(agent: agent, cwd: cwd)
        readMore()
        watch()
        selected = steps.last?.id
    }

    private func readMore() {
        guard let file, let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        offset += UInt64(data.count)
        var buffer = carry + data
        // Keep a partial last line for the next read.
        if let lastNewline = buffer.lastIndex(of: 0x0A) {
            carry = buffer[(lastNewline + 1)...]
            buffer = buffer[..<lastNewline]
        } else {
            carry = buffer
            return
        }
        let lines = buffer.split(separator: 0x0A).map { Data($0) }
        let added = TranscriptParser.parse(lines: lines, firstID: steps.count)
        if !added.isEmpty { steps.append(contentsOf: added) }
    }

    private func watch() {
        guard let file else { return }
        let fd = open(file.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend], queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.readMore() } }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
    }

    var totals: (input: Int, output: Int, tools: Int, errors: Int) {
        steps.reduce((0, 0, 0, 0)) { sum, step in
            (sum.0 + step.inputTokens, sum.1 + step.outputTokens, sum.2 + (step.kind == .tool ? 1 : 0), sum.3 + (step.kind == .error ? 1 : 0))
        }
    }
}

/// The transcript pane: every step on the left, the selected one on the right.
struct TranscriptPane: View {
    let sessionID: UUID
    let paneID: UUID
    @ObservedObject private var client = DaemonClient.shared
    @StateObject private var model = TranscriptModel()
    @Environment(\.theme) private var theme
    @State private var filter = Filter.all

    enum Filter: String, CaseIterable { case all = "All", tools = "Tools", edits = "Edits", errors = "Errors" }

    private var visible: [TranscriptStep] {
        switch filter {
        case .all: return model.steps
        case .tools: return model.steps.filter { $0.kind == .tool }
        case .edits: return model.steps.filter(\.isEdit)
        case .errors: return model.steps.filter { $0.kind == .error }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(paneID: paneID, icon: "list.bullet.rectangle", title: "Transcript", detail: header) {
                Segments(options: Filter.allCases.map { ($0, $0.rawValue) }, selection: $filter)
                if let file = model.file {
                    IconButton(systemName: "doc.text.magnifyingglass", help: "Open the raw log") {
                        Workspace.shared.open(.file(file.path), besideSession: sessionID)
                    }
                }
            }
            if model.file == nil {
                VStack(spacing: 6) {
                    Text("No transcript found.").font(TypeScale.ui(13, .medium)).foregroundStyle(theme.text2.color)
                    Text("Transcripts come from Claude Code and Codex sessions started in this folder.")
                        .font(TypeScale.ui(12)).foregroundStyle(theme.text3.color)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    list.frame(minWidth: 240, idealWidth: 320, maxWidth: 460)
                    detail.frame(minWidth: 300)
                }
            }
        }
        .background(theme.bg.color)
        .onAppear {
            if let session = client.session(sessionID) { model.load(agent: session.agent?.kind, cwd: session.cwd) }
        }
        .onDisappear { model.stop() }
    }

    private var header: String {
        guard model.file != nil else { return "" }
        let totals = model.totals
        var parts = ["\(model.steps.count) steps", "\(totals.tools) tool calls"]
        if totals.errors > 0 { parts.append(totals.errors == 1 ? "1 error" : "\(totals.errors) errors") }
        if totals.input + totals.output > 0 { parts.append("\(Self.compact(totals.input)) in · \(Self.compact(totals.output)) out") }
        if let cost = client.session(sessionID)?.agent?.costUSD { parts.append(String(format: "$%.2f", cost)) }
        return parts.joined(separator: " · ")
    }

    static func compact(_ tokens: Int) -> String {
        tokens >= 1_000_000 ? String(format: "%.1fM", Double(tokens) / 1e6) : (tokens >= 1000 ? String(format: "%.1fk", Double(tokens) / 1e3) : "\(tokens)")
    }

    private var list: some View {
        ScrollViewReader { proxy in
            List(selection: $model.selected) {
                ForEach(visible) { step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: icon(step))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(step.kind == .error ? theme.danger.color : (step.kind == .prompt ? theme.text.color : theme.text3.color))
                            .frame(width: 14)
                        Text(step.title)
                            .font(step.kind == .tool ? TypeScale.mono(11.5) : TypeScale.ui(12.5, step.kind == .prompt ? .semibold : .regular))
                            .foregroundStyle(step.kind == .error ? theme.danger.color : theme.text.color)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        if step.outputTokens > 0 {
                            Text(Self.compact(step.outputTokens)).font(TypeScale.mono(10)).foregroundStyle(theme.text3.color)
                        }
                    }
                    .padding(.vertical, 3)
                    .tag(step.id)
                    .id(step.id)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(theme.surface.color)
            .onChange(of: model.steps.count) { _, _ in
                // Follow the live end unless you've picked an older step.
                if let last = visible.last, model.selected == nil || model.selected == visible.dropLast().last?.id {
                    model.selected = last.id
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func icon(_ step: TranscriptStep) -> String {
        switch step.kind {
        case .prompt: return "person"
        case .reply: return "text.bubble"
        case .tool: return step.isEdit ? "pencil" : (step.tool == "Bash" || step.tool == "shell" ? "terminal" : "wrench.and.screwdriver")
        case .result: return "arrow.turn.down.right"
        case .error: return "exclamationmark.triangle"
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let step = model.steps.first(where: { $0.id == model.selected }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(step.kind.rawValue.capitalized).font(TypeScale.ui(11, .semibold)).foregroundStyle(theme.text3.color)
                    if let file = step.file {
                        Button((file as NSString).lastPathComponent) { Workspace.shared.open(path: file, besideSession: sessionID) }
                            .buttonStyle(.plain).font(TypeScale.mono(11.5, .medium)).foregroundStyle(theme.text.color)
                    }
                    Spacer()
                    if let time = step.time {
                        Text(time.formatted(date: .omitted, time: .standard)).font(TypeScale.mono(10.5)).foregroundStyle(theme.text3.color)
                    }
                    if step.inputTokens + step.outputTokens > 0 {
                        Text("\(Self.compact(step.inputTokens)) in · \(Self.compact(step.outputTokens)) out")
                            .font(TypeScale.mono(10.5)).foregroundStyle(theme.text3.color)
                    }
                }
                .padding(.horizontal, 14).frame(height: 30)
                .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline.color).frame(height: 1) }
                if let before = step.before, let after = step.after {
                    DiffText(diff: Self.diff(before, after, file: step.file ?? "file"))
                } else {
                    MonoText(text: NSAttributedString(string: step.text, attributes: [
                        .font: NSFont(descriptor: PreferencesStore.shared.terminalFont.fontDescriptor, size: 12) ?? .monospacedSystemFont(ofSize: 12, weight: .regular),
                        .foregroundColor: (step.kind == .error ? theme.danger : theme.text).nsColor,
                    ]), key: "\(step.id)", wraps: true)
                }
            }
        } else {
            Text("Select a step.").font(TypeScale.ui(12)).foregroundStyle(theme.text3.color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// A unified diff of one edit, for the diff view.
    static func diff(_ before: String, _ after: String, file: String) -> String {
        let old = before.isEmpty ? [] : before.components(separatedBy: "\n")
        let new = after.components(separatedBy: "\n")
        var lines = ["--- \((file as NSString).lastPathComponent)", "+++ \((file as NSString).lastPathComponent)", "@@ -1,\(old.count) +1,\(new.count) @@"]
        let difference = new.difference(from: old)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var i = 0, j = 0
        while i < old.count || j < new.count {
            if i < old.count, removed.contains(i) { lines.append("-" + old[i]); i += 1 }
            else if j < new.count, inserted.contains(j) { lines.append("+" + new[j]); j += 1 }
            else { if j < new.count { lines.append(" " + new[j]) }; i += 1; j += 1 }
        }
        return lines.joined(separator: "\n")
    }
}
