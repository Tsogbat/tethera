import SwiftUI
import TetheraKit

/// The shared agent board: every team member's agents, live from the team repository.
struct BoardPane: View {
    let paneID: UUID
    @ObservedObject private var team = TeamSync.shared
    @Environment(\.theme) private var theme
    @State private var state = "all"
    @State private var repo: String?
    @State private var agent: String?

    private var rows: [(member: MemberStatus, session: MemberStatus.Session)] {
        var result: [(member: MemberStatus, session: MemberStatus.Session)] = []
        for member in team.members {
            for session in member.sessions where matches(session) { result.append((member, session)) }
        }
        return result.sorted { a, b in
            let left = rank(a.session.state), right = rank(b.session.state)
            return left != right ? left < right : a.member.login < b.member.login
        }
    }

    private func matches(_ session: MemberStatus.Session) -> Bool {
        let stateMatches = state == "all" || session.state == state || (state == "working" && session.state == "idle")
        return stateMatches && (repo == nil || session.repo == repo) && (agent == nil || session.agent == agent)
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(paneID: paneID, icon: "person.3", title: "Team", detail: detail) {
                if team.repository != nil {
                    IconButton(systemName: "arrow.clockwise", help: "Refresh") { Task { await team.sync(force: true) } }
                        .disabled(team.syncing)
                }
            }
            if team.repository == nil {
                VStack(spacing: 8) {
                    Text("No team yet.").font(TypeScale.ui(13, .medium)).foregroundStyle(theme.text2.color)
                    Text("A team is a private GitHub repository. Join one in Settings → Team to see everyone's agents here.")
                        .font(TypeScale.ui(12)).foregroundStyle(theme.text3.color).multilineTextAlignment(.center)
                    Button("Open Settings") { SettingsOpener.open() }.padding(.top, 4)
                }
                .frame(maxWidth: 360)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                filters
                if let problem = team.problem {
                    Text(problem).font(TypeScale.ui(12)).foregroundStyle(theme.danger.color)
                        .padding(.horizontal, 20).padding(.top, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ScrollView {
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                BoardRow(member: row.member, session: row.session, now: context.date)
                            }
                            if rows.isEmpty {
                                Text(team.members.isEmpty ? "Nobody has shared yet. Each member appears once their Tethera syncs." : "No agents match.")
                                    .font(TypeScale.ui(12.5)).foregroundStyle(theme.text3.color).padding(.vertical, 24)
                            }
                            ForEach(team.members.filter { $0.sessions.isEmpty }, id: \.login) { member in
                                Text("\(member.login) · no agents running")
                                    .font(TypeScale.ui(12)).foregroundStyle(theme.text3.color)
                                    .frame(height: 30)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
            }
        }
        .background(theme.bg.color)
        .onAppear {
            team.boardVisible = true
            Task { await team.sync(force: true) }
        }
        .onDisappear { team.boardVisible = false }
    }

    private var detail: String? {
        guard let repository = team.repository else { return nil }
        let people = team.members.count
        return "\(repository) · \(people) \(people == 1 ? "member" : "members")"
    }

    private var filters: some View {
        let repos = Set(team.members.flatMap { $0.sessions.map(\.repo) }).sorted()
        let agents = Set(team.members.flatMap { $0.sessions.map(\.agent) }).sorted()
        return HStack(spacing: 10) {
            Segments(options: [("all", "All"), ("needsInput", "Needs someone"), ("working", "Working"), ("done", "Done")], selection: $state)
            Menu(repo ?? "Any repository") {
                Button("Any repository") { repo = nil }
                ForEach(repos, id: \.self) { name in Button(name) { repo = name } }
            }
            .menuStyle(.borderlessButton).fixedSize()
            Menu(agent.flatMap { AgentKind(rawValue: $0)?.displayName } ?? "Any agent") {
                Button("Any agent") { agent = nil }
                ForEach(agents, id: \.self) { name in Button(AgentKind(rawValue: name)?.displayName ?? name) { agent = name } }
            }
            .menuStyle(.borderlessButton).fixedSize()
            Spacer()
            if let last = team.lastSync {
                Text("Updated \(last.formatted(.relative(presentation: .numeric)))")
                    .font(TypeScale.ui(11)).foregroundStyle(theme.text3.color)
            }
        }
        .font(TypeScale.ui(12))
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func rank(_ state: String) -> Int {
        AgentState(rawValue: state)?.attentionRank ?? 9
    }
}

private struct BoardRow: View {
    let member: MemberStatus
    let session: MemberStatus.Session
    let now: Date
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            StateMark(state: AgentState(rawValue: session.state) ?? .idle)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name).font(TypeScale.ui(13, .semibold)).foregroundStyle(theme.text.color).lineLimit(1)
                Text("\(AgentKind(rawValue: session.agent)?.displayName ?? session.agent) · \(label) · \(session.repo)")
                    .font(TypeScale.ui(12)).foregroundStyle(session.state == "needsInput" ? theme.text.color : theme.text2.color).lineLimit(1)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(member.login).font(TypeScale.ui(12.5, .medium)).foregroundStyle(theme.text.color)
                Text([member.mac, Self.ago(session.since, now)].joined(separator: " · "))
                    .font(TypeScale.ui(11)).foregroundStyle(theme.text3.color)
            }
            Text(session.costUSD.map { String(format: "$%.2f", $0) } ?? "")
                .font(TypeScale.ui(12)).monospacedDigit().foregroundStyle(theme.text2.color)
                .frame(width: 58, alignment: .trailing)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline.color).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        switch session.state {
        case "needsInput": return "needs someone"
        case "working": return "working"
        case "done": return "done"
        case "error": return "error"
        default: return "waiting"
        }
    }

    static func ago(_ date: Date, _ now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86_400))d"
    }
}

/// An agent state as the sidebar draws it, in ink: a ring waiting, a filled dot when it needs
/// someone, a check when done, a cross on error, a spinner while working.
struct StateMark: View {
    let state: AgentState
    @Environment(\.theme) private var theme

    var body: some View {
        switch state {
        case .needsInput: Circle().fill(theme.accent.color).frame(width: 8, height: 8)
        case .working: ProgressView().controlSize(.mini).scaleEffect(0.8)
        case .done: Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.text2.color)
        case .error: Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.danger.color)
        case .idle: Circle().strokeBorder(theme.text3.color, lineWidth: 1.5).frame(width: 8, height: 8)
        }
    }
}
