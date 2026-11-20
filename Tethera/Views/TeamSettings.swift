import AppKit
import SwiftUI
import TetheraKit

/// Settings → Team: join a team repository, see who's in it, leave.
struct TeamSettings: View {
    @ObservedObject private var team = TeamSync.shared
    @State private var repository = ""
    @State private var checking = false
    @State private var checked: Result<String, Error>?

    var body: some View {
        Form {
            if let joined = team.repository {
                Section {
                    LabeledContent("Repository") { Text(joined).textSelection(.enabled) }
                    LabeledContent("You") { Text(team.login ?? "…") }
                    LabeledContent("Last sync") {
                        Text(team.lastSync.map { $0.formatted(.relative(presentation: .named)) } ?? (team.syncing ? "syncing…" : "not yet"))
                    }
                    if let problem = team.problem { Text(problem).foregroundStyle(.red) }
                    ForEach(team.members, id: \.login) { member in
                        LabeledContent(member.login) {
                            Text("\(member.mac) · \(member.sessions.count) \(member.sessions.count == 1 ? "agent" : "agents") · \(member.updated.formatted(.relative(presentation: .named)))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Button("Open Board") { Workspace.shared.showBoard() }
                        Button("Sync Now") { Task { await team.sync(force: true) } }.disabled(team.syncing)
                        Spacer()
                        Button("Leave Team") { team.leave() }
                    }
                } header: {
                    PlanHeader(title: "Team", plan: .team)
                } footer: {
                    Text(sharedNote).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    TextField("Repository", text: $repository, prompt: Text("acme/agents"))
                        .onChange(of: repository) { _, _ in checked = nil }
                    switch checked {
                    case .success(let login):
                        Text("You're \(login), and you can push to it.").foregroundStyle(.secondary)
                    case .failure(let error):
                        Text(error.localizedDescription).foregroundStyle(.red)
                    case nil:
                        EmptyView()
                    }
                    HStack {
                        if checking { ProgressView().controlSize(.small) }
                        Spacer()
                        if case .success = checked {
                            Button("Join") { team.join(repository.trimmingCharacters(in: .whitespaces)) }
                                .keyboardShortcut(.defaultAction)
                        } else {
                            Button("Check") { check() }
                                .disabled(repository.trimmingCharacters(in: .whitespaces).isEmpty || checking)
                        }
                    }
                } header: {
                    PlanHeader(title: "Join a team", plan: .team)
                } footer: {
                    Text("A team is a private GitHub repository: create one with a README, add your teammates as collaborators, and everyone joins it here. Tethera talks to GitHub through the GitHub CLI with your own login (gh auth login); it never sees a token. \(sharedNote)")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                HStack {
                    Text("Team rules are a policies.json at the top of the repository, in the same format as yours.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Copy My Rules") {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        let json = (try? encoder.encode(PolicyStore.shared.rules)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(json, forType: .string)
                    }
                }
            } header: {
                Text("Team policies")
            }
        }
        .formStyle(.grouped)
    }

    private var sharedNote: String {
        "Each member shares their agents' names, repositories, states and costs, and this month's approvals (what each was for, and who answered), on their own branch of the repository. Never terminal output."
    }

    private func check() {
        checking = true
        let repo = repository.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                checked = .success(try await team.check(repo))
            } catch {
                checked = .failure(error)
            }
            checking = false
        }
    }
}
