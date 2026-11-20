import SwiftUI

/// Tethera's plans. Everything is free during the beta; a plan only says where a feature
/// belongs, so nothing is locked and nothing is charged.
enum Plan: String, CaseIterable, Identifiable {
    case free, pro, team

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        case .team: return "Team"
        }
    }

    var summary: String {
        switch self {
        case .free: return "Everything on your Mac."
        case .pro: return "Your agents from anywhere."
        case .team: return "Agents across your team."
        }
    }

    var features: [String] {
        switch self {
        case .free:
            return ["Sessions that survive quitting", "Agent status and notifications", "Approvals inbox",
                    "Changes, Git, and Homebrew panes", "Transcripts and budgets", "Agents in worktrees"]
        case .pro:
            return ["Other Macs over SSH", "Phone dashboard", "Push to your phone"]
        case .team:
            return ["Shared agent board", "Approval policies", "Cost dashboard", "Audit log"]
        }
    }

    /// Plans whose features haven't shipped yet.
    var arrives: String? { self == .team ? "Coming in 1.0" : nil }
}

/// Settings → Plan.
struct PlanSettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Plan.allCases) { plan in
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plan.title).font(.title3.weight(.semibold))
                            Text(plan.summary).foregroundStyle(.secondary)
                        }
                        Divider()
                        ForEach(plan.features, id: \.self) { feature in
                            Text(feature).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Text(plan.arrives ?? "Free during the beta")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
                }
            }
            Text("Every plan is free while Tethera is in beta. There's no account and nothing to sign up for.")
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}
