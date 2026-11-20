import AppKit
import SwiftUI

/// A shortcut you can change in Settings → Shortcuts.
struct KeyBinding: Codable, Equatable, Hashable {
    var key: String
    var command = true
    var shift = false
    var option = false
    var control = false

    var modifiers: EventModifiers {
        var set: EventModifiers = []
        if command { set.insert(.command) }
        if shift { set.insert(.shift) }
        if option { set.insert(.option) }
        if control { set.insert(.control) }
        return set
    }

    var shortcut: KeyboardShortcut? {
        guard let character = key.lowercased().first else { return nil }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
    }

    /// "⌥⌘A", in the order macOS menus use.
    var display: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + key.uppercased()
    }

    /// From a key press, if it has a modifier and a printable key.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let characters = event.charactersIgnoringModifiers?.lowercased(), characters.count == 1,
              let scalar = characters.unicodeScalars.first, scalar.value >= 0x20, scalar.value < 0x7F,
              !flags.intersection([.command, .control, .option]).isEmpty else { return nil }
        key = characters
        command = flags.contains(.command)
        shift = flags.contains(.shift)
        option = flags.contains(.option)
        control = flags.contains(.control)
    }

    init(_ key: String, command: Bool = true, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.key = key
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }
}

/// Every command whose shortcut you can change, with its default.
enum KeyBindings {
    struct Command: Identifiable {
        let id: String
        let title: String
        let binding: KeyBinding
    }

    static let commands: [Command] = [
        Command(id: "newShell", title: "New shell session", binding: KeyBinding("t")),
        Command(id: "palette", title: "Command palette", binding: KeyBinding("k")),
        Command(id: "home", title: "Home", binding: KeyBinding("h", shift: true)),
        Command(id: "overview", title: "Agents overview", binding: KeyBinding("a", shift: true)),
        Command(id: "approvals", title: "Approvals", binding: KeyBinding("a", option: true)),
        Command(id: "needsYou", title: "Go to the session that needs you", binding: KeyBinding("u", shift: true)),
        Command(id: "splitRight", title: "Split right", binding: KeyBinding("d")),
        Command(id: "splitDown", title: "Split down", binding: KeyBinding("d", shift: true)),
        Command(id: "openFile", title: "Open file", binding: KeyBinding("o")),
        Command(id: "folder", title: "New shell in a folder", binding: KeyBinding("o", shift: true)),
        Command(id: "browser", title: "New browser tab", binding: KeyBinding("l")),
        Command(id: "changes", title: "Changes", binding: KeyBinding("e", shift: true)),
        Command(id: "transcript", title: "Transcript", binding: KeyBinding("t", option: true)),
        Command(id: "git", title: "Git", binding: KeyBinding("g", option: true)),
        Command(id: "brew", title: "Homebrew", binding: KeyBinding("b", option: true)),
        Command(id: "inspector", title: "Inspector", binding: KeyBinding("i", option: true)),
        Command(id: "rename", title: "Rename session", binding: KeyBinding("r", shift: true)),
    ]

    @MainActor
    static func binding(_ id: String) -> KeyBinding? {
        PreferencesStore.shared.value.keyBindings[id] ?? commands.first { $0.id == id }?.binding
    }

    @MainActor
    static func shortcut(_ id: String) -> KeyboardShortcut? {
        binding(id)?.shortcut
    }

    /// The other command already using a binding, if any.
    @MainActor
    static func conflict(for binding: KeyBinding, excluding id: String) -> Command? {
        commands.first { $0.id != id && self.binding($0.id) == binding }
    }
}

/// Settings → Shortcuts: click a shortcut, press the new one.
struct ShortcutRecorder: View {
    let command: KeyBindings.Command
    @ObservedObject private var store = PreferencesStore.shared
    @State private var recording = false
    @State private var monitor: Any?
    @State private var conflict: String?

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if let conflict {
                    Text("Used by \(conflict)").font(.caption).foregroundStyle(.secondary)
                }
                Button(recording ? "Press keys…" : (KeyBindings.binding(command.id)?.display ?? "None")) {
                    recording ? stop() : start()
                }
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 96)
                if store.value.keyBindings[command.id] != nil {
                    Button("Reset") {
                        store.value.keyBindings[command.id] = nil
                        conflict = nil
                    }
                    .controlSize(.small)
                }
            }
        } label: {
            Text(command.title)
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        conflict = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }  // Escape cancels.
            guard let binding = KeyBinding(event: event) else { return nil }
            if let other = KeyBindings.conflict(for: binding, excluding: command.id) {
                conflict = other.title
            } else {
                store.value.keyBindings[command.id] = binding == command.binding ? nil : binding
            }
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
