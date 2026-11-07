import SwiftUI
import TetheraKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "textformat") }
            AgentSettings().tabItem { Label("Agents", systemImage: "point.3.connected.trianglepath.dotted") }
            ShortcutSettings().tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 560, height: 460)
    }
}

private struct GeneralSettings: View {
    @ObservedObject private var store = PreferencesStore.shared

    var body: some View {
        Form {
            Section {
                Picker("Shell", selection: Binding(
                    get: { store.value.shell ?? "" },
                    set: { store.value.shell = $0.isEmpty ? nil : $0 })) {
                    Text("Login shell (\((ShellLaunch.loginShell as NSString).lastPathComponent))").tag("")
                    ForEach(["/bin/zsh", "/bin/bash", "/opt/homebrew/bin/fish", "/opt/homebrew/bin/bash"].filter { FileManager.default.isExecutableFile(atPath: $0) }, id: \.self) {
                        Text($0).tag($0)
                    }
                }
                LabeledContent("New sessions start in") {
                    HStack {
                        Text(store.value.startDirectory.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "the current session’s folder, or ~")
                            .foregroundStyle(.secondary)
                        Button("Choose…") { chooseFolder() }
                        if store.value.startDirectory != nil { Button("Reset") { store.value.startDirectory = nil } }
                    }
                }
                HStack {
                    Text("Shell startup files")
                    Spacer()
                    Button("Open .zshrc") { open("~/.zshrc") }
                    Button("Open .bashrc") { open("~/.bashrc") }
                }
            } footer: {
                Text("Your shell runs exactly as configured. Tethera adds prompt marks through a separate script; it never edits your startup files.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Notify me when an agent needs me or finishes", isOn: $store.value.notifyWhenAgentsNeedYou)
            } footer: {
                Text("Sessions keep running when you quit Tethera (⌘Q). To stop them all, use Quit and End All Sessions (⌥⌘Q).")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK { store.value.startDirectory = panel.url?.path }
    }

    private func open(_ path: String) {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        NSWorkspace.shared.open(url)
    }
}

private struct AppearanceSettings: View {
    @ObservedObject private var store = PreferencesStore.shared
    @State private var families = FontLoader.monospacedFamilies

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $store.value.appearance) {
                    ForEach(Preferences.Appearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Terminal colors", selection: $store.value.terminalPalette) {
                    Text("Match appearance (Graphite / Paper)").tag("auto")
                    Divider()
                    ForEach(TerminalPalette.named, id: \.id) { Text($0.name).tag($0.id) }
                }
            }
            Section {
                Picker("Font", selection: $store.value.fontFamily) {
                    ForEach(FontLoader.bundledFamilies, id: \.self) { Text($0).tag($0) }
                    Divider()
                    ForEach(families.filter { !FontLoader.bundledFamilies.contains($0) }, id: \.self) { Text($0).tag($0) }
                }
                Stepper(value: $store.value.fontSize, in: 9...28, step: 1) {
                    LabeledContent("Size", value: "\(Int(store.value.fontSize)) pt")
                }
                Picker("Cursor", selection: $store.value.cursor) {
                    ForEach(Preferences.Cursor.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Blinking cursor", isOn: $store.value.cursorBlink)
                Toggle("Use Option as Meta key", isOn: $store.value.optionAsMeta)
                Toggle("GPU rendering (Metal)", isOn: $store.value.useMetal)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutSettings: View {
    private let shortcuts: [(String, String)] = [
        ("⌘T", "New shell session"), ("⌘K  ⌘P", "Command palette"), ("⇧⌘A", "Agents overview"),
        ("⇧⌘U", "Go to the session that needs you"), ("⌘]  ⌘[", "Next / previous session"), ("⌘1 … ⌘9", "Session by position"),
        ("⌘D  ⇧⌘D", "Split right / down"), ("⌘W", "Close pane (the session keeps running)"),
        ("⌥⌘W", "End session"), ("⇧⌘R", "Rename session"), ("⌥⌘I", "Inspector"),
        ("⌘+  ⌘-  ⌘0", "Font size"), ("⌘Q", "Quit — sessions keep running"), ("⌥⌘Q", "Quit and end all sessions"),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(shortcuts, id: \.0) { keys, action in
                    LabeledContent(action) { Text(keys).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary) }
                }
            }
        }
        .formStyle(.grouped)
    }
}
