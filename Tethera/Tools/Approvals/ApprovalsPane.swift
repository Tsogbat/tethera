import SwiftUI
import TetheraKit

/// Every permission request in one place (⌥⌘A). Claude Code's can be answered here; other
/// agents' are listed so you can jump to them.
struct ApprovalsPane: View {
    let paneID: UUID
    @ObservedObject private var center = ApprovalCenter.shared
    @ObservedObject private var client = DaemonClient.shared
    @Environment(\.theme) private var theme

    /// Sessions waiting on a permission that Tethera can't answer for them.
    private var inTerminal: [SessionInfo] {
        client.sessions.filter { $0.needsYou && !center.hasPending(for: $0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(paneID: paneID, icon: "checkmark.shield", title: "Approvals",
                       detail: center.pending.isEmpty ? nil : "\(center.pending.count) waiting") { EmptyView() }
            if center.pending.isEmpty && inTerminal.isEmpty {
                VStack(spacing: 6) {
                    Text("Nothing waiting.").font(TypeScale.ui(13, .medium)).foregroundStyle(theme.text2.color)
                    Text("When an agent asks to run something, it shows up here and as a notification.")
                        .font(TypeScale.ui(12)).foregroundStyle(theme.text3.color)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            VStack(spacing: 0) {
                                ForEach(center.pending) { approval in
                                    ApprovalRow(approval: approval, now: context.date)
                                }
                            }
                        }
                        if !inTerminal.isEmpty {
                            SectionLabel(text: "Waiting in the terminal")
                                .padding(.top, 22)
                                .padding(.bottom, 6)
                            ForEach(inTerminal) { session in
                                HStack(spacing: 10) {
                                    SessionGlyph(agent: session.agent?.kind, size: 12, color: theme.accent.color)
                                    Text(session.name).font(TypeScale.ui(13, .semibold)).foregroundStyle(theme.text.color)
                                    Text(session.agent?.message ?? session.subtitle.text)
                                        .font(TypeScale.ui(12)).foregroundStyle(theme.text2.color).lineLimit(1)
                                    Spacer()
                                    Button("Go to session") { Workspace.shared.show(session.id) }
                                        .buttonStyle(.plain).font(TypeScale.ui(12, .medium)).foregroundStyle(theme.text.color)
                                }
                                .frame(height: 36)
                                .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline.color).frame(height: 1) }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
            }
        }
        .background(theme.bg.color)
    }
}

private struct ApprovalRow: View {
    let approval: ApprovalCenter.Approval
    let now: Date
    @ObservedObject private var client = DaemonClient.shared
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SessionGlyph(agent: approval.agent, size: 12, color: theme.text.color)
                Text(client.session(approval.session)?.name ?? approval.agent.displayName)
                    .font(TypeScale.ui(13, .semibold)).foregroundStyle(theme.text.color)
                Text("wants to run \(approval.tool)").font(TypeScale.ui(12.5)).foregroundStyle(theme.text2.color)
                Spacer()
                Text(Elapsed.short(since: approval.since, now: now)).font(TypeScale.mono(10.5)).foregroundStyle(theme.text3.color)
            }
            Text(approval.summary)
                .font(TypeScale.mono(12))
                .foregroundStyle(theme.text.color)
                .lineLimit(4)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Metrics.controlRadius).fill(theme.surface.color))
            HStack(spacing: 8) {
                Button { ApprovalCenter.shared.answer(approval.id, .allow) } label: {
                    Text("Allow").font(TypeScale.ui(12, .semibold)).foregroundStyle(theme.bg.color)
                        .padding(.horizontal, 14).frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: Metrics.controlRadius).fill(theme.text.color))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                Button { ApprovalCenter.shared.answer(approval.id, .deny) } label: {
                    Text("Deny").font(TypeScale.ui(12, .semibold)).foregroundStyle(theme.text.color)
                        .padding(.horizontal, 14).frame(height: 26)
                        .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius).strokeBorder(theme.hairline.color))
                }
                .buttonStyle(.plain)
                Button("Answer in terminal") { ApprovalCenter.shared.answer(approval.id, .terminal) }
                    .buttonStyle(.plain).font(TypeScale.ui(12)).foregroundStyle(theme.text2.color)
                    .padding(.leading, 6)
                Spacer()
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline.color).frame(height: 1) }
    }
}
