#if DEBUG
import AppKit
import TetheraKit

/// Scripted runs and window captures for development (Debug builds only).
///
///     TETHERA_SNAPSHOT_DIR=… TETHERA_SCRIPT='ls -G;;@wait:1;;@shot:main;;@quit' .build/debug/Tethera
///
/// Steps: a shell line (typed into the focused session with ↩), `@type:<text>`, `@keys:<text>`
/// (`\e`, `\r`, `\x03` escapes), `@new`, `@agent:<kind>`, `@split`, `@select:<n>`, `@palette`,
/// `@overview`, `@inspector`, `@close`, `@home`, `@about` (captures about.png), `@appearance:<dark|light>`, `@wait:<sec>`, `@shot:<name>`, `@quit`.
@MainActor
enum DebugHooks {
    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["TETHERA_SNAPSHOT_DIR"] else { return }
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let steps = (env["TETHERA_SCRIPT"] ?? "@wait:3;;@shot:window").components(separatedBy: ";;")
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            for step in steps { await run(step.trimmingCharacters(in: .whitespaces), directory: directory) }
        }
    }

    private static func run(_ step: String, directory: String) async {
        let workspace = Workspace.shared
        let client = DaemonClient.shared
        func type(_ text: String) {
            guard let id = workspace.focusedSessionID else { return }
            client.send(id, Data(text.utf8))
        }
        if step.hasPrefix("@wait:") {
            try? await Task.sleep(nanoseconds: UInt64((Double(step.dropFirst(6)) ?? 1) * 1e9))
        } else if step.hasPrefix("@shot:") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.isVisible && !($0 is NSPanel) }?.makeKeyAndOrderFront(nil)
            try? await Task.sleep(nanoseconds: 600_000_000)
            snapshot(name: String(step.dropFirst(6)), directory: directory)
        } else if step == "@new" {
            workspace.newSession()
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        } else if step.hasPrefix("@agent:") {
            if let kind = AgentKind(rawValue: String(step.dropFirst(7))) { workspace.newSession(agent: kind) }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        } else if step == "@split" {
            workspace.split(.horizontal)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        } else if step.hasPrefix("@select:") {
            workspace.show(index: Int(step.dropFirst(8)) ?? 0)
        } else if step.hasPrefix("@rename:") {
            if let id = workspace.focusedSessionID { client.rename(id, to: String(step.dropFirst(8))) }
        } else if step.hasPrefix("@splitwith:") {
            let sessions = client.sessions
            if let index = Int(step.dropFirst(11)), sessions.indices.contains(index) {
                workspace.axis = .horizontal
                let pane = Workspace.Pane(content: .session(sessions[index].id))
                workspace.panes.append(pane)
                workspace.focus(pane: pane.id)
            }
        } else if step == "@home" {
            workspace.showHome()
            try? await Task.sleep(nanoseconds: 800_000_000)
        } else if step == "@about" {
            AboutWindow.show()
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if let window = NSApp.windows.first(where: { $0.title == "About Tethera" }) {
                capture(window, name: "about", directory: directory)
            }
        } else if step == "@palette" {
            workspace.showPalette = true
        } else if step == "@overview" {
            workspace.showOverview = true
        } else if step == "@inspector" {
            PreferencesStore.shared.value.showInspector.toggle()
        } else if step == "@close" {
            workspace.showPalette = false
            workspace.showOverview = false
        } else if step.hasPrefix("@appearance:") {
            PreferencesStore.shared.value.appearance = step.hasSuffix("light") ? .light : .dark
        } else if step.hasPrefix("@type:") {
            type(String(step.dropFirst(6)))
        } else if step.hasPrefix("@keys:") {
            type(String(step.dropFirst(6))
                .replacingOccurrences(of: "\\e", with: "\u{1b}")
                .replacingOccurrences(of: "\\r", with: "\r")
                .replacingOccurrences(of: "\\x03", with: "\u{03}"))
        } else if step.hasPrefix("@settings") {
            SettingsOpener.open()
            try? await Task.sleep(nanoseconds: 900_000_000)
            if let tab = step.split(separator: ":").dropFirst().first, let window = NSApp.keyWindow,
               let toolbar = window.toolbar, let item = toolbar.items.first(where: { $0.label == String(tab) }) {
                window.toolbar?.selectedItemIdentifier = item.itemIdentifier
                _ = item.target.map { NSApp.sendAction(item.action!, to: $0, from: item) }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        } else if step.hasPrefix("@shotkey:") {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if let window = NSApp.keyWindow { capture(window, name: String(step.dropFirst(9)), directory: directory) }
        } else if step == "@quit" {
            NSApp.terminate(nil)
        } else if !step.isEmpty {
            // Tethera opens to Home; a script's first shell line gets a session to type into.
            if workspace.focusedSessionID == nil {
                workspace.newSession()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            type(step + "\r")
            try? await Task.sleep(nanoseconds: 700_000_000)
        }
    }

    /// Captures the window with materials and shadow. `CGWindowListCreateImage` is hidden from
    /// Swift in the current SDK but still works for the app's own windows without permission.
    static func snapshot(name: String, directory: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) && $0.styleMask.contains(.titled) && $0.title != "Settings" && !$0.title.hasSuffix("Settings") }) else { return }
        capture(window, name: name, directory: directory)
    }

    static func capture(_ window: NSWindow, name: String, directory: String) {
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let handle = dlopen(nil, RTLD_NOW), let symbol = dlsym(handle, "CGWindowListCreateImage") else { return }
        let capture = unsafeBitCast(symbol, to: Capture.self)
        guard let image = capture(.null, 1 << 3, UInt32(window.windowNumber), 1 << 3)?.takeRetainedValue(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? data.write(to: url)
        print("[DebugHooks] wrote \(url.path)")
    }
}
#endif
