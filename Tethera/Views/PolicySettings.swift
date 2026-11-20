import SwiftUI
import TetheraKit

/// Your approval rules, kept in `TETHERA_HOME/policies.json` where the `tethera` hook reads them.
@MainActor
final class PolicyStore: ObservableObject {
    static let shared = PolicyStore()

    @Published var rules: [ApprovalRule] = [] {
        didSet { if rules != oldValue { try? ApprovalPolicies.save(rules) } }
    }
    @Published private(set) var teamRules: [ApprovalRule] = []

    private init() { reload() }

    func reload() {
        rules = ApprovalPolicies.load(ApprovalPolicies.localFile)
        teamRules = ApprovalPolicies.load(ApprovalPolicies.teamFile)
    }

    /// Adds a preset's rules once: rules that ask or deny go first, so an allow rule can't
    /// get ahead of them.
    func add(_ preset: ApprovalPolicies.Preset) {
        let fresh = preset.rules.filter { new in !rules.contains { $0.tool == new.tool && $0.pattern == new.pattern && $0.agent == new.agent } }
        let guarding = fresh.filter { $0.action != .allow }
        rules = guarding + rules + fresh.filter { $0.action == .allow }
    }
}

/// Settings → Policies.
struct PolicySettings: View {
    @ObservedObject private var store = PolicyStore.shared
    @ObservedObject private var team = TeamSync.shared
    @State private var editing: ApprovalRule?
    @State private var tryTool = "Bash"
    @State private var tryText = ""

    var body: some View {
        Form {
            if !store.teamRules.isEmpty {
                Section {
                    ForEach(store.teamRules) { RuleRow(rule: $0) }
                } header: {
                    Text("From \(team.repository ?? "your team")")
                } footer: {
                    Text("Your team's rules come before yours.").foregroundStyle(.secondary)
                }
            }
            Section {
                if store.rules.isEmpty {
                    Text("No rules yet. Everything an agent asks comes to you.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.rules) { rule in
                    RuleRow(rule: rule)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { editing = rule }
                        .contextMenu {
                            Button("Edit…") { editing = rule }
                            Button("Move Up") { move(rule, by: -1) }.disabled(store.rules.first == rule)
                            Button("Move Down") { move(rule, by: 1) }.disabled(store.rules.last == rule)
                            Divider()
                            Button("Delete", role: .destructive) { store.rules.removeAll { $0.id == rule.id } }
                        }
                }
                .onMove { store.rules.move(fromOffsets: $0, toOffset: $1) }
                HStack {
                    Menu("Add Preset") {
                        ForEach(ApprovalPolicies.presets) { preset in
                            Button(preset.title) { store.add(preset) }
                        }
                    }
                    .fixedSize()
                    Spacer()
                    Button("Add Rule…") { editing = ApprovalRule(tool: "Bash", action: .allow) }
                }
            } header: {
                Text("Your rules")
            } footer: {
                Text("When Claude Code asks for permission, the first rule that matches answers it, even with Tethera closed. Rules that ask, or no rule, bring the question to you. An allow rule never covers a command that chains, pipes, or redirects (`;` `&&` `|` `>`), so `npm test*` can't allow `npm test && rm -rf ~`. Drag to reorder.")
                    .foregroundStyle(.secondary)
            }
            Section("Try it") {
                HStack {
                    TextField("Tool", text: $tryTool).frame(width: 90)
                    TextField("Command, file, or URL", text: $tryText, prompt: Text("npm test && rm -rf ~"))
                        .font(.system(.body, design: .monospaced))
                }
                Text(verdict).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { store.reload() }
        .sheet(item: $editing) { rule in
            RuleEditor(rule: rule) { saved in
                if let index = store.rules.firstIndex(where: { $0.id == saved.id }) {
                    store.rules[index] = saved
                } else if saved.action == .allow {
                    store.rules.append(saved)
                } else {
                    store.rules.insert(saved, at: 0)
                }
            }
        }
    }

    private var verdict: String {
        guard !tryText.isEmpty else { return "Type something an agent might run to see which rule answers it." }
        let input: [String: Any] = tryTool == "Bash" ? ["command": tryText] : ["file_path": tryText]
        guard let decision = ApprovalPolicies.decide(agent: "claude", tool: tryTool, input: input, team: store.teamRules, local: store.rules) else {
            return ApprovalPolicies.isCompound(tool: tryTool, subject: tryText)
                ? "Asks you: it does more than one thing, so no allow rule covers it."
                : "Asks you: no rule matches."
        }
        let by = "\(decision.fromTeam ? "team rule" : "rule") \(decision.rule.summary)"
        switch decision.rule.action {
        case .allow: return "Allowed by the \(by)."
        case .deny: return "Denied by the \(by)."
        case .ask: return "Asks you, by the \(by)."
        }
    }

    private func move(_ rule: ApprovalRule, by offset: Int) {
        guard let index = store.rules.firstIndex(of: rule) else { return }
        let target = index + offset
        guard store.rules.indices.contains(target) else { return }
        store.rules.swapAt(index, target)
    }
}

private struct RuleRow: View {
    let rule: ApprovalRule

    var body: some View {
        HStack(spacing: 10) {
            Text(rule.action.rawValue.capitalized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(rule.action == .deny ? Color.red : .primary)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(rule.tool == "*" ? "Any tool" : rule.tool)
                    if let pattern = rule.pattern, !pattern.isEmpty {
                        Text(pattern).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                if rule.agent != nil || rule.note != nil {
                    Text([rule.agent.flatMap { AgentKind(rawValue: $0)?.displayName ?? $0 }, rule.note].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

private struct RuleEditor: View {
    @State var rule: ApprovalRule
    let save: (ApprovalRule) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rule").font(.headline)
            Form {
                Picker("When", selection: $rule.action) {
                    Text("Allow").tag(ApprovalRule.Action.allow)
                    Text("Deny").tag(ApprovalRule.Action.deny)
                    Text("Ask me").tag(ApprovalRule.Action.ask)
                }
                Picker("Agent", selection: Binding(get: { rule.agent ?? "" }, set: { rule.agent = $0.isEmpty ? nil : $0 })) {
                    Text("Any agent").tag("")
                    ForEach([AgentKind.claude, .codex, .gemini, .antigravity, .opencode], id: \.self) { Text($0.displayName).tag($0.rawValue) }
                }
                HStack {
                    TextField("Tool", text: $rule.tool, prompt: Text("Bash"))
                    Menu("") {
                        ForEach(["Bash", "Edit", "Write", "Read", "WebFetch", "mcp__*", "*"], id: \.self) { name in
                            Button(name == "*" ? "Any tool" : name) { rule.tool = name }
                        }
                    }
                    .fixedSize()
                }
                TextField("Matching", text: Binding(get: { rule.pattern ?? "" }, set: { rule.pattern = $0.isEmpty ? nil : $0 }),
                          prompt: Text("npm test*  ·  */secrets/*  ·  /regex/"))
                    .font(.system(.body, design: .monospaced))
                TextField("Note", text: Binding(get: { rule.note ?? "" }, set: { rule.note = $0.isEmpty ? nil : $0 }),
                          prompt: Text("Why, shown when it denies"))
            }
            .formStyle(.columns)
            Text("Matching is a pattern for the command, file path, or URL: `*` is anything, `?` one character. Empty matches everything the tool does.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    save(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(rule.tool.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
