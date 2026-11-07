import SwiftUI
import TetheraKit

/// Settings → Agents: which CLIs are installed, and one-click hooks so Tethera knows exactly
/// what each agent is doing. Every change is shown before it's written, and is reversible.
struct AgentSettings: View {
    @ObservedObject private var detector = AgentDetector.shared
    @State private var connected: [AgentIntegrations.Target: Bool] = [:]
    @State private var browserConnected: [AgentIntegrations.Target: Bool] = [:]
    @State private var statusLineConnected = false
    @State private var wrapStatusLine = true
    @State private var review: Review?
    @State private var error: String?

    struct Review: Identifiable {
        let target: AgentIntegrations.Target
        let connecting: Bool
        let plan: AgentIntegrations.Plan
        var browser = false
        var id: String { "\(target.rawValue)-\(connecting)-\(browser)" }
        var title: String {
            browser
                ? "\(connecting ? "Add the browser to" : "Remove the browser from") \(AgentSettings.browserAgent(target).displayName)"
                : "\(connecting ? "Connect" : "Disconnect") \(target.kind.displayName)"
        }
    }

    var body: some View {
        Form {
            Section {
                ForEach(AgentDetector.launchable, id: \.self) { kind in
                    row(kind)
                }
            } header: {
                HStack {
                    Text("Agents")
                    Spacer()
                    Button("Refresh") { Task { await detector.refresh(); reload() } }.controlSize(.small)
                }
            } footer: {
                Text("Claude Code reports its state to Tethera on its own. Connecting adds small hooks so every agent reports what it's doing — tool calls, permission requests, finished turns — and you get notified when one needs you. Tethera shows each change before writing it and keeps a backup.")
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(AgentIntegrations.Target.allCases, id: \.self) { target in
                    browserRow(target)
                }
            } header: {
                Text("Browser for agents")
            } footer: {
                Text("Adds `tethera mcp` as an MCP server, so an agent can open pages in a Tethera tab beside its session, read them, click and type, and take screenshots: handy for checking the app it's building. You watch every step.")
                    .foregroundStyle(.secondary)
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
        .sheet(item: $review) { review in
            PlanReview(review: review) {
                apply(review)
            } cancel: {
                self.review = nil
            }
        }
    }

    @ViewBuilder
    private func row(_ kind: AgentKind) -> some View {
        let status = detector.status(for: kind)
        let target = AgentIntegrations.Target(kind: kind)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SessionGlyph(agent: kind, size: 14, color: .primary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(kind.displayName)
                        if let version = status?.version {
                            Text(version).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                    Text(status?.path ?? "Not installed").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let target, status?.isInstalled == true {
                    if connected[target] == true {
                        Label("Connected", systemImage: "checkmark").labelStyle(.titleAndIcon).font(.caption).foregroundStyle(.secondary)
                        Button("Disconnect") { prepare(target, connecting: false) }.controlSize(.small)
                    } else {
                        Button("Connect…") { prepare(target, connecting: true) }.controlSize(.small)
                    }
                } else if kind == .ollama && status?.isInstalled == true {
                    Text("Runs agents on local models").font(.caption).foregroundStyle(.secondary)
                }
            }
            if kind == .claude, status?.isInstalled == true {
                Toggle("Also show model, context and cost (wraps your status line; it keeps working unchanged)", isOn: $wrapStatusLine)
                    .font(.caption)
                    .disabled(connected[.claude] == true)
                    .padding(.leading, 24)
            }
        }
        .padding(.vertical, 2)
    }

    /// The agent whose config the browser goes into: `~/.gemini/settings.json` is Gemini CLI's.
    static func browserAgent(_ target: AgentIntegrations.Target) -> AgentKind {
        target == .antigravity ? .gemini : target.kind
    }

    @ViewBuilder
    private func browserRow(_ target: AgentIntegrations.Target) -> some View {
        let agent = Self.browserAgent(target)
        let installed = detector.status(for: agent)?.isInstalled == true
        HStack(spacing: 10) {
            SessionGlyph(agent: agent, size: 14, color: .primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.displayName)
                Text((AgentIntegrations.mcpConfigFile(target).path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if browserConnected[target] == true {
                Label("Added", systemImage: "checkmark").labelStyle(.titleAndIcon).font(.caption).foregroundStyle(.secondary)
                Button("Remove") { prepareBrowser(target, connecting: false) }.controlSize(.small)
            } else if installed {
                Button("Add…") { prepareBrowser(target, connecting: true) }.controlSize(.small)
            } else {
                Text("Not installed").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func prepareBrowser(_ target: AgentIntegrations.Target, connecting: Bool) {
        error = nil
        let executable = detector.status(for: Self.browserAgent(target))?.path
        let plan = connecting
            ? AgentIntegrations.mcpConnectPlan(target, agentExecutable: executable)
            : AgentIntegrations.mcpDisconnectPlan(target, agentExecutable: executable)
        review = Review(target: target, connecting: connecting, plan: plan, browser: true)
    }

    private func reload() {
        for target in AgentIntegrations.Target.allCases {
            connected[target] = AgentIntegrations.isConnected(target)
            browserConnected[target] = AgentIntegrations.isMCPConnected(target)
        }
        statusLineConnected = AgentIntegrations.isStatusLineConnected()
    }

    private func prepare(_ target: AgentIntegrations.Target, connecting: Bool) {
        error = nil
        let plan = connecting
            ? AgentIntegrations.connectPlan(target, wrapStatusLine: target == .claude && wrapStatusLine)
            : AgentIntegrations.disconnectPlan(target)
        review = Review(target: target, connecting: connecting, plan: plan)
    }

    private func apply(_ review: Review) {
        do {
            if review.connecting { AgentIntegrations.refreshCLILink(to: DaemonClient.cliPath) }
            try AgentIntegrations.apply(review.plan)
            self.review = nil
            reload()
        } catch {
            let file = review.browser ? AgentIntegrations.mcpConfigFile(review.target) : review.target.configFile
            self.error = "Couldn't update \(file.path): \(error.localizedDescription)"
            self.review = nil
        }
    }
}

/// Shows exactly what will change, line by line, before anything is written.
private struct PlanReview: View {
    let review: AgentSettings.Review
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(review.title)
                .font(.headline)
            if let manual = review.plan.manualSteps {
                Text(manual)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(review.plan.changes.filter { $0.before != ($0.after ?? "") }, id: \.file) { change in
                        VStack(alignment: .leading, spacing: 6) {
                            Text((change.file.path as NSString).abbreviatingWithTildeInPath + (change.after == nil ? " — removed" : ""))
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                            DiffView(before: change.before, after: change.after ?? "")
                        }
                    }
                }
            }
            .frame(maxHeight: 320)
            ForEach(Array(review.plan.commands.enumerated()), id: \.offset) { _, command in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Runs").font(.system(.caption, design: .monospaced).weight(.semibold))
                    Text(command.map { $0.contains(" ") ? "'\($0)'" : $0 }.joined(separator: " "))
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
                }
            }
            if let note = review.plan.note {
                Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !review.plan.changes.isEmpty {
                Text("A backup of each file is saved next to it before writing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button(review.browser ? (review.connecting ? "Add" : "Remove") : (review.connecting ? "Connect" : "Disconnect"), action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!review.plan.hasChanges)
            }
        }
        .padding(20)
        .frame(width: 620)
    }
}

/// Changed lines only: added in green, removed in red.
private struct DiffView: View {
    let before: String
    let after: String

    private var lines: [(String, Character)] {
        let old = before.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let new = after.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let difference = new.difference(from: old)
        var result: [(String, Character)] = []
        for change in difference {
            switch change {
            case .remove(_, let line, _): result.append((line, "-"))
            case .insert(_, let line, _): result.append((line, "+"))
            }
        }
        return result.filter { !$0.0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, entry in
                Text("\(String(entry.1)) \(entry.0)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(entry.1 == "+" ? Color.green : Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .textSelection(.enabled)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
    }
}
