import SwiftUI

/// A question and the streamed answer from the user's AI CLI.
struct AIBlockView: View {
    @EnvironmentObject private var settings: UserSettings
    let block: TerminalBlock
    @ObservedObject var viewModel: BlockTerminalViewModel
    let isSelected: Bool
    @State private var hovering = false
    @State private var copied = false

    private var theme: DesignTheme { settings.theme }
    private var provider: AgentCLI { block.aiProvider ?? settings.aiSettings.provider }
    private var isWorking: Bool { block.status == .running }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AgentBadge(agent: provider, size: 18)
                Text(provider.displayName)
                    .font(Typography.ui(12, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                if let model = settings.aiSettings.model(for: provider, role: .chat) {
                    Text(model)
                        .font(Typography.mono(settings.themeConfiguration.fontFamily, size: 10.5))
                        .foregroundStyle(theme.textTertiary)
                }
                SparkleIcon(active: isWorking, size: 10, color: theme.accent)
                Spacer()
                if isWorking {
                    PillButton(title: "Stop", systemImage: "stop.fill") { viewModel.stopAI(blockID: block.id) }
                        .transition(.opacity)
                } else if hovering || isSelected {
                    HStack(spacing: 2) {
                        IconButton(systemName: copied ? "checkmark" : "doc.on.doc", help: "Copy answer", tint: copied ? theme.success : nil) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(block.output, forType: .string)
                            withAnimation(Motion.bouncy) { copied = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation(Motion.quick) { copied = false } }
                        }
                        IconButton(systemName: "arrow.clockwise", help: "Ask again") { viewModel.ask(block.input) }
                        IconButton(systemName: "xmark", help: "Remove") { viewModel.removeBlock(block.id) }
                    }
                    .transition(.opacity.combined(with: .offset(x: 4)))
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("?")
                    .font(Typography.mono(settings.themeConfiguration.fontFamily, size: 13, weight: .bold))
                    .foregroundStyle(BrandGradient.linear)
                Text(block.input)
                    .font(Typography.ui(13.5, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = block.aiError {
                AIErrorView(message: error, hint: block.aiHint, provider: provider)
                    .transition(.opacity)
            } else if block.output.isEmpty && isWorking {
                ThinkingText(text: "Thinking with \(provider.displayName)…")
                    .padding(.vertical, 2)
                    .transition(.opacity)
            } else {
                MarkdownOutputView(content: block.output, onInsertCode: { viewModel.insert($0) })
                    .transition(.opacity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.surfaceRaised.opacity(isSelected ? 0.85 : 0.55))
        )
        .overlay {
            if isWorking {
                ThinkingBorder(shape: RoundedRectangle(cornerRadius: 14, style: .continuous), colors: BrandGradient.colors, lineWidth: 1.2)
                    .transition(.opacity)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? theme.accent.opacity(0.4) : theme.hairline, lineWidth: 0.75)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { inside in withAnimation(Motion.quick) { hovering = inside } }
        .onTapGesture { viewModel.select(isSelected ? nil : block.id) }
        .animation(Motion.smooth, value: isWorking)
    }
}

struct AIErrorView: View {
    @EnvironmentObject private var settings: UserSettings
    let message: String
    let hint: String?
    let provider: AgentCLI

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(message)
                    .font(Typography.ui(12))
                    .foregroundStyle(settings.theme.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(settings.theme.danger)
            }
            if let hint {
                Text(hint)
                    .font(Typography.ui(11.5))
                    .foregroundStyle(settings.theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                PillButton(title: "Sign in to \(provider.displayName)", systemImage: "person.crop.circle") {
                    AppCommands.shared.send(.runInNewTab(provider.loginCommand))
                }
                PillButton(title: "AI Settings", systemImage: "gearshape") {
                    AppCommands.shared.send(.openSettings)
                }
            }
        }
    }
}
