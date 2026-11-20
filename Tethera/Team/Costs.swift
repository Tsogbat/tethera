import Charts
import SwiftUI
import TetheraKit

/// Spend from the journal, by day, agent and repository. Agents report a running total per
/// conversation; each cost event adds how far its session's total grew since the last one
/// (`Journal.spend`), credited to that event's day.
@MainActor
enum CostReport {
    static func daily(days: Int, now: Date = Date(), journal: Journal? = nil) -> [MemberStatus.DayCost] {
        let journal = journal ?? .shared
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) ?? now
        let baselineStart = calendar.date(byAdding: .day, value: -7, to: start) ?? start
        let baseline = journal.events(from: baselineStart, to: start.addingTimeInterval(-0.001))
        return daily(events: journal.events(from: start, to: now), baseline: baseline)
    }

    static func daily(events: [Journal.Event], baseline: [Journal.Event]) -> [MemberStatus.DayCost] {
        var last: [UUID: Double] = [:]
        for event in baseline where event.kind == .cost {
            if let session = event.session, let cost = event.costUSD { last[session] = cost }
        }
        var totals: [String: Double] = [:]
        for event in events where event.kind == .cost {
            guard let session = event.session, let cost = event.costUSD else { continue }
            let spent = last[session].map { cost >= $0 ? cost - $0 : cost } ?? cost
            last[session] = cost
            guard spent > 0 else { continue }
            let repo = event.repo.map { (WorktreeMonitor.shared.repoRoot(for: $0) ?? $0) as NSString }?.lastPathComponent ?? "—"
            let key = [JournalFile.dayName(event.at), event.agent ?? "agent", repo].joined(separator: "\u{1f}")
            totals[key, default: 0] += spent
        }
        return totals.map { key, usd in
            let parts = key.components(separatedBy: "\u{1f}")
            return MemberStatus.DayCost(day: parts[0], agent: parts[1], repo: parts[2], usd: usd)
        }
        .sorted { ($0.day, $0.agent, $0.repo) < ($1.day, $1.agent, $1.repo) }
    }
}

/// The cost dashboard: what your agents (or your team's) spent each day, and on what.
struct CostsPane: View {
    let paneID: UUID
    @ObservedObject private var team = TeamSync.shared
    @Environment(\.theme) private var theme
    @State private var days = 14
    @State private var scope = "you"
    @State private var rows: [Row] = []
    @State private var hovered: String?

    /// One day's spend by one member, agent and repository.
    struct Row: Hashable {
        var member: String
        var cost: MemberStatus.DayCost
    }

    private var dayKeys: [String] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<days).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map(JournalFile.dayName)
        }
    }

    private var perDay: [(day: String, usd: Double)] {
        let sums = Dictionary(grouping: rows, by: \.cost.day).mapValues { $0.reduce(0) { $0 + $1.cost.usd } }
        return dayKeys.map { ($0, sums[$0] ?? 0) }
    }

    private var total: Double { rows.reduce(0) { $0 + $1.cost.usd } }

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(paneID: paneID, icon: "chart.bar", title: "Costs", detail: team.repository.map { scope == "team" ? $0 : "your Mac" }) {
                if team.repository != nil {
                    Segments(options: [("you", "You"), ("team", "Team")], selection: $scope)
                }
                Segments(options: [(7, "7 days"), (14, "14 days"), (30, "30 days")], selection: $days)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    headline
                    chart
                    if !rows.isEmpty {
                        HStack(alignment: .top, spacing: 28) {
                            breakdown("By agent", rows.map { (AgentKind(rawValue: $0.cost.agent)?.displayName ?? $0.cost.agent, $0.cost.usd) })
                            breakdown("By repository", rows.map { ($0.cost.repo, $0.cost.usd) })
                            if scope == "team" {
                                breakdown("By member", rows.map { ($0.member, $0.cost.usd) })
                            }
                        }
                    }
                    Text(footnote)
                        .font(TypeScale.ui(11.5))
                        .foregroundStyle(theme.text3.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
        .background(theme.bg.color)
        .onAppear(perform: load)
        .onChange(of: days) { _, _ in load() }
        .onChange(of: scope) { _, _ in load() }
        .onChange(of: team.members) { _, _ in if scope == "team" { load() } }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: "$%.2f", total))
                .font(TypeScale.ui(30, .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.text.color)
            Text("\(scope == "team" ? "Your team's agents" : "Your agents") in the last \(days) days · \(String(format: "$%.2f", perDay.last?.usd ?? 0)) today")
                .font(TypeScale.ui(12.5))
                .foregroundStyle(theme.text2.color)
        }
    }

    private var chart: some View {
        Chart(perDay, id: \.day) { day in
            BarMark(x: .value("Day", day.day), y: .value("Spend", day.usd), width: .ratio(0.62))
                .foregroundStyle(hovered == nil || hovered == day.day ? theme.text.color : theme.text.color.opacity(0.35))
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
                .accessibilityLabel(Self.label(day.day))
                .accessibilityValue(String(format: "$%.2f", day.usd))
            if let hovered, hovered == day.day {
                RuleMark(x: .value("Day", day.day))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit, y: .disabled)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Self.label(day.day)).font(TypeScale.ui(11)).foregroundStyle(theme.text2.color)
                            Text(String(format: "$%.2f", day.usd)).font(TypeScale.ui(12.5, .semibold)).monospacedDigit().foregroundStyle(theme.text.color)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(theme.raised.color))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.hairline.color))
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: dayKeys.enumerated().filter { $0.offset % max(1, days / 7) == 0 }.map(\.element)) { value in
                AxisValueLabel { Text(Self.label(value.as(String.self) ?? "", short: true)).font(TypeScale.ui(10.5)).foregroundStyle(theme.text3.color) }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(theme.hairline.color)
                AxisValueLabel { Text(String(format: "$%.0f", value.as(Double.self) ?? 0)).font(TypeScale.ui(10.5)).foregroundStyle(theme.text3.color) }
            }
        }
        .chartXSelection(value: $hovered)
        .frame(height: 200)
        .accessibilityLabel("Spend per day")
    }

    private func breakdown(_ title: String, _ items: [(String, Double)]) -> some View {
        let sums = Dictionary(items, uniquingKeysWith: +).sorted { $0.value > $1.value }
        let top = sums.first?.value ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title)
            ForEach(sums.prefix(8), id: \.key) { name, usd in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(name).font(TypeScale.ui(12.5)).foregroundStyle(theme.text.color).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(String(format: "$%.2f", usd)).font(TypeScale.ui(12.5)).monospacedDigit().foregroundStyle(theme.text2.color)
                    }
                    GeometryReader { proxy in
                        Capsule().fill(theme.text.color.opacity(0.75)).frame(width: max(2, proxy.size.width * usd / max(top, 0.0001)), height: 3)
                    }
                    .frame(height: 3)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footnote: String {
        scope == "team"
            ? "From each member's last update to the team repository. Costs are the agents' own reports (Claude Code's status line)."
            : "From the agents' own cost reports (Claude Code's status line), kept in Tethera's journal on this Mac."
    }

    private func load() {
        if scope == "team" {
            let keys = Set(dayKeys)
            rows = team.members.flatMap { member in
                member.costs.filter { keys.contains($0.day) }.map { Row(member: member.login, cost: $0) }
            }
        } else {
            rows = CostReport.daily(days: days).map { Row(member: team.login ?? "you", cost: $0) }
        }
    }

    /// "2026-11-20" → "Fri 20" (short: "20").
    static func label(_ day: String, short: Bool = false) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: day) else { return day }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(short ? "MMMd" : "EEEMMMd")
        return formatter.string(from: date)
    }
}
