import SwiftUI

struct NativeSettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case appearance = "Appearance"
        case terminal = "Terminal"
        case ai = "AI"
        case about = "About"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .appearance: return "paintpalette"
            case .terminal: return "terminal"
            case .ai: return "sparkle"
            case .about: return "info.circle"
            }
        }
    }

    @EnvironmentObject private var settings: UserSettings
    @State private var section: Section = .appearance
    @Namespace private var pill

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(Section.allCases) { item in
                    Button {
                        withAnimation(Motion.snappy) { section = item }
                    } label: {
                        Label(item.rawValue, systemImage: item.icon)
                            .font(Typography.ui(12.5, weight: .medium))
                            .foregroundStyle(section == item ? settings.theme.textPrimary : settings.theme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background {
                                if section == item {
                                    Color.clear
                                        .glassSurface(Capsule(), tint: settings.theme.accent)
                                        .matchedGeometryEffect(id: "section", in: pill)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Capsule().fill(settings.theme.surface.opacity(0.7)))
            .overlay(Capsule().strokeBorder(settings.theme.hairline, lineWidth: 0.5))
            .padding(.top, 18)
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch section {
                    case .appearance: AppearanceSettings()
                    case .terminal: TerminalSettings()
                    case .ai: AISettingsView()
                    case .about: AboutSettings()
                    }
                }
                .frame(maxWidth: 720)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .id(section)
                .transition(.opacity.combined(with: .offset(y: 6)))
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Building blocks

struct SettingsCard<Content: View>: View {
    @EnvironmentObject private var settings: UserSettings
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typography.ui(13.5, weight: .semibold))
                    .foregroundStyle(settings.theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.ui(11.5))
                        .foregroundStyle(settings.theme.textTertiary)
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SettingsRow<Accessory: View>: View {
    @EnvironmentObject private var settings: UserSettings
    let title: String
    var detail: String? = nil
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.ui(12.5, weight: .medium))
                    .foregroundStyle(settings.theme.textPrimary)
                if let detail {
                    Text(detail)
                        .font(Typography.ui(11))
                        .foregroundStyle(settings.theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
    }
}

// MARK: - Appearance

struct AppearanceSettings: View {
    @EnvironmentObject private var settings: UserSettings

    var body: some View {
        SettingsCard(title: "Theme", subtitle: "Colors for the window, blocks and the terminal's 16 ANSI colors.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(UserSettings.presets) { preset in
                    ThemeTile(preset: preset, isSelected: settings.selectedThemeId == preset.id) {
                        withAnimation(.easeInOut(duration: 0.25)) { settings.applyPreset(preset) }
                    }
                }
            }
        }

        SettingsCard(title: "Text") {
            SettingsRow(title: "Font") {
                Picker("", selection: $settings.themeConfiguration.fontFamily) {
                    ForEach(UserSettings.fontOptions, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 180)
            }
            SettingsRow(title: "Size", detail: "⌘+ and ⌘− work anywhere.") {
                HStack(spacing: 10) {
                    Slider(value: $settings.themeConfiguration.fontSize, in: 10...24, step: 1)
                        .frame(width: 160)
                    Text("\(Int(settings.themeConfiguration.fontSize)) pt")
                        .font(Typography.ui(11.5).monospacedDigit())
                        .foregroundStyle(settings.theme.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
            SettingsRow(title: "Line spacing") {
                HStack(spacing: 10) {
                    Slider(value: $settings.themeConfiguration.lineSpacing, in: 1.0...1.8, step: 0.05)
                        .frame(width: 160)
                    Text(String(format: "%.2f", settings.themeConfiguration.lineSpacing))
                        .font(Typography.ui(11.5).monospacedDigit())
                        .foregroundStyle(settings.theme.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }

        SettingsCard(title: "Window") {
            SettingsRow(title: "Glass opacity", detail: "Lower values let more of the desktop blur through.") {
                HStack(spacing: 10) {
                    Slider(value: $settings.terminal.windowOpacity, in: 0.55...1.0, step: 0.01)
                        .frame(width: 160)
                    Text("\(Int(settings.terminal.windowOpacity * 100))%")
                        .font(Typography.ui(11.5).monospacedDigit())
                        .foregroundStyle(settings.theme.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }
}

struct ThemeTile: View {
    @EnvironmentObject private var settings: UserSettings
    let preset: ThemePreset
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        let palette = preset.configuration.effectivePalette
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("~/code").foregroundStyle(palette.foreground.color.opacity(0.45))
                        Text("main").foregroundStyle(palette.green.color)
                    }
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    Text("git status")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.foreground.color)
                    HStack(spacing: 3) {
                        ForEach(1..<7) { index in
                            RoundedRectangle(cornerRadius: 2).fill(palette.ansi[index].color).frame(width: 12, height: 6)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.background.color))
                .overlay(alignment: .topTrailing) {
                    Circle().fill(preset.configuration.accentColor.color).frame(width: 8, height: 8).padding(8)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? settings.theme.accent : settings.theme.border, lineWidth: isSelected ? 2 : 0.75)
                )
                .scaleEffect(hovering ? 1.02 : 1)

                HStack {
                    Text(preset.name)
                        .font(Typography.ui(12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(settings.theme.textPrimary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(settings.theme.accent)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(Motion.snappy) { hovering = inside } }
        .animation(Motion.bouncy, value: isSelected)
    }
}

// MARK: - Terminal

struct TerminalSettings: View {
    @EnvironmentObject private var settings: UserSettings

    var body: some View {
        SettingsCard(title: "Cursor & keyboard") {
            SettingsRow(title: "Cursor shape") {
                Picker("", selection: $settings.terminal.cursorShape) {
                    ForEach(CursorShape.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            SettingsRow(title: "Blinking cursor") {
                Toggle("", isOn: $settings.terminal.cursorBlink).toggleStyle(.switch).labelsHidden()
            }
            SettingsRow(title: "Option key acts as Meta", detail: "Needed for Alt-shortcuts in vim, emacs and many TUIs.") {
                Toggle("", isOn: $settings.terminal.optionAsMeta).toggleStyle(.switch).labelsHidden()
            }
            SettingsRow(title: "Inline suggestions", detail: "Ghost text from your history (→ to accept) and the Tab menu.") {
                Toggle("", isOn: $settings.terminal.autocompletion).toggleStyle(.switch).labelsHidden()
            }
        }

        SettingsCard(title: "Output") {
            SettingsRow(title: "Collapse output longer than", detail: "Long blocks show the end first, with a button for the rest.") {
                Stepper("\(settings.terminal.collapseThreshold) lines", value: $settings.terminal.collapseThreshold, in: 50...5_000, step: 50)
                    .font(Typography.ui(12).monospacedDigit())
            }
            SettingsRow(title: "Scrollback while running", detail: "Lines kept for a single running command.") {
                Stepper("\(settings.terminal.scrollbackLines) lines", value: $settings.terminal.scrollbackLines, in: 1_000...100_000, step: 1_000)
                    .font(Typography.ui(12).monospacedDigit())
            }
        }

        SettingsCard(title: "Shell", subtitle: "zsh and bash are supported. New tabs use the change.") {
            SettingsRow(title: "Shell path", detail: "Leave empty to use your login shell (\(ShellEnvironment.loginShell)).") {
                TextField("/bin/zsh", text: $settings.terminal.shellPath)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }
        }
    }
}

// MARK: - AI

struct AISettingsView: View {
    @EnvironmentObject private var settings: UserSettings
    @ObservedObject private var detector = AgentDetector.shared
    @State private var testResult: [AgentCLI: TestState] = [:]

    enum TestState: Equatable {
        case running
        case passed(TimeInterval)
        case failed(String)
    }

    var body: some View {
        SettingsCard(title: "AI assistant", subtitle: "Tethera drives the AI CLIs you're already signed in to — no API keys. Nothing the AI suggests ever runs without you pressing Enter.") {
            SettingsRow(title: "Enable AI features") {
                Toggle("", isOn: $settings.aiSettings.isEnabled).toggleStyle(.switch).labelsHidden()
            }
            if settings.aiSettings.isEnabled {
                SettingsRow(title: "Suggest a fix when a command fails", detail: "Runs one quick request with the failed command and its output.") {
                    Toggle("", isOn: $settings.aiSettings.autoFixOnFailure).toggleStyle(.switch).labelsHidden()
                }
                SettingsRow(title: "Share recent output as context", detail: "Recent blocks are included when you ask a question.") {
                    HStack(spacing: 10) {
                        if settings.aiSettings.includeOutputContext {
                            Stepper("\(settings.aiSettings.contextBlockCount) blocks", value: $settings.aiSettings.contextBlockCount, in: 1...12)
                                .font(Typography.ui(12).monospacedDigit())
                        }
                        Toggle("", isOn: $settings.aiSettings.includeOutputContext).toggleStyle(.switch).labelsHidden()
                    }
                }
                SettingsRow(title: "Warn about destructive commands", detail: "Shows a warning chip for rm -r, sudo, kill and similar.") {
                    Toggle("", isOn: $settings.aiSettings.warnOnDestructiveOps).toggleStyle(.switch).labelsHidden()
                }
            }
        }

        SettingsCard(title: "Providers", subtitle: "Pick the CLI that answers. Fast model: commands and fixes. Chat model: questions and explanations.") {
            HStack {
                Spacer()
                Button {
                    Task { await detector.refresh() }
                } label: {
                    Label(detector.isRefreshing ? "Detecting…" : "Detect again", systemImage: "arrow.triangle.2.circlepath")
                        .font(Typography.ui(11.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(settings.theme.accent)
                .disabled(detector.isRefreshing)
            }
            VStack(spacing: 10) {
                ForEach(AgentCLI.allCases) { provider in
                    ProviderRow(provider: provider,
                                status: detector.status(for: provider),
                                models: detector.models[provider] ?? [],
                                isSelected: settings.aiSettings.provider == provider,
                                test: testResult[provider],
                                onSelect: { withAnimation(Motion.snappy) { settings.aiSettings.provider = provider } },
                                onTest: { runTest(provider) })
                }
            }
        }
        .task { if detector.models[.opencode] == nil { await detector.loadModels(for: .opencode) } }
    }

    private func runTest(_ provider: AgentCLI) {
        testResult[provider] = .running
        let started = Date()
        let request = AgentRequest(provider: provider, prompt: "Reply with exactly: OK", system: "",
                                   model: settings.aiSettings.model(for: provider, role: .fast),
                                   workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path, timeout: 90)
        Task {
            let result = await AgentRunner.complete(request)
            withAnimation(Motion.snappy) {
                switch result {
                case .success: testResult[provider] = .passed(Date().timeIntervalSince(started))
                case .failure(let failure): testResult[provider] = .failed(failure.hint ?? failure.message)
                }
            }
        }
    }
}

struct ProviderRow: View {
    @EnvironmentObject private var settings: UserSettings
    let provider: AgentCLI
    let status: AgentDetector.Status?
    let models: [String]
    let isSelected: Bool
    let test: AISettingsView.TestState?
    let onSelect: () -> Void
    let onTest: () -> Void

    private var installed: Bool { status?.isInstalled ?? false }

    private var fastModel: Binding<String> {
        Binding(get: { settings.aiSettings.models[provider.rawValue]?.fast ?? "" },
                set: { settings.aiSettings.models[provider.rawValue, default: ProviderModels()].fast = $0 })
    }

    private var chatModel: Binding<String> {
        Binding(get: { settings.aiSettings.models[provider.rawValue]?.chat ?? "" },
                set: { settings.aiSettings.models[provider.rawValue, default: ProviderModels()].chat = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                Button(action: onSelect) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(isSelected ? settings.theme.accent : settings.theme.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(!installed)

                AgentBadge(agent: provider, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.displayName)
                            .font(Typography.ui(13, weight: .semibold))
                            .foregroundStyle(settings.theme.textPrimary)
                        if let version = status?.version {
                            Text("v\(version)")
                                .font(Typography.mono(settings.themeConfiguration.fontFamily, size: 10.5))
                                .foregroundStyle(settings.theme.textTertiary)
                        }
                    }
                    Text(installed ? provider.tagline : "Not installed")
                        .font(Typography.ui(11))
                        .foregroundStyle(installed ? settings.theme.textTertiary : settings.theme.warning)
                }
                Spacer()
                testBadge
                if installed {
                    PillButton(title: "Test", action: onTest)
                    PillButton(title: "Sign in", systemImage: "person.crop.circle") {
                        AppCommands.shared.send(.runInNewTab(provider.loginCommand))
                    }
                }
            }
            if isSelected && installed {
                HStack(spacing: 10) {
                    modelField("Fast model", binding: fastModel)
                    modelField("Chat model", binding: chatModel)
                }
                .padding(.leading, 26)
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? settings.theme.accentSoft.opacity(0.6) : settings.theme.surface.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? settings.theme.accent.opacity(0.4) : settings.theme.hairline, lineWidth: 0.75)
        )
        .opacity(installed ? 1 : 0.6)
        .animation(Motion.snappy, value: isSelected)
    }

    @ViewBuilder
    private var testBadge: some View {
        switch test {
        case .running:
            ProgressView().controlSize(.small)
        case .passed(let seconds):
            Label(String(format: "%.1fs", seconds), systemImage: "checkmark.circle.fill")
                .font(Typography.ui(11, weight: .medium))
                .foregroundStyle(settings.theme.success)
                .transition(.scale.combined(with: .opacity))
        case .failed(let message):
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(settings.theme.danger)
                .help(message)
                .transition(.scale.combined(with: .opacity))
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private func modelField(_ label: String, binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Typography.ui(10.5, weight: .medium))
                .foregroundStyle(settings.theme.textTertiary)
            if !models.isEmpty {
                Picker("", selection: binding) {
                    Text("Default").tag("")
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            } else {
                TextField(provider.modelPlaceholder, text: binding)
                    .textFieldStyle(.roundedBorder)
                    .font(Typography.mono(settings.themeConfiguration.fontFamily, size: 11.5))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - About

struct AboutSettings: View {
    @EnvironmentObject private var settings: UserSettings

    var body: some View {
        VStack(spacing: 14) {
            TetheraMark(size: 96)
                .shadow(color: Color(red: 0.48, green: 0.36, blue: 1).opacity(0.35), radius: 26, y: 12)
            Text("Tethera")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(settings.theme.textPrimary)
            Text("A block terminal for macOS, built on SwiftTerm.")
                .font(Typography.ui(12.5))
                .foregroundStyle(settings.theme.textSecondary)
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") · AGPL-3.0")
                .font(Typography.ui(11))
                .foregroundStyle(settings.theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
