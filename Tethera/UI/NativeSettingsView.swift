import SwiftUI

struct NativeSettingsView: View {
    @EnvironmentObject private var userSettings: UserSettings
    @State private var selectedTab = 0
    
    private func terminalFont(size: CGFloat = 13) -> Font {
        return Font.custom(userSettings.themeConfiguration.fontFamily, size: size)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            HStack(spacing: 0) {
                TabButton(title: "Appearance", isSelected: selectedTab == 0) {
                    selectedTab = 0
                }
                TabButton(title: "Terminal", isSelected: selectedTab == 1) {
                    selectedTab = 1
                }
                TabButton(title: "AI", isSelected: selectedTab == 2) {
                    selectedTab = 2
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            Divider()
                .background(SwiftUI.Color.gray.opacity(0.3))
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if selectedTab == 0 {
                        AppearanceSettings()
                    } else if selectedTab == 1 {
                        TerminalSettings()
                    } else {
                        AISettingsView()
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(userSettings.themeConfiguration.backgroundColor.color)
        }
        .background(userSettings.themeConfiguration.backgroundColor.color)
        .frame(minWidth: 650, minHeight: 550)
    }
}

// MARK: - Theme Gallery

struct ThemeGalleryView: View {
    @EnvironmentObject private var userSettings: UserSettings
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 16) {
                ForEach(UserSettings.presets) { preset in
                    ThemeTile(preset: preset, isSelected: userSettings.selectedThemeId == preset.id) {
                        userSettings.applyPreset(preset)
                    }
                    .frame(width: 150)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 120)
    }
}

struct ThemeTile: View {
    let preset: ThemePreset
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(preset.configuration.backgroundColor.color)
                        .frame(height: 90)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    isSelected ? preset.configuration.accentColor.color : SwiftUI.Color.gray.opacity(0.2),
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )
                    HStack(spacing: 6) {
                        Text("Aa")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(preset.configuration.textColor.color)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(preset.configuration.backgroundColor.color.opacity(0.5))
                            )
                        RoundedRectangle(cornerRadius: 3)
                            .fill(preset.configuration.accentColor.color)
                            .frame(width: 20, height: 10)
                    }
                    .padding(8)
                }
                Text(preset.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject private var userSettings: UserSettings
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom(userSettings.themeConfiguration.fontFamily, size: 13).weight(.medium))
                .foregroundColor(isSelected ? .primary : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? userSettings.themeConfiguration.accentColor.color.opacity(0.12) : SwiftUI.Color.clear)
        )
    }
}

struct AppearanceSettings: View {
    @EnvironmentObject private var userSettings: UserSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Theme Gallery - primary way to change appearance
            SettingsGroup(title: "Theme Gallery", icon: "paintpalette") {
                ThemeGalleryView()
            }
            
            // Line Spacing setting (moved out of removed Theme section)
            SettingsGroup(title: "Text Display", icon: "text.alignleft") {
                VStack(alignment: .leading, spacing: 16) {
                    SliderRow(
                        title: "Line Spacing",
                        icon: "text.line.first.and.arrowtriangle.forward",
                        value: Binding(
                            get: { userSettings.themeConfiguration.lineSpacing },
                            set: { newValue in
                                userSettings.themeConfiguration.lineSpacing = newValue
                                userSettings.saveSettings()
                            }
                        ),
                        range: 1.0...2.0,
                        step: 0.1,
                        suffix: ""
                    )
                }
            }
            
            SettingsGroup(title: "Typography", icon: "textformat") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Font")
                            .font(.custom("JetBrains Mono", size: 13))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { userSettings.themeConfiguration.fontFamily },
                            set: { newValue in
                                userSettings.themeConfiguration.fontFamily = newValue
                                userSettings.saveSettings()
                            }
                        )) {
                            ForEach(UserSettings.fontOptions, id: \.self) { font in
                                Text(font).tag(font)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 150)
                    }
                    
                    HStack {
                        Text("Font Size")
                            .font(.custom("JetBrains Mono", size: 13))
                        Spacer()
                        Slider(
                            value: Binding(
                                get: { Double(userSettings.themeConfiguration.fontSize) },
                                set: { newValue in
                                    userSettings.themeConfiguration.fontSize = newValue
                                    userSettings.saveSettings()
                                }
                            ),
                            in: 8...24,
                            step: 1
                        )
                        .frame(width: 100)
                        Text("\(Int(userSettings.themeConfiguration.fontSize))")
                            .font(.custom("JetBrains Mono", size: 12))
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                    }
                    
                    HStack {
                        Text("Padding")
                            .font(.custom("JetBrains Mono", size: 13))
                        Spacer()
                        Slider(
                            value: Binding(
                                get: { userSettings.themeConfiguration.padding },
                                set: { newValue in
                                    userSettings.themeConfiguration.padding = newValue
                                    userSettings.saveSettings()
                                }
                            ),
                            in: 0...20,
                            step: 1
                        )
                        .frame(width: 100)
                        Text("\(Int(userSettings.themeConfiguration.padding))")
                            .font(.custom("JetBrains Mono", size: 12))
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                    }
                }
            }
        }
    }
}

struct TerminalSettings: View {
    @EnvironmentObject private var userSettings: UserSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "Behavior", icon: "gear") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Enable autocompletion")
                            .font(.custom("JetBrains Mono", size: 13))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { userSettings.developerSettings.autocompletionEnabled },
                            set: { newValue in
                                userSettings.developerSettings.autocompletionEnabled = newValue
                                userSettings.saveSettings()
                            }
                        ))
                        .toggleStyle(SwitchToggleStyle())
                    }
                    
                    HStack {
                        Text("Show line numbers")
                            .font(.custom("JetBrains Mono", size: 13))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { userSettings.developerSettings.showLineNumbers },
                            set: { newValue in
                                userSettings.developerSettings.showLineNumbers = newValue
                                userSettings.saveSettings()
                            }
                        ))
                        .toggleStyle(SwitchToggleStyle())
                    }
                    
                    HStack {
                        Text("Enable syntax highlighting")
                            .font(.custom("JetBrains Mono", size: 13))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { userSettings.developerSettings.syntaxHighlighting },
                            set: { newValue in
                                userSettings.developerSettings.syntaxHighlighting = newValue
                                userSettings.saveSettings()
                            }
                        ))
                        .toggleStyle(SwitchToggleStyle())
                    }
                    
                    HStack {
                        Text("Auto indent")
                            .font(.custom("JetBrains Mono", size: 13))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { userSettings.developerSettings.autoIndent },
                            set: { newValue in
                                userSettings.developerSettings.autoIndent = newValue
                                userSettings.saveSettings()
                            }
                        ))
                        .toggleStyle(SwitchToggleStyle())
                    }
                    
                    HStack {
                        Text("Word wrap")
                            .font(.custom("JetBrains Mono", size: 13))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { userSettings.developerSettings.wordWrap },
                            set: { newValue in
                                userSettings.developerSettings.wordWrap = newValue
                                userSettings.saveSettings()
                            }
                        ))
                        .toggleStyle(SwitchToggleStyle())
                    }
                }
            }
            
            SettingsGroup(title: "Formatting", icon: "text.justify") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Tab size")
                            .font(.custom("JetBrains Mono", size: 13))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { userSettings.developerSettings.tabSize },
                            set: { newValue in
                                userSettings.developerSettings.tabSize = newValue
                                userSettings.saveSettings()
                            }
                        )) {
                            Text("2").tag(2)
                            Text("4").tag(4)
                            Text("8").tag(8)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 100)
                    }
                }
            }
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let icon: String?
    let content: Content
    @EnvironmentObject private var userSettings: UserSettings
    
    init(title: String, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(userSettings.themeConfiguration.accentColor.color)
                }
                Text(title)
                    .font(.custom(userSettings.themeConfiguration.fontFamily, size: 15).weight(.semibold))
                    .foregroundColor(.primary)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(.leading, icon != nil ? 24 : 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    userSettings.themeConfiguration.isDarkMode ?
                    SwiftUI.Color.white.opacity(0.04) : SwiftUI.Color.black.opacity(0.03)
                )
        )
        .cornerRadius(12)
    }
}


struct SliderRow: View {
    let title: String
    let icon: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                Text(title)
                    .font(.custom("JetBrains Mono", size: 13))
                Spacer()
                Text(String(format: "%.1f", value) + suffix)
                    .font(.custom("JetBrains Mono", size: 12))
                    .foregroundColor(.secondary)
            }
            
            Slider(value: $value, in: range, step: step)
        }
    }
}

// MARK: - AI Settings View (Stage 2-6: AI Layer Configuration)

struct AISettingsView: View {
    @EnvironmentObject private var userSettings: UserSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Master Toggle
            SettingsGroup(title: "AI Assistant", icon: "brain") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable AI Features")
                                .font(.custom("JetBrains Mono", size: 13))
                            Text("AI never auto-executes commands")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { userSettings.aiSettings.isEnabled },
                            set: { newValue in
                                userSettings.aiSettings.isEnabled = newValue
                                userSettings.saveSettings()
                            }
                        ))
                        .toggleStyle(SwitchToggleStyle())
                    }
                    
                    if userSettings.aiSettings.isEnabled {
                        Divider()
                        
                        // Provider Selection
                        HStack {
                            HStack(spacing: 8) {
                                Image(systemName: userSettings.aiSettings.provider.icon)
                                    .foregroundColor(userSettings.themeConfiguration.accentColor.color)
                                Text("AI Provider")
                                    .font(.custom("JetBrains Mono", size: 13))
                            }
                            Spacer()
                            Picker("", selection: Binding(
                                get: { userSettings.aiSettings.provider },
                                set: { newValue in
                                    userSettings.aiSettings.provider = newValue
                                    userSettings.saveSettings()
                                }
                            )) {
                                ForEach(AIProvider.allCases, id: \.self) { provider in
                                    Text(provider.displayName).tag(provider)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(width: 150)
                        }
                    }
                }
            }
            
            if userSettings.aiSettings.isEnabled {
                // Features
                SettingsGroup(title: "Features", icon: "sparkles") {
                    VStack(alignment: .leading, spacing: 16) {
                        NativeToggleRow(
                            title: "Inline Command Help",
                            description: "Show explanations for commands",
                            isOn: Binding(
                                get: { userSettings.aiSettings.showInlineHelp },
                                set: { newValue in
                                    userSettings.aiSettings.showInlineHelp = newValue
                                    userSettings.saveSettings()
                                }
                            )
                        )
                        
                        NativeToggleRow(
                            title: "Error Explanations",
                            description: "Explain command failures",
                            isOn: Binding(
                                get: { userSettings.aiSettings.showErrorExplanations },
                                set: { newValue in
                                    userSettings.aiSettings.showErrorExplanations = newValue
                                    userSettings.saveSettings()
                                }
                            )
                        )
                        
                        NativeToggleRow(
                            title: "Block Summaries",
                            description: "Auto-summarize long output",
                            isOn: Binding(
                                get: { userSettings.aiSettings.enableBlockSummaries },
                                set: { newValue in
                                    userSettings.aiSettings.enableBlockSummaries = newValue
                                    userSettings.saveSettings()
                                }
                            )
                        )
                        
                        NativeToggleRow(
                            title: "Command Generation",
                            description: "Generate commands from prompts",
                            isOn: Binding(
                                get: { userSettings.aiSettings.enableCommandGeneration },
                                set: { newValue in
                                    userSettings.aiSettings.enableCommandGeneration = newValue
                                    userSettings.saveSettings()
                                }
                            )
                        )
                    }
                }
                
                // Safety & Privacy
                SettingsGroup(title: "Safety & Privacy", icon: "shield.fill") {
                    VStack(alignment: .leading, spacing: 16) {
                        NativeToggleRow(
                            title: "Offline Fallback",
                            description: "Use man pages when offline",
                            isOn: Binding(
                                get: { userSettings.aiSettings.enableOfflineFallback },
                                set: { newValue in
                                    userSettings.aiSettings.enableOfflineFallback = newValue
                                    userSettings.saveSettings()
                                }
                            )
                        )
                        
                        NativeToggleRow(
                            title: "Allow Network Calls",
                            description: "Enable AI API requests",
                            isOn: Binding(
                                get: { userSettings.aiSettings.allowNetworkCalls },
                                set: { newValue in
                                    userSettings.aiSettings.allowNetworkCalls = newValue
                                    userSettings.saveSettings()
                                }
                            )
                        )
                        
                        Divider()
                        
                        NativeToggleRow(
                            title: "Warn on Destructive Commands",
                            description: "Alert before rm, sudo, kill, etc.",
                            isOn: Binding(
                                get: { userSettings.aiSettings.warnOnDestructiveOps },
                                set: { newValue in
                                    userSettings.aiSettings.warnOnDestructiveOps = newValue
                                    userSettings.saveSettings()
                                }
                            )
                        )
                    }
                }
                
                // Safety Notice
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Safety Rules")
                            .font(.system(size: 12, weight: .semibold))
                        Text("AI never auto-executes commands. You always see and confirm before execution.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(SwiftUI.Color.blue.opacity(0.1))
                )
            }
        }
    }
}

struct NativeToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("JetBrains Mono", size: 13))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle())
        }
    }
}


#Preview {
    NativeSettingsView()
        .environmentObject(UserSettings())
        .frame(width: 650, height: 550)
}

