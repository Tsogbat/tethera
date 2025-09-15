import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// Resolve naming conflicts
typealias SwiftUIColor = SwiftUI.Color

struct SettingsView: View {
    @ObservedObject var userSettings: UserSettings
    @State private var selectedColorPreset: String = "Blue"
    @State private var showingColorPicker = false
    @State private var activeColorType: ColorType = .primary
    
    enum ColorType: String, CaseIterable {
        case primary = "Primary"
        case secondary = "Secondary"
        case background = "Background"
        case accent = "Accent"
        case text = "Text"
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                themeSection
                colorCustomizationSection
                fontSection
                developerSection
                actionsSection
            }
            .padding(24)
        }
        .background(userSettings.themeConfiguration.backgroundColor.color)
        .foregroundColor(userSettings.themeConfiguration.textColor.color)
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Customize your terminal experience")
                .font(.subheadline)
                .opacity(0.7)
        }
    }
    
    // MARK: - Theme Section
    private var themeSection: some View {
        SettingsSection(title: "Theme & Appearance", icon: "paintbrush.fill") {
            VStack(spacing: 16) {
                // Dark/Light Mode Toggle
                HStack {
                    Text("Dark Mode")
                        .font(.body)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { userSettings.themeConfiguration.isDarkMode },
                        set: { newValue in
                            userSettings.themeConfiguration.isDarkMode = newValue
                            if newValue {
                                userSettings.applyDarkTheme()
                            } else {
                                userSettings.applyLightTheme()
                            }
                        }
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: userSettings.themeConfiguration.accentColor.color))
                }
                
                Divider()
                
                // Theme Presets
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Themes")
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        ThemePresetButton(
                            title: "Dark",
                            colors: [.black, .gray, .blue],
                            isSelected: userSettings.themeConfiguration.isDarkMode
                        ) {
                            userSettings.applyDarkTheme()
                        }
                        
                        ThemePresetButton(
                            title: "Light",
                            colors: [.white, .gray, .blue],
                            isSelected: !userSettings.themeConfiguration.isDarkMode
                        ) {
                            userSettings.applyLightTheme()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Color Customization Section
    private var colorCustomizationSection: some View {
        SettingsSection(title: "Color Customization", icon: "eyedropper.halffull") {
            VStack(spacing: 16) {
                ForEach(ColorType.allCases, id: \.self) { colorType in
                    ColorCustomizationRow(
                        colorType: colorType,
                        currentColor: getCurrentColor(for: colorType),
                        userSettings: userSettings
                    )
                }
                
                Divider()
                
                // Color Presets
                VStack(alignment: .leading, spacing: 12) {
                    Text("Color Presets")
                        .font(.headline)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                        ForEach(UserSettings.colorPresets, id: \.0) { preset in
                            ColorPresetButton(
                                name: preset.0,
                                color: preset.1,
                                isSelected: selectedColorPreset == preset.0
                            ) {
                                selectedColorPreset = preset.0
                                applyColorPreset(preset.1)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Font Section
    private var fontSection: some View {
        SettingsSection(title: "Typography", icon: "textformat") {
            VStack(spacing: 16) {
                // Font Family
                HStack {
                    Text("Font Family")
                        .font(.body)
                    Spacer()
                    Picker("Font", selection: Binding(
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
                }
                
                // Font Size
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Font Size")
                        Spacer()
                        Text("\(Int(userSettings.themeConfiguration.fontSize))pt")
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { userSettings.themeConfiguration.fontSize },
                            set: { newValue in
                                userSettings.themeConfiguration.fontSize = newValue
                                userSettings.saveSettings()
                            }
                        ),
                        in: 10...24,
                        step: 1
                    )
                    .accentColor(userSettings.themeConfiguration.accentColor.color)
                }
                
                // Line Spacing
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Line Spacing")
                        Spacer()
                        Text(String(format: "%.1f", userSettings.themeConfiguration.lineSpacing))
                            .foregroundColor(.secondary)
                    }
                    
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
                    .accentColor(userSettings.themeConfiguration.accentColor.color)
                }
                
                // Padding
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Padding")
                        Spacer()
                        Text("\(Int(userSettings.themeConfiguration.padding))px")
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { userSettings.themeConfiguration.padding },
                            set: { newValue in
                                userSettings.themeConfiguration.padding = newValue
                                userSettings.saveSettings()
                            }
                        ),
                        in: 4...20,
                        step: 2
                    )
                    .accentColor(userSettings.themeConfiguration.accentColor.color)
                }
            }
        }
    }
    
    // MARK: - Developer Section
    private var developerSection: some View {
        SettingsSection(title: "Developer Preferences", icon: "hammer.fill") {
            VStack(spacing: 16) {
                ToggleRow(
                    title: "Autocompletion",
                    description: "Enable intelligent command and path completion",
                    isOn: Binding(
                        get: { userSettings.developerSettings.autocompletionEnabled },
                        set: { newValue in
                            userSettings.developerSettings.autocompletionEnabled = newValue
                            userSettings.saveSettings()
                        }
                    ),
                    accentColor: userSettings.themeConfiguration.accentColor.color
                )
                
                ToggleRow(
                    title: "Line Numbers",
                    description: "Show line numbers in terminal output",
                    isOn: Binding(
                        get: { userSettings.developerSettings.showLineNumbers },
                        set: { newValue in
                            userSettings.developerSettings.showLineNumbers = newValue
                            userSettings.saveSettings()
                        }
                    ),
                    accentColor: userSettings.themeConfiguration.accentColor.color
                )
                
                ToggleRow(
                    title: "Syntax Highlighting",
                    description: "Highlight syntax in supported file types",
                    isOn: Binding(
                        get: { userSettings.developerSettings.syntaxHighlighting },
                        set: { newValue in
                            userSettings.developerSettings.syntaxHighlighting = newValue
                            userSettings.saveSettings()
                        }
                    ),
                    accentColor: userSettings.themeConfiguration.accentColor.color
                )
                
                ToggleRow(
                    title: "Auto Indent",
                    description: "Automatically indent new lines",
                    isOn: Binding(
                        get: { userSettings.developerSettings.autoIndent },
                        set: { newValue in
                            userSettings.developerSettings.autoIndent = newValue
                            userSettings.saveSettings()
                        }
                    ),
                    accentColor: userSettings.themeConfiguration.accentColor.color
                )
                
                ToggleRow(
                    title: "Word Wrap",
                    description: "Wrap long lines to fit the terminal width",
                    isOn: Binding(
                        get: { userSettings.developerSettings.wordWrap },
                        set: { newValue in
                            userSettings.developerSettings.wordWrap = newValue
                            userSettings.saveSettings()
                        }
                    ),
                    accentColor: userSettings.themeConfiguration.accentColor.color
                )
                
                // Tab Size
                HStack {
                    VStack(alignment: .leading) {
                        Text("Tab Size")
                            .font(.body)
                        Text("Number of spaces per tab")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker("Tab Size", selection: Binding(
                        get: { userSettings.developerSettings.tabSize },
                        set: { newValue in
                            userSettings.developerSettings.tabSize = newValue
                            userSettings.saveSettings()
                        }
                    )) {
                        ForEach([2, 4, 8], id: \.self) { size in
                            Text("\(size)").tag(size)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 120)
                }
            }
        }
    }
    
    // MARK: - Actions Section
    private var actionsSection: some View {
        SettingsSection(title: "Actions", icon: "gear") {
            VStack(spacing: 12) {
                Button("Reset to Defaults") {
                    userSettings.resetToDefaults()
                }
                .buttonStyle(ActionButtonStyle(
                    backgroundColor: userSettings.themeConfiguration.secondaryColor.color,
                    foregroundColor: userSettings.themeConfiguration.textColor.color
                ))
                
                Button("Export Settings") {
                    // TODO: Implement settings export
                }
                .buttonStyle(ActionButtonStyle(
                    backgroundColor: userSettings.themeConfiguration.accentColor.color,
                    foregroundColor: .white
                ))
            }
        }
    }
    
    // MARK: - Helper Methods
    private func getCurrentColor(for colorType: ColorType) -> SwiftUIColor {
        switch colorType {
        case .primary:
            return userSettings.themeConfiguration.primaryColor.color
        case .secondary:
            return userSettings.themeConfiguration.secondaryColor.color
        case .background:
            return userSettings.themeConfiguration.backgroundColor.color
        case .accent:
            return userSettings.themeConfiguration.accentColor.color
        case .text:
            return userSettings.themeConfiguration.textColor.color
        }
    }
    
    private func applyColorPreset(_ color: SwiftUIColor) {
        userSettings.themeConfiguration.primaryColor = CodableColor(color)
        userSettings.themeConfiguration.accentColor = CodableColor(color)
        userSettings.saveSettings()
    }
}

// MARK: - Supporting Views
struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            content
        }
        .padding(20)
        .background(SwiftUIColor.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

struct ToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    let accentColor: SwiftUIColor
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: accentColor))
        }
    }
}

struct ColorCustomizationRow: View {
    let colorType: SettingsView.ColorType
    let currentColor: SwiftUIColor
    @ObservedObject var userSettings: UserSettings
    @State private var showingColorPicker = false
    
    var body: some View {
        HStack {
            Text(colorType.rawValue)
                .font(.body)
            Spacer()
            Button(action: { showingColorPicker = true }) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(currentColor)
                    .frame(width: 40, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(SwiftUIColor.primary.opacity(0.2), lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .sheet(isPresented: $showingColorPicker) {
            ColorPicker("Select \(colorType.rawValue) Color", selection: Binding(
                get: { currentColor },
                set: { newColor in
                    updateColor(newColor)
                }
            ))
            .padding()
        }
    }
    
    private func updateColor(_ color: SwiftUIColor) {
        switch colorType {
        case .primary:
            userSettings.themeConfiguration.primaryColor = CodableColor(color)
        case .secondary:
            userSettings.themeConfiguration.secondaryColor = CodableColor(color)
        case .background:
            userSettings.themeConfiguration.backgroundColor = CodableColor(color)
        case .accent:
            userSettings.themeConfiguration.accentColor = CodableColor(color)
        case .text:
            userSettings.themeConfiguration.textColor = CodableColor(color)
        }
        userSettings.saveSettings()
    }
}

struct ThemePresetButton: View {
    let title: String
    let colors: [SwiftUIColor]
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                HStack(spacing: 2) {
                    ForEach(colors.indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(colors[index])
                            .frame(height: 20)
                    }
                }
                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(8)
            .background(isSelected ? SwiftUIColor.blue.opacity(0.2) : SwiftUIColor.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? SwiftUIColor.blue : SwiftUIColor.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ColorPresetButton: View {
    let name: String
    let color: SwiftUIColor
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? SwiftUIColor.white : SwiftUIColor.clear, lineWidth: 2)
                    )
                Text(name)
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ActionButtonStyle: ButtonStyle {
    let backgroundColor: SwiftUIColor
    let foregroundColor: SwiftUIColor
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    SettingsView(userSettings: UserSettings())
        .frame(width: 600, height: 800)
}
