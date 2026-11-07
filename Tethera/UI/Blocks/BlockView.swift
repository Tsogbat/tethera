import SwiftUI
import AppKit

/// Routes a block to its view.
struct BlockView: View {
    let block: TerminalBlock
    @ObservedObject var viewModel: BlockTerminalViewModel
    let isSelected: Bool
    let liveNamespace: Namespace.ID

    var body: some View {
        switch block.kind {
        case .command:
            CommandBlockView(block: block, viewModel: viewModel, isSelected: isSelected, liveNamespace: liveNamespace)
        case .ai:
            AIBlockView(block: block, viewModel: viewModel, isSelected: isSelected)
        case .system:
            SystemBlockView(block: block, viewModel: viewModel)
        }
    }
}

// MARK: - Command block

struct CommandBlockView: View {
    @EnvironmentObject private var settings: UserSettings
    let block: TerminalBlock
    @ObservedObject var viewModel: BlockTerminalViewModel
    let isSelected: Bool
    let liveNamespace: Namespace.ID

    @State private var hovering = false
    @State private var isEditing = false
    @State private var editedCommand = ""
    @State private var showAllOutput = false
    @State private var showRawMarkdown = false
    @State private var copiedFlash = false
    @State private var markdownEditor: MarkdownFileEditor.Model?
    @FocusState private var editFieldFocused: Bool

    private var theme: DesignTheme { settings.theme }
    private var fontFamily: String { settings.themeConfiguration.fontFamily }
    private var fontSize: CGFloat { CGFloat(settings.themeConfiguration.fontSize) }
    private var isAttached: Bool { viewModel.attachedBlockIDs.contains(block.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            commandLine
            output
            if block.hasMedia, let files = block.mediaFiles {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(files, id: \.self) { MediaPreviewView(filePath: $0) }
                }
                .padding(.top, 2)
            }
            fixRow
            explanationPanel
        }
        .padding(.vertical, Layout.blockInsetV)
        .padding(.horizontal, Layout.blockInsetH)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .overlay(alignment: .leading) { rail }
        .overlay(alignment: .topTrailing) {
            if (hovering || isSelected) && !block.isRunning && !isEditing {
                BlockToolbar(block: block, viewModel: viewModel, onEdit: beginEditing, onCopy: copyOutput)
                    .padding(.top, 6)
                    .padding(.trailing, 8)
                    .transition(.opacity.combined(with: .offset(x: 6)))
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(Motion.quick) { hovering = inside }
        }
        .onTapGesture {
            viewModel.select(isSelected ? nil : block.id)
        }
        .contextMenu { contextMenu }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 6) {
            Text(BlockTerminalViewModel.abbreviate(block.workingDirectory ?? "~"))
                .lineLimit(1)
                .truncationMode(.head)
            if let branch = block.gitBranch {
                Text("·").foregroundStyle(theme.textTertiary.opacity(0.6))
                Image(systemName: "arrow.triangle.branch").font(.system(size: 9, weight: .semibold))
                Text(branch).lineLimit(1)
            }
            Spacer(minLength: 12)
            if block.isRunning {
                RunningClock(start: block.timestamp)
            } else {
                if let duration = block.formattedDuration {
                    Text(duration)
                }
                Text(block.timestamp, format: .dateTime.hour().minute())
                if block.isFailure, let code = block.exitCode {
                    ExitCodePill(code: code)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            if isAttached {
                Image(systemName: "paperclip")
                    .foregroundStyle(theme.accent)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .font(Typography.mono(fontFamily, size: 10.5, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(theme.textTertiary)
        // Leave room for the hover toolbar.
        .padding(.trailing, (hovering || isSelected) && !block.isRunning ? 190 : 0)
    }

    @ViewBuilder
    private var commandLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let agent = block.category == .agent ? AgentCLI(programName: CommandLineParser.programName(of: block.input)) : nil {
                AgentBadge(agent: agent, size: 16)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            }
            if isEditing {
                TextField("Command", text: $editedCommand)
                    .textFieldStyle(.plain)
                    .font(Typography.mono(fontFamily, size: fontSize, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .focused($editFieldFocused)
                    .onSubmit(commitEdit)
                    .onExitCommand(perform: cancelEdit)
                PillButton(title: "Run", systemImage: "return", prominent: true, action: commitEdit)
                PillButton(title: "Cancel", action: cancelEdit)
            } else {
                Text(block.input)
                    .font(Typography.mono(fontFamily, size: fontSize, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var output: some View {
        if block.isRunning {
            if viewModel.runningBlockID == block.id && viewModel.presentation == .inline {
                LiveTerminalHost(live: viewModel.live)
                    .modifier(LiveHeightObserver(live: viewModel.live))
                    .matchedGeometryEffect(id: "live", in: liveNamespace)
                    .onTapGesture { viewModel.live.focus() }
            } else if viewModel.presentation == .fullPane {
                Label("Running full screen", systemImage: "rectangle.expand.vertical")
                    .font(Typography.ui(11, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
            }
        } else if let editor = markdownEditor {
            MarkdownFileEditor(model: editor, onClose: { withAnimation(Motion.smooth) { markdownEditor = nil } })
        } else if block.isMarkdownContent && !showRawMarkdown && !block.output.isEmpty {
            MarkdownOutputView(content: block.output)
        } else if !block.output.isEmpty {
            let threshold = max(20, settings.terminal.collapseThreshold)
            let hidden = block.outputLineCount - threshold
            VStack(alignment: .leading, spacing: 6) {
                if hidden > 0 && !showAllOutput {
                    Button {
                        withAnimation(Motion.smooth) { showAllOutput = true }
                    } label: {
                        Label("Show \(hidden) earlier lines", systemImage: "chevron.up")
                            .font(Typography.ui(11, weight: .medium))
                            .foregroundStyle(theme.accent)
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
                if let truncated = block.styledOutput?.truncatedLineCount, truncated > 0, showAllOutput || hidden <= 0 {
                    Text("… \(truncated) earlier lines weren't kept")
                        .font(Typography.ui(11))
                        .foregroundStyle(theme.textTertiary)
                }
                StyledOutputView(block: block, lineLimit: showAllOutput ? nil : threshold)
            }
        }
    }

    @ViewBuilder
    private var fixRow: some View {
        switch block.fix {
        case .idle:
            EmptyView()
        case .loading:
            AIInlineRow(state: .working("Looking for a fix…"))
                .transition(.opacity.combined(with: .offset(y: -4)))
        case .ready(let command):
            AIInlineRow(state: .suggestion(command),
                        onInsert: { viewModel.insert(command) },
                        onDismiss: { viewModel.dismissFix(blockID: block.id) })
                .transition(.opacity.combined(with: .offset(y: -4)))
        case .failed(let message):
            AIInlineRow(state: .unavailable(message), onDismiss: { viewModel.dismissFix(blockID: block.id) })
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var explanationPanel: some View {
        switch block.explanation {
        case .idle:
            EmptyView()
        case .loading:
            AIPanel(provider: settings.aiSettings.provider, isWorking: true, onClose: { viewModel.dismissExplanation(blockID: block.id) }) {
                ThinkingText(text: "Reading the output…")
            }
            .transition(.opacity.combined(with: .offset(y: -6)))
        case .ready(let text):
            AIPanel(provider: settings.aiSettings.provider, isWorking: false, onClose: { viewModel.dismissExplanation(blockID: block.id) }) {
                MarkdownOutputView(content: text, onInsertCode: { viewModel.insert($0) })
            }
            .transition(.opacity.combined(with: .offset(y: -6)))
        case .failed(let message):
            AIPanel(provider: settings.aiSettings.provider, isWorking: false, onClose: { viewModel.dismissExplanation(blockID: block.id) }) {
                Text(message).font(Typography.ui(12)).foregroundStyle(theme.danger)
            }
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isSelected ? theme.selection : (hovering ? theme.surface : Color.clear))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? theme.accent.opacity(0.35) : (isAttached ? theme.accent.opacity(0.25) : .clear), lineWidth: 0.75)
            )
    }

    @ViewBuilder
    private var rail: some View {
        if block.isRunning {
            ShimmerBar(color: theme.accent)
                .frame(width: 2.5)
                .clipShape(Capsule())
                .padding(.vertical, 10)
                .transition(.opacity)
        } else if block.isFailure {
            Capsule()
                .fill(theme.danger)
                .frame(width: 2.5)
                .padding(.vertical, 10)
                .transition(.opacity.combined(with: .scale(scale: 0.5, anchor: .top)))
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Copy Command") { copy(block.input) }
        Button("Copy Output") { copy(block.output) }
        Button("Copy Command and Output") { copy("$ \(block.input)\n\(block.output)") }
        Divider()
        Button("Rerun") { viewModel.rerun(blockID: block.id) }
        Button("Edit and Rerun") { beginEditing() }
        Button("Insert into Prompt") { viewModel.insert(block.input) }
        if let path = block.markdownSourcePath {
            Button("Edit Markdown File") { openMarkdownEditor(path) }
            Button(showRawMarkdown ? "Render Markdown" : "Show Raw Markdown") { showRawMarkdown.toggle() }
        }
        if viewModel.aiEnabled {
            Divider()
            Button("Explain with AI") { viewModel.explain(blockID: block.id) }
            if block.isFailure { Button("Suggest a Fix") { viewModel.requestFix(blockID: block.id) } }
            Button(isAttached ? "Detach from AI Prompt" : "Attach to AI Prompt") { viewModel.toggleAttachment(block.id) }
            Menu("Send to Agent") {
                ForEach(AgentCLI.allCases) { agent in
                    Button(agent.displayName) { viewModel.sendToAgent(agent, blockID: block.id) }
                }
            }
        }
        Divider()
        Button("Remove Block", role: .destructive) { viewModel.removeBlock(block.id) }
    }

    // MARK: Actions

    private func beginEditing() {
        editedCommand = block.input
        withAnimation(Motion.snappy) { isEditing = true }
        DispatchQueue.main.async { editFieldFocused = true }
    }

    private func commitEdit() {
        let command = editedCommand
        withAnimation(Motion.snappy) { isEditing = false }
        viewModel.rerun(blockID: block.id, command: command)
    }

    private func cancelEdit() {
        withAnimation(Motion.snappy) { isEditing = false }
        editedCommand = block.input
    }

    private func copyOutput() {
        if block.hasMedia, let first = block.mediaFiles?.first, let image = NSImage(contentsOfFile: first) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        } else {
            copy(block.output.isEmpty ? block.input : block.output)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func openMarkdownEditor(_ path: String) {
        withAnimation(Motion.smooth) {
            markdownEditor = MarkdownFileEditor.Model(path: path)
        }
    }
}

// MARK: - Live height

/// Rows in use × cell height, capped at the pane.
enum LiveHeightReader {
    static func height(_ live: LiveTerminal) -> CGFloat {
        max(live.cellSize.height, live.inlineHeight)
    }
}

/// Re-renders the host when the emulator's used rows change.
struct LiveHeightObserver: ViewModifier {
    @ObservedObject var live: LiveTerminal

    func body(content: Content) -> some View {
        content
            .frame(height: LiveHeightReader.height(live))
            .animation(.easeOut(duration: 0.12), value: live.contentRows)
    }
}

// MARK: - Toolbar

struct BlockToolbar: View {
    @EnvironmentObject private var settings: UserSettings
    let block: TerminalBlock
    @ObservedObject var viewModel: BlockTerminalViewModel
    let onEdit: () -> Void
    let onCopy: () -> Void
    @State private var appeared = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 1) {
            if viewModel.aiEnabled {
                item(0) {
                    IconButton(systemName: "sparkle", help: "Explain with AI", tint: settings.theme.accent) {
                        viewModel.explain(blockID: block.id)
                    }
                }
                if block.isFailure {
                    item(1) {
                        IconButton(systemName: "wand.and.stars", help: "Suggest a fix", tint: settings.theme.accent) {
                            viewModel.requestFix(blockID: block.id)
                        }
                    }
                }
            }
            item(2) {
                IconButton(systemName: "arrow.clockwise", help: "Rerun") { viewModel.rerun(blockID: block.id) }
            }
            item(3) {
                IconButton(systemName: "pencil", help: "Edit and rerun", action: onEdit)
            }
            item(4) {
                IconButton(systemName: copied ? "checkmark" : "doc.on.doc", help: "Copy output", tint: copied ? settings.theme.success : nil) {
                    onCopy()
                    withAnimation(Motion.bouncy) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation(Motion.quick) { copied = false } }
                }
            }
            if viewModel.aiEnabled {
                item(5) {
                    IconButton(systemName: viewModel.attachedBlockIDs.contains(block.id) ? "paperclip.circle.fill" : "paperclip",
                               help: "Attach to AI prompt", tint: settings.theme.accent) {
                        viewModel.toggleAttachment(block.id)
                    }
                }
            }
        }
        .padding(3)
        .glassSurface(RoundedRectangle(cornerRadius: 10, style: .continuous), elevated: true)
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
    }

    private func item<Content: View>(_ index: Int, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .opacity(appeared ? 1 : 0)
            .offset(x: appeared ? 0 : 4)
            .animation(Motion.snappy.delay(Double(index) * 0.02), value: appeared)
    }
}

// MARK: - Small pieces

struct ExitCodePill: View {
    @EnvironmentObject private var settings: UserSettings
    let code: Int32

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: code == 130 ? "stop.fill" : "xmark")
                .font(.system(size: 7.5, weight: .heavy))
            Text(code == 130 ? "interrupted" : "\(code)")
        }
        .font(Typography.mono(settings.themeConfiguration.fontFamily, size: 10, weight: .semibold))
        .foregroundStyle(code == 130 ? settings.theme.textSecondary : settings.theme.danger)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill((code == 130 ? settings.theme.textSecondary : settings.theme.danger).opacity(0.12)))
    }
}

struct RunningClock: View {
    @EnvironmentObject private var settings: UserSettings
    let start: Date

    var body: some View {
        TimelineView(.periodic(from: start, by: 0.1)) { context in
            HStack(spacing: 5) {
                PulsingDot(color: settings.theme.accent, size: 5)
                Text(TerminalBlock.format(milliseconds: Int64(max(0, context.date.timeIntervalSince(start)) * 1000)))
                    .contentTransition(.numericText())
            }
        }
    }
}

struct ThinkingText: View {
    @EnvironmentObject private var settings: UserSettings
    let text: String
    @State private var phase = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(text)
            .font(Typography.ui(12, weight: .medium))
            .foregroundStyle(settings.theme.textSecondary)
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(colors: [.clear, settings.theme.textPrimary.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.4)
                            .offset(x: phase ? proxy.size.width : -proxy.size.width * 0.4)
                    }
                    .mask(Text(text).font(Typography.ui(12, weight: .medium)))
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = true }
            }
    }
}

/// A compact AI row under a failed block.
struct AIInlineRow: View {
    enum State {
        case working(String)
        case suggestion(String)
        case unavailable(String)
    }

    @EnvironmentObject private var settings: UserSettings
    let state: State
    var onInsert: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 9) {
            SparkleIcon(active: isWorking, size: 11, color: settings.theme.accent)
            switch state {
            case .working(let text):
                ThinkingText(text: text)
            case .suggestion(let command):
                Text("Try")
                    .font(Typography.ui(12, weight: .medium))
                    .foregroundStyle(settings.theme.textSecondary)
                Text(command)
                    .font(Typography.mono(settings.themeConfiguration.fontFamily, size: 12, weight: .medium))
                    .foregroundStyle(settings.theme.textPrimary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                PillButton(title: "Insert", systemImage: "arrow.down.to.line", prominent: true) { onInsert?() }
            case .unavailable(let message):
                Text(message)
                    .font(Typography.ui(11.5))
                    .foregroundStyle(settings.theme.textTertiary)
                    .lineLimit(2)
                Spacer(minLength: 8)
            }
            if let onDismiss, !isWorking {
                IconButton(systemName: "xmark", help: "Dismiss", size: 20, action: onDismiss)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(settings.theme.accentSoft.opacity(0.55))
        )
        .overlay {
            if isWorking {
                ThinkingBorder(shape: RoundedRectangle(cornerRadius: 9, style: .continuous), colors: BrandGradient.colors.map { $0.opacity(0.8) }, lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(settings.theme.accent.opacity(0.18), lineWidth: 0.5)
            }
        }
    }

    private var isWorking: Bool {
        if case .working = state { return true }
        return false
    }
}

/// Card used for AI explanations.
struct AIPanel<Content: View>: View {
    @EnvironmentObject private var settings: UserSettings
    let provider: AgentCLI
    let isWorking: Bool
    let onClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                AgentBadge(agent: provider, size: 15)
                Text(provider.displayName)
                    .font(Typography.ui(11.5, weight: .semibold))
                    .foregroundStyle(settings.theme.textSecondary)
                SparkleIcon(active: isWorking, size: 9, color: settings.theme.accent)
                Spacer()
                IconButton(systemName: "xmark", help: "Close", size: 20, action: onClose)
            }
            content
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(settings.theme.surfaceRaised.opacity(0.6)))
        .overlay {
            if isWorking {
                ThinkingBorder(shape: RoundedRectangle(cornerRadius: 11, style: .continuous), colors: BrandGradient.colors, lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(settings.theme.hairline, lineWidth: 0.75)
            }
        }
    }
}

// MARK: - System block

struct SystemBlockView: View {
    @EnvironmentObject private var settings: UserSettings
    let block: TerminalBlock
    @ObservedObject var viewModel: BlockTerminalViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: block.success == false ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(block.success == false ? settings.theme.warning : settings.theme.accent)
            Text(block.output)
                .font(Typography.ui(12.5))
                .foregroundStyle(settings.theme.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if block.input == "restart" && viewModel.shellState == .exited {
                PillButton(title: "Restart", systemImage: "arrow.clockwise", prominent: true) { viewModel.restartShell() }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(settings.theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(settings.theme.hairline, lineWidth: 0.75))
        .padding(.vertical, 4)
    }
}

// MARK: - Markdown file editor

struct MarkdownFileEditor: View {
    @MainActor
    final class Model: ObservableObject {
        let path: String
        @Published var text: String
        @Published private(set) var original: String
        @Published var error: String?

        init(path: String) {
            self.path = path
            let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            self.text = content
            self.original = content
        }

        var isDirty: Bool { text != original }

        func save() -> Bool {
            do {
                try text.write(toFile: path, atomically: true, encoding: .utf8)
                original = text
                error = nil
                return true
            } catch {
                self.error = error.localizedDescription
                return false
            }
        }
    }

    @EnvironmentObject private var settings: UserSettings
    @ObservedObject var model: Model
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text((model.path as NSString).lastPathComponent)
                    .font(Typography.mono(settings.themeConfiguration.fontFamily, size: 11.5, weight: .semibold))
                    .foregroundStyle(settings.theme.textSecondary)
                if model.isDirty {
                    Circle().fill(settings.theme.warning).frame(width: 6, height: 6).transition(.scale)
                }
                if let error = model.error {
                    Text(error).font(Typography.ui(11)).foregroundStyle(settings.theme.danger).lineLimit(1)
                }
                Spacer()
                PillButton(title: "Cancel", action: onClose)
                PillButton(title: "Save", systemImage: "checkmark", prominent: true) {
                    if model.save() { onClose() }
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            HStack(alignment: .top, spacing: 10) {
                TextEditor(text: $model.text)
                    .font(Typography.mono(settings.themeConfiguration.fontFamily, size: CGFloat(settings.themeConfiguration.fontSize) - 1))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(settings.theme.surface))
                ScrollView {
                    MarkdownOutputView(content: model.text)
                        .padding(10)
                }
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(settings.theme.surface.opacity(0.5)))
            }
            .frame(minHeight: 220, maxHeight: 440)
        }
        .animation(Motion.quick, value: model.isDirty)
    }
}

// MARK: - Media preview

struct MediaPreviewView: View {
    @EnvironmentObject private var settings: UserSettings
    let filePath: String
    @State private var image: NSImage?
    @State private var failed = false
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 520, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(settings.theme.border, lineWidth: 0.75))
                    .shadow(color: .black.opacity(hovering ? 0.3 : 0.15), radius: hovering ? 16 : 8, y: 6)
                    .scaleEffect(hovering ? 1.01 : 1)
                    .onHover { inside in withAnimation(Motion.snappy) { hovering = inside } }
                    .onTapGesture { NSWorkspace.shared.open(URL(fileURLWithPath: filePath)) }
                    .help("Open in Preview")
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                Text((filePath as NSString).lastPathComponent)
                    .font(Typography.mono(settings.themeConfiguration.fontFamily, size: 10.5))
                    .foregroundStyle(settings.theme.textTertiary)
            } else if failed {
                Label("Couldn't load \((filePath as NSString).lastPathComponent)", systemImage: "exclamationmark.triangle")
                    .font(Typography.ui(12))
                    .foregroundStyle(settings.theme.textSecondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: filePath) {
            let path = filePath
            let loaded = await Task.detached(priority: .userInitiated) { NSImage(contentsOfFile: path) }.value
            withAnimation(Motion.smooth) {
                image = loaded
                failed = loaded == nil
            }
        }
    }
}
