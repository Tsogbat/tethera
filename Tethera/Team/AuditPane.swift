import AppKit
import SwiftUI
import TetheraKit

/// The audit log: every approval (who answered, how, when), budget stops, and sessions starting
/// and ending, from the journal on this Mac and, for a team, every member's this month.
struct AuditPane: View {
    let paneID: UUID
    @ObservedObject private var team = TeamSync.shared
    @Environment(\.theme) private var theme
    @State private var scope = "you"
    @State private var kind = "approvals"
    @State private var search = ""
    @State private var entries: [Entry] = []

    struct Entry: Identifiable, Hashable {
        let id = UUID()
        var member: String
        var event: Journal.Event

        static func == (a: Entry, b: Entry) -> Bool { a.id == b.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    private var shown: [Entry] {
        let query = search.lowercased()
        return entries.filter { entry in
            let event = entry.event
            switch kind {
            case "approvals": guard event.kind == .approval else { return false }
            case "budgets": guard event.kind == .budget else { return false }
            case "sessions": guard event.kind == .started || event.kind == .ended else { return false }
            default: break
            }
            guard !query.isEmpty else { return true }
            return [entry.member, event.sessionName, event.agent, event.tool, event.detail, event.decision, event.by, event.repo, event.message]
                .compactMap { $0?.lowercased() }.contains { $0.contains(query) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(paneID: paneID, icon: "list.bullet.rectangle", title: "Audit log", detail: "last 30 days") {
                if team.repository != nil {
                    Segments(options: [("you", "You"), ("team", "Team")], selection: $scope)
                }
                Menu {
                    Button("Export CSV…") { export(csv: true) }
                    Button("Export JSON…") { export(csv: false) }
                } label: {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 11, weight: .medium))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Export")
            }
            HStack(spacing: 10) {
                Segments(options: [("approvals", "Approvals"), ("budgets", "Budgets"), ("sessions", "Sessions"), ("all", "All")], selection: $kind)
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                Spacer()
                Text("\(shown.count) \(shown.count == 1 ? "entry" : "entries")")
                    .font(TypeScale.ui(11)).foregroundStyle(theme.text3.color)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(shown) { entry in AuditRow(entry: entry, showMember: scope == "team") }
                    if shown.isEmpty {
                        Text(entries.isEmpty ? "Nothing recorded yet. Approvals, budget stops and sessions show up here as they happen." : "Nothing matches.")
                            .font(TypeScale.ui(12.5)).foregroundStyle(theme.text3.color).padding(.vertical, 24)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .background(theme.bg.color)
        .task(id: scope) { await load() }
    }

    private func load() async {
        if scope == "team" {
            entries = await team.teamAudit().map { Entry(member: $0.login, event: $0.event) }
        } else {
            let start = Date().addingTimeInterval(-30 * 86_400)
            entries = Journal.shared.events(from: start).reversed().map { Entry(member: team.login ?? "you", event: $0) }
        }
    }

    private func export(csv: Bool) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "tethera-audit-\(JournalFile.dayName(Date())).\(csv ? "csv" : "json")"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = csv ? Self.csv(shown) : Self.json(shown)
        try? data.write(to: url, options: .atomic)
    }

    static func csv(_ entries: [Entry]) -> Data {
        let columns = ["time", "member", "kind", "agent", "session", "tool", "detail", "decision", "by", "repo"]
        func field(_ value: String?) -> String {
            let text = value ?? ""
            return text.contains(where: { ",\"\n".contains($0) }) ? "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : text
        }
        let iso = ISO8601DateFormatter()
        let lines = entries.map { entry -> String in
            let e = entry.event
            return [iso.string(from: e.at), entry.member, e.kind.rawValue, e.agent, e.sessionName, e.tool, e.detail, e.decision, e.by, e.repo]
                .map(field).joined(separator: ",")
        }
        return Data(([columns.joined(separator: ",")] + lines).joined(separator: "\n").utf8 + [0x0A])
    }

    static func json(_ entries: [Entry]) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        struct Exported: Encodable { var member: String; var event: Journal.Event }
        return (try? encoder.encode(entries.map { Exported(member: $0.member, event: $0.event) })) ?? Data()
    }
}

private struct AuditRow: View {
    let entry: AuditPane.Entry
    let showMember: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        let event = entry.event
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(event.at.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                .font(TypeScale.ui(11.5)).monospacedDigit().foregroundStyle(theme.text3.color)
                .frame(width: 104, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(headline).font(TypeScale.ui(12.5, .semibold)).foregroundStyle(event.decision == "deny" ? theme.danger.color : theme.text.color)
                if let detail = event.detail, !detail.isEmpty, event.kind == .approval {
                    Text(detail).font(TypeScale.mono(11.5)).foregroundStyle(theme.text2.color).lineLimit(2).textSelection(.enabled)
                }
                Text(context).font(TypeScale.ui(11.5)).foregroundStyle(theme.text3.color).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline.color).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        let event = entry.event
        switch event.kind {
        case .approval:
            let verb = event.decision == "allow" ? "Allowed" : event.decision == "deny" ? "Denied" : "Sent to the terminal:"
            return "\(verb) \(event.tool ?? "a tool")"
        case .budget: return event.detail == "context" ? "Context limit reached" : String(format: "Daily budget reached ($%.2f)", event.costUSD ?? 0)
        case .started: return "Session started"
        case .ended: return "Session ended"
        case .state: return "\(event.agent ?? "Agent") \(event.state ?? "")"
        case .cost: return String(format: "Cost $%.2f", event.costUSD ?? 0)
        }
    }

    private var context: String {
        let event = entry.event
        let who: String? = event.kind == .approval ? (event.by.map { by in by == "you" ? "by \(showMember ? entry.member : "you")" : "by \(by)" } ?? "by you") : nil
        let repo = event.repo.map { ($0 as NSString).lastPathComponent }
        return [showMember && event.kind != .approval ? entry.member : nil, who, event.agent.flatMap { AgentKind(rawValue: $0)?.displayName ?? $0 },
                event.sessionName, repo == event.sessionName ? nil : repo, event.by?.contains("policy") == true ? event.message : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
