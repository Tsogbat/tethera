import SwiftUI
import AppKit

enum InputMode: Equatable {
    case shell
    case generate   // "# find large files"
    case ask        // "? why did the build fail" or ⌘I

    var glyph: String {
        switch self {
        case .shell: return "chevron.right"
        case .generate: return "number"
        case .ask: return "sparkle"
        }
    }
}

/// The floating glass command bar at the bottom of each pane.
struct InputBarView: View {
    @EnvironmentObject private var settings: UserSettings
    @ObservedObject var viewModel: BlockTerminalViewModel
    @ObservedObject private var detector = AgentDetector.shared
    let isActivePane: Bool

    @StateObject private var autocomplete = AutocompleteEngine()
    @State private var text = ""
    @State private var editorHeight: CGFloat = 20
    @State private var caretX: CGFloat = 0
    @State private var isFocused = false
    @State private var editorFocusToken = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: DesignTheme { settings.theme }
    private var fontFamily: String { settings.themeConfiguration.fontFamily }
    private var fontSize: CGFloat { CGFloat(settings.themeConfiguration.fontSize) }
    private var provider: AgentCLI { settings.aiSettings.provider }

    private var mode: InputMode {
        if viewModel.aiModeSticky { return .ask }
        if text.hasPrefix("#") { return .generate }
        if text.hasPrefix("?") { return .ask }
        return .shell
    }

    private var isGenerating: Bool {
        if case .loading = viewModel.generation { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            contextRow
            if viewModel.isRunning && viewModel.presentation == .inline {
                runningRow
                    .transition(.opacity.combined(with: .offset(y: 4)))
            } else {
                editorRow
                    .transition(.opacity.combined(with: .offset(y: -4)))
                if case .failed(let failure) = viewModel.generation {
                    generationError(failure)
                        .transition(.opacity.combined(with: .offset(y: -4)))
                } else if isFocused && text.isEmpty && !isGenerating {
                    hintsRow
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous),
                      tint: mode == .shell ? nil : theme.accent,
                      elevated: true)
        .overlay {
            if isGenerating {
                ThinkingBorder(shape: RoundedRectangle(cornerRadius: 18, style: .continuous), colors: BrandGradient.colors, lineWidth: 1.4)
                    .transition(.opacity)
            } else if mode != .shell {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(BrandGradient.linear.opacity(0.55), lineWidth: 1)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
            if autocomplete.isDropdownVisible && !autocomplete.dropdownSuggestions.isEmpty {
                AutocompleteSuggestionView(
                    suggestions: autocomplete.dropdownSuggestions,
                    selectedIndex: $autocomplete.selectedIndex,
                    onSelect: apply(_:)
                )
                .frame(width: 400)
                .offset(x: max(0, min(caretX + 26, 600)))
                .alignmentGuide(.top) { $0[.bottom] + 8 }
                .transition(.popover)
                .zIndex(10)
            }
        }
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: mode)
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: viewModel.isRunning)
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: isGenerating)
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: autocomplete.isDropdownVisible)
        .animation(Motion.quick, value: isFocused && text.isEmpty)
        .onChange(of: viewModel.focusEditorToken) { _, _ in
            if isActivePane { editorFocusToken += 1 }
        }
        .onChange(of: isActivePane) { _, active in
            if active && !viewModel.isRunning { editorFocusToken += 1 }
        }
        .onAppear {
            if isActivePane { editorFocusToken += 1 }
        }
    }

    // MARK: Rows

    private var contextRow: some View {
        HStack(spacing: 6) {
            MetaChip(icon: "folder.fill", text: viewModel.displayWorkingDirectory, tint: theme.accent)
            if let git = viewModel.gitInfo {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.success)
                    Text(git.branch)
                        .font(Typography.mono(fontFamily, size: 11, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    if git.isDirty {
                        Circle().fill(theme.warning).frame(width: 5, height: 5)
                            .help("Uncommitted changes")
                    }
                    if let aheadBehind = git.aheadBehindText {
                        Text(aheadBehind)
                            .font(Typography.mono(fontFamily, size: 10.5))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(theme.surfaceRaised.opacity(0.7)))
                .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 0.5))
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            ForEach(viewModel.attachedBlockIDs, id: \.self) { id in
                if let block = viewModel.block(id) {
                    AttachmentChip(title: block.input) { viewModel.toggleAttachment(id) }
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            if mode == .shell, let warning = AIAssistant.shared.destructiveWarning(for: text) {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(Typography.ui(11, weight: .medium))
                    .foregroundStyle(theme.warning)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(theme.warning.opacity(0.12)))
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            Spacer(minLength: 8)
            if settings.aiSettings.isEnabled {
                providerMenu
            }
        }
        .animation(Motion.snappy, value: viewModel.gitInfo)
        .animation(Motion.snappy, value: viewModel.attachedBlockIDs)
    }

    private var providerMenu: some View {
        Menu {
            Section("AI provider") {
                ForEach(AgentCLI.allCases) { candidate in
                    Button {
                        settings.aiSettings.provider = candidate
                    } label: {
                        let installed = detector.status(for: candidate)?.isInstalled ?? false
                        if candidate == provider {
                            Label(candidate.displayName, systemImage: "checkmark")
                        } else {
                            Text(installed ? candidate.displayName : "\(candidate.displayName) (not installed)")
                        }
                    }
                }
            }
            Section {
                ForEach(AgentCLI.allCases.filter { detector.status(for: $0)?.isInstalled ?? false }) { agent in
                    Button("Open \(agent.displayName) here") { viewModel.launchAgent(agent) }
                }
            }
            Divider()
            Button("AI Settings…") { AppCommands.shared.send(.openSettings) }
        } label: {
            HStack(spacing: 6) {
                AgentBadge(agent: provider, size: 15)
                Text(provider.displayName)
                    .font(Typography.ui(11.5, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.leading, 4)
            .padding(.trailing, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(theme.surfaceRaised.opacity(0.7)))
            .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose which AI CLI answers")
    }

    private var editorRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: mode.glyph)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(mode == .shell ? AnyShapeStyle(theme.accent) : AnyShapeStyle(BrandGradient.linear))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 16, height: max(editorHeight, 20))

            ZStack(alignment: .topLeading) {
                if case .loading(let request) = viewModel.generation {
                    HStack(spacing: 8) {
                        ThinkingText(text: "Writing a command for “\(request)”")
                        Spacer()
                        PillButton(title: "Cancel") { viewModel.cancelGeneration() }
                    }
                    .frame(minHeight: editorHeight)
                    .transition(.opacity)
                } else {
                    CommandEditor(
                        text: $text,
                        ghost: ghost,
                        placeholder: placeholder,
                        font: TerminalFont.nsFont(family: fontFamily, size: fontSize, weight: .medium),
                        textColor: NSColor(theme.textPrimary),
                        ghostColor: NSColor(theme.textTertiary),
                        caretColor: theme.accentNS,
                        focusToken: editorFocusToken,
                        insertion: viewModel.insertion,
                        onKey: handle(_:),
                        onHeightChange: { height in
                            withAnimation(Motion.quick) { editorHeight = height }
                        },
                        onCaretX: { caretX = $0 },
                        onFocusChange: { isFocused = $0 }
                    )
                    .frame(height: max(editorHeight, 20))
                    .transition(.opacity)
                }
            }

            if !text.trimmingCharacters(in: .whitespaces).isEmpty && !isGenerating {
                Button(action: submit) {
                    Image(systemName: mode == .shell ? "return" : "arrow.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(mode == .shell ? AnyShapeStyle(theme.accent) : AnyShapeStyle(BrandGradient.linear)))
                }
                .buttonStyle(.plain)
                .help(mode == .shell ? "Run (↩)" : "Send to \(provider.displayName) (↩)")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .onChange(of: text) { _, newValue in
            textChanged(newValue)
        }
    }

    private var runningRow: some View {
        HStack(spacing: 10) {
            PulsingDot(color: theme.accent, size: 6)
            if let agent = viewModel.runningAgent {
                AgentBadge(agent: agent, size: 16)
            }
            Text(viewModel.runningBlock?.input ?? "")
                .font(Typography.mono(fontFamily, size: 12.5, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            if let block = viewModel.runningBlock {
                RunningClock(start: block.timestamp)
                    .font(Typography.mono(fontFamily, size: 11))
                    .foregroundStyle(theme.textTertiary)
            }
            Spacer(minLength: 8)
            Text(viewModel.live.hasFocus ? "Keys go to the program" : "Click the output to type into it")
                .font(Typography.ui(11))
                .foregroundStyle(theme.textTertiary)
            KeyHint(keys: "⌃C", label: "stop")
            IconButton(systemName: "arrow.up.left.and.arrow.down.right", help: "Full screen") { viewModel.togglePresentation() }
            PillButton(title: "Stop", systemImage: "stop.fill", tint: theme.danger) { viewModel.stopRunning() }
        }
        .frame(minHeight: 26)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.live.focus() }
    }

    private var hintsRow: some View {
        HStack(spacing: 14) {
            KeyHint(keys: "#", label: "describe a command")
            KeyHint(keys: "?", label: "ask \(provider.displayName)")
            KeyHint(keys: "⌘P", label: "commands")
            KeyHint(keys: "⌃R", label: "history")
            Spacer()
        }
        .padding(.leading, 26)
    }

    private func generationError(_ failure: AgentFailure) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(theme.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(failure.message)
                    .font(Typography.ui(11.5))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(3)
                if let hint = failure.hint {
                    Text(hint).font(Typography.ui(11)).foregroundStyle(theme.textTertiary)
                }
            }
            Spacer()
            if failure.kind == .notSignedIn || failure.kind == .notInstalled {
                PillButton(title: "Sign in") { AppCommands.shared.send(.runInNewTab(provider.loginCommand)) }
            }
            IconButton(systemName: "xmark", help: "Dismiss", size: 20) { viewModel.cancelGeneration() }
        }
        .padding(.leading, 26)
    }

    // MARK: Text state

    private var placeholder: String {
        if viewModel.shellState == .starting { return "Starting \((ShellEnvironment.loginShell as NSString).lastPathComponent)…" }
        if viewModel.shellState == .exited { return "The shell exited — restart it from the block above" }
        switch mode {
        case .shell: return "Run a command, # describe one, or ? ask AI"
        case .generate: return "Describe the command you need"
        case .ask: return "Ask \(provider.displayName) anything — Esc to leave AI mode"
        }
    }

    /// Text drawn after the caret.
    private var ghost: String {
        guard mode == .shell, settings.terminal.autocompletion || viewModel.aiGhost != nil else { return "" }
        if text.isEmpty {
            return viewModel.aiGhost ?? ""
        }
        let completion = autocomplete.inlineCompletion
        guard completion.count > text.count, completion.hasPrefix(text) else { return "" }
        return String(completion.dropFirst(text.count))
    }

    private func textChanged(_ newValue: String) {
        if !newValue.isEmpty { viewModel.dismissAIGhost() }
        if case .failed = viewModel.generation { viewModel.cancelGeneration() }
        guard mode == .shell, settings.terminal.autocompletion else {
            autocomplete.clear()
            return
        }
        autocomplete.updateInlineCompletion(for: newValue,
                                            history: CommandHistoryManager.shared.suggestionCorpus,
                                            workingDirectory: viewModel.workingDirectory)
        if autocomplete.isDropdownVisible {
            autocomplete.showDropdownSuggestions(for: newValue, workingDirectory: viewModel.workingDirectory)
        }
    }

    // MARK: Keys

    private func handle(_ key: EditorKey) -> Bool {
        switch key {
        case .submit:
            if autocomplete.isDropdownVisible, let suggestion = autocomplete.getSelectedSuggestion() {
                apply(suggestion)
                return true
            }
            submit()
            return true
        case .submitAlternate:
            let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !question.isEmpty else { return true }
            text = ""
            autocomplete.clear()
            viewModel.ask(stripPrefix(question))
            return true
        case .tab:
            if autocomplete.isDropdownVisible {
                if let suggestion = autocomplete.getSelectedSuggestion() { apply(suggestion) }
                return true
            }
            if text.isEmpty, let ghostCommand = viewModel.aiGhost {
                setText(ghostCommand)
                return true
            }
            guard mode == .shell, !text.isEmpty else { return true }
            autocomplete.showDropdownSuggestions(for: text, workingDirectory: viewModel.workingDirectory)
            return true
        case .shiftTab:
            if autocomplete.isDropdownVisible { autocomplete.navigateUp() }
            return true
        case .up:
            if autocomplete.isDropdownVisible {
                autocomplete.navigateUp()
            } else if let previous = viewModel.historyPrevious(currentInput: text) {
                setText(previous)
            }
            return true
        case .down:
            if autocomplete.isDropdownVisible {
                autocomplete.navigateDown()
            } else if let next = viewModel.historyNext() {
                setText(next)
            }
            return true
        case .acceptGhost:
            let suffix = ghost
            guard !suffix.isEmpty else { return false }
            setText(text + suffix)
            return true
        case .escape:
            if autocomplete.isDropdownVisible {
                autocomplete.hideDropdown()
            } else if isGenerating {
                viewModel.cancelGeneration()
            } else if viewModel.aiModeSticky {
                viewModel.aiModeSticky = false
            } else if viewModel.aiGhost != nil {
                viewModel.dismissAIGhost()
            } else if mode != .shell {
                text = ""
            } else {
                return false
            }
            return true
        case .historySearch:
            AppCommands.shared.send(.search)
            return true
        case .interrupt:
            text = ""
            autocomplete.clear()
            viewModel.cancelGeneration()
            return true
        case .clearScreen:
            viewModel.clearBlocks()
            return true
        }
    }

    private func submit() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, viewModel.runningBlockID == nil else { return }
        autocomplete.clear()
        switch mode {
        case .shell:
            text = ""
            viewModel.submit(value)
        case .generate:
            text = ""
            viewModel.generateCommand(from: stripPrefix(value))
        case .ask:
            text = ""
            viewModel.ask(stripPrefix(value))
        }
    }

    private func stripPrefix(_ value: String) -> String {
        var result = value
        if result.hasPrefix("#") || result.hasPrefix("?") { result.removeFirst() }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private func setText(_ value: String) {
        text = value
        autocomplete.clear()
        viewModel.insert(value)
    }

    private func apply(_ suggestion: AutocompleteSuggestion) {
        var updated = autocomplete.applySuggestion(suggestion, to: text)
        if suggestion.type == .command { updated += " " }
        setText(updated)
        if suggestion.type == .directory {
            autocomplete.showDropdownSuggestions(for: updated, workingDirectory: viewModel.workingDirectory)
        }
    }
}

struct AttachmentChip: View {
    @EnvironmentObject private var settings: UserSettings
    let title: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "paperclip").font(.system(size: 9.5, weight: .semibold))
            Text(title)
                .font(Typography.mono(settings.themeConfiguration.fontFamily, size: 10.5, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: 140)
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 7.5, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(settings.theme.accent)
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(settings.theme.accentSoft))
        .help("Attached to your next AI question")
    }
}
