import SwiftUI

struct NativeSettingsView: View {
    @StateObject private var userSettings = UserSettings()
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
                        AppearanceSettings(userSettings: userSettings)
                    } else {
                        TerminalSettings(userSettings: userSettings)
                    }
                }
                .padding(20)
            }
        }
        .background(SwiftUI.Color(NSColor.windowBackgroundColor))
        .frame(minWidth: 600, minHeight: 500)
    }
}

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom("JetBrains Mono", size: 13).weight(.medium))
                .foregroundColor(isSelected ? .primary : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? SwiftUI.Color.accentColor.opacity(0.1) : SwiftUI.Color.clear)
        )
    }
}

struct AppearanceSettings: View {
    @ObservedObject var userSettings: UserSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup(title: "Theme") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Appearance")
                            .font(.custom("JetBrains Mono", size: 13))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { userSettings.themeConfiguration.isDarkMode ? 1 : 0 },
                            set: { newValue in
                                userSettings.themeConfiguration.isDarkMode = newValue == 1
                                userSettings.saveSettings()
                            }
                        )) {
                            Text("Light").tag(0)
                            Text("Dark").tag(1)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 120)
                    }
                    
                    HStack {
                        Text("Line Spacing")
                            .font(.custom("JetBrains Mono", size: 13))
                        Spacer()
                        Slider(
                            value: Binding(
                                get: { userSettings.themeConfiguration.lineSpacing },
                                set: { newValue in
                                    userSettings.themeConfiguration.lineSpacing = newValue
                                    userSettings.saveSettings()
                                }
                            ),
                            in: 1.0...2.0,
                            step: 0.1
                        )
                        .frame(width: 100)
                        Text(String(format: "%.1f", userSettings.themeConfiguration.lineSpacing))
                            .font(.custom("JetBrains Mono", size: 11))
                            .foregroundColor(.secondary)
                            .frame(width: 30)
                    }
                    
                    HStack {
                        Text("Accent Color")
                            .font(.custom("JetBrains Mono", size: 13))
                        Spacer()
                        ColorPicker("", selection: Binding(
                            get: { userSettings.themeConfiguration.accentColor.color },
                            set: { newColor in
                                userSettings.themeConfiguration.accentColor = CodableColor(newColor)
                                userSettings.saveSettings()
                            }
                        ))
                        .frame(width: 30)
                    }
                    
                    HStack {
                        Text("Background")
                            .font(.custom("JetBrains Mono", size: 13))
                        Spacer()
                        ColorPicker("", selection: Binding(
                            get: { userSettings.themeConfiguration.backgroundColor.color },
                            set: { newColor in
                                userSettings.themeConfiguration.backgroundColor = CodableColor(newColor)
                                userSettings.saveSettings()
                            }
                        ))
                        .frame(width: 30)
                    }
                }
            }
            
            SettingsGroup(title: "Typography") {
                VStack(alignment: .leading, spacing: 12) {
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
                            .font(.custom("JetBrains Mono", size: 11))
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
                            .font(.custom("JetBrains Mono", size: 11))
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                    }
                    
                    SliderRow(
                        title: "Line Spacing",
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
        }
    }
}

struct TerminalSettings: View {
    @ObservedObject var userSettings: UserSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup(title: "Behavior") {
                VStack(alignment: .leading, spacing: 12) {
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
            
            SettingsGroup(title: "Formatting") {
                VStack(alignment: .leading, spacing: 12) {
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
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.custom("JetBrains Mono", size: 14).weight(.semibold))
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(.leading, 8)
        }
        .background(SwiftUI.Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}


struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                Text("\(Int(value))\(suffix)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            
            Slider(value: $value, in: range, step: step)
                .accentColor(.accentColor)
        }
    }
}


#Preview {
    NativeSettingsView()
        .frame(width: 600, height: 500)
}
