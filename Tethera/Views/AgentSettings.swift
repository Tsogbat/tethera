import SwiftUI
import TetheraKit

/// Settings → Agents: which CLIs are installed, and one-click hooks so Tethera knows exactly
/// what each agent is doing. Every change is shown before it's written, and is reversible.
struct AgentSettings: View {
    @ObservedObject private var detector = AgentDetector.shared
    @State private var connected: [AgentIntegrations.Target: Bool] = [:]
    @State private var statusLineConnected = false
    @State private var wrapStatusLine = true
    @State private var review: Review?
    @State private var error: String?

    struct Review: Identifiable {
        let target: AgentIntegrations.Target
        let connecting: Bool
        let plan: AgentIntegrations.Plan
        var id: String { "\(target.rawValue)-\(connecting)" }
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

    private func reload() {
        for target in AgentIntegrations.Target.allCases {
            connected[target] = AgentIntegrations.isConnected(target)
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
            self.error = "Couldn't update \(review.target.configFile.path): \(error.localizedDescription)"
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
            Text("\(review.connecting ? "Connect" : "Disconnect") \(review.target.kind.displayName)")
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
            if let note = review.plan.note {
                Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("A backup of each file is saved next to it before writing.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button(review.connecting ? "Connect" : "Disconnect", action: confirm)
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
