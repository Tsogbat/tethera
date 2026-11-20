import AppKit
import SwiftUI
import TetheraKit
import UserNotifications

/// Notices when you've been gone (Tethera in the background, or the Mac asleep) for a while,
/// and summarizes what the agents did meanwhile from the journal.
@MainActor
final class AwayTracker: ObservableObject {
    static let shared = AwayTracker()

    struct Summary: Equatable {
        struct Row: Identifiable, Equatable {
            let session: UUID
            let name: String
            let agent: AgentKind?
            let outcome: String
            let message: String?
            let cost: Double
            var id: UUID { session }
        }

        let since: Date
        let rows: [Row]
        let approvals: Int

        var headline: String {
            let finished = rows.filter { $0.outcome == "finished" }.count
            let waiting = rows.filter { $0.outcome == "needs you" }.count
            let failed = rows.filter { $0.outcome == "error" }.count
            var parts: [String] = []
            if finished > 0 { parts.append("\(finished) finished") }
            if waiting > 0 { parts.append(waiting == 1 ? "1 needs you" : "\(waiting) need you") }
            if failed > 0 { parts.append(failed == 1 ? "1 hit an error" : "\(failed) hit errors") }
            if parts.isEmpty { parts.append("\(rows.count) kept working") }
            return parts.joined(separator: " · ")
        }
    }

    @Published private(set) var summary: Summary?
    private var leftAt: Date?
    private var observers: [NSObjectProtocol] = []

    /// How long you need to be away before a summary is worth showing.
    private var threshold: TimeInterval {
        ProcessInfo.processInfo.environment["TETHERA_AWAY_SECONDS"].flatMap(TimeInterval.init) ?? 15 * 60
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default, workspace = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AwayTracker.shared.left() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AwayTracker.shared.left() }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AwayTracker.shared.returned() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { if NSApp.isActive { AwayTracker.shared.returned() } }
        })
    }

    private func left() {
        if leftAt == nil { leftAt = Date() }
    }

    private func returned() {
        guard let leftAt else { return }
        self.leftAt = nil
        guard Date().timeIntervalSince(leftAt) >= threshold else { return }
        let built = Self.summarize(since: leftAt)
        if !built.rows.isEmpty { summary = built }
    }

    func dismiss() { summary = nil }

    #if DEBUG
    /// Scripted captures: summarize as if you'd been away since `start`.
    func simulateReturn(since start: Date) {
        summary = Self.summarize(since: start)
    }
    #endif

    /// Each session that changed while you were away: where it ended up, its last message, and
    /// what it spent.
    static func summarize(since start: Date, journal: Journal? = nil) -> Summary {
        let journal = journal ?? .shared
        let events = journal.events(from: start)
        let baseline = journal.events(from: Calendar.current.startOfDay(for: start), to: start)
        let spend = Journal.spend(in: events, baseline: baseline)
        var order: [UUID] = []
        var latest: [UUID: Journal.Event] = [:]
        var names: [UUID: String] = [:]
        var messages: [UUID: String] = [:]
        for event in events {
            guard let session = event.session else { continue }
            if let name = event.sessionName { names[session] = name }
            if event.kind == .state {
                if latest[session] == nil { order.append(session) }
                latest[session] = event
                if let message = event.message, !message.isEmpty { messages[session] = message }
            }
        }
        let rows = order.compactMap { session -> Summary.Row? in
            guard let event = latest[session] else { return nil }
            let outcome: String
            switch AgentState(rawValue: event.state ?? "") {
            case .done, .idle: outcome = "finished"
            case .needsInput: outcome = "needs you"
            case .error: outcome = "error"
            default: outcome = "working"
            }
            return Summary.Row(session: session, name: names[session] ?? "Session", agent: event.agent.flatMap(AgentKind.init(rawValue:)),
                               outcome: outcome, message: messages[session], cost: spend[session] ?? 0)
        }
        // Needs-you first, then errors, then finished.
        let rank = ["needs you": 0, "error": 1, "finished": 2, "working": 3]
        return Summary(since: start, rows: rows.sorted { (rank[$0.outcome] ?? 9) < (rank[$1.outcome] ?? 9) },
                       approvals: events.filter { $0.kind == .approval }.count)
    }
}

/// The summary on Home: one line per session that changed while you were away.
struct AwaySummaryView: View {
    let summary: AwayTracker.Summary
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel(text: "While you were away")
                Text(Elapsed.short(since: summary.since) + " · " + summary.headline)
                    .font(TypeScale.ui(11.5)).foregroundStyle(theme.text2.color)
                Spacer()
                Button("Dismiss") { AwayTracker.shared.dismiss() }
                    .buttonStyle(.plain).font(TypeScale.ui(11.5, .medium)).foregroundStyle(theme.text2.color)
            }
            .padding(.bottom, 8)
            ForEach(summary.rows) { row in
                Button {
                    Workspace.shared.show(row.session)
                } label: {
                    HStack(spacing: 10) {
                        SessionGlyph(agent: row.agent, size: 12, color: row.outcome == "needs you" ? theme.accent.color : theme.text2.color)
                            .frame(width: 14)
                        Text(row.name).font(TypeScale.ui(13, .medium)).foregroundStyle(theme.text.color)
                            .frame(width: 150, alignment: .leading).lineLimit(1)
                        Text(row.outcome)
                            .font(TypeScale.ui(12, row.outcome == "needs you" ? .semibold : .regular))
                            .foregroundStyle(row.outcome == "error" ? theme.danger.color : (row.outcome == "needs you" ? theme.accent.color : theme.text2.color))
                            .frame(width: 80, alignment: .leading)
                        Text(row.message ?? "")
                            .font(TypeScale.ui(12)).foregroundStyle(theme.text2.color).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 8)
                        if row.cost >= 0.01 {
                            Text(String(format: "$%.2f", row.cost)).font(TypeScale.mono(11)).foregroundStyle(theme.text3.color)
                        }
                    }
                    .frame(height: 32)
                    .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline.color).frame(height: 1) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Spending and context limits. Agents report their cost and context use through their status
/// line; Tethera adds up today's spend and warns (and can pause agents) at your limits.
@MainActor
final class BudgetWatcher {
    static let shared = BudgetWatcher()

    private var day = Calendar.current.startOfDay(for: Date())
    private var lastCost: [UUID: Double] = [:]
    private var spentToday: Double = 0
    private var loaded = false
    private var warnedToday = false
    private var contextWarned: Set<UUID> = []

    var todaySpend: Double {
        loadIfNeeded()
        return spentToday
    }

    private func loadIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        if today != day {
            day = today
            loaded = false
            warnedToday = false
        }
        guard !loaded else { return }
        loaded = true
        let events = Journal.shared.events(from: day)
        spentToday = Journal.spend(in: events).values.reduce(0, +)
        lastCost = [:]
        for event in events where event.kind == .cost {
            if let session = event.session, let cost = event.costUSD { lastCost[session] = cost }
        }
        warnedToday = events.contains { $0.kind == .budget && $0.detail == "daily" }
    }

    func check(_ session: SessionInfo) {
        loadIfNeeded()
        let preferences = PreferencesStore.shared.value
        if let cost = session.agent?.costUSD, cost != lastCost[session.id] {
            let previous = lastCost[session.id]
            spentToday += previous.map { cost >= $0 ? cost - $0 : cost } ?? cost
            lastCost[session.id] = cost
        }
        if let budget = preferences.dailyBudgetUSD, budget > 0, spentToday >= budget, !warnedToday {
            warnedToday = true
            Journal.shared.append(.init(at: Date(), kind: .budget, detail: "daily", costUSD: spentToday))
            var body = String(format: "Agents have spent $%.2f today, past your $%.2f limit.", spentToday, budget)
            if preferences.pauseAgentsOverBudget {
                pauseWorkingAgents()
                body += " Working agents were paused."
            }
            notify("Daily budget reached", body)
        }
        if let limit = preferences.contextAlertPercent, limit > 0,
           let used = session.agent?.contextPercent, used >= limit, !contextWarned.contains(session.id) {
            contextWarned.insert(session.id)
            Journal.shared.append(.init(at: Date(), kind: .budget, session: session.id, sessionName: session.name, detail: "context"))
            notify("\(session.name) is at \(Int(used))% context", "Consider compacting or starting a fresh conversation.")
        }
        if let used = session.agent?.contextPercent, let limit = preferences.contextAlertPercent, used < limit - 10 {
            contextWarned.remove(session.id)
        }
    }

    /// Sends Escape, which interrupts Claude Code and most agent TUIs without quitting them.
    private func pauseWorkingAgents() {
        for session in DaemonClient.shared.sessions where session.isWorking {
            DaemonClient.shared.send(session.id, Data([0x1B]))
        }
    }

    private func notify(_ title: String, _ body: String) {
        guard let center = ApprovalCenter.notifications else {
            NSApp.requestUserAttention(.informationalRequest)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
