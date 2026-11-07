import AppKit
import SwiftUI

/// About Tethera: the computer, the version, and where things come from.
struct AboutView: View {
    @Environment(\.theme) private var theme

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 0) {
            RetroComputerView(dark: theme.isDark, onKey: { key in
                if key == "return" { NSWorkspace.shared.open(URL(string: "https://tsogbat.github.io/tethera/")!) }
            })
            .frame(height: 250)
            .padding(.top, 18)
            Text("Tethera")
                .font(TypeScale.ui(20, .semibold))
                .foregroundStyle(theme.text.color)
            Text("Version \(version)")
                .font(TypeScale.mono(11))
                .foregroundStyle(theme.text3.color)
                .padding(.top, 3)
            Text("The terminal for your AI agents.")
                .font(TypeScale.ui(13))
                .foregroundStyle(theme.text2.color)
                .padding(.top, 12)
            HStack(spacing: 18) {
                link("Website", "https://tsogbat.github.io/tethera/")
                link("Releases", "https://github.com/Tsogbat/tethera/releases")
                link("Source", "https://github.com/Tsogbat/tethera")
            }
            .padding(.top, 16)
            Text("Geist Mono, IBM Plex Mono and JetBrains Mono under the SIL Open Font License.\nSymbols Nerd Font under the MIT License. SwiftTerm by Miguel de Icaza.")
                .font(TypeScale.ui(10.5))
                .foregroundStyle(theme.text3.color)
                .multilineTextAlignment(.center)
                .padding(.top, 22)
                .padding(.horizontal, 24)
            Spacer(minLength: 18)
        }
        .frame(width: 440, height: 520)
        .background(theme.bg.color)
    }

    private func link(_ title: String, _ url: String) -> some View {
        Button(title) { NSWorkspace.shared.open(URL(string: url)!) }
            .buttonStyle(.plain)
            .font(TypeScale.ui(12, .medium))
            .foregroundStyle(theme.text.color)
            .underline(true, color: theme.hairline.color)
    }
}

@MainActor
enum AboutWindow {
    private static var window: NSWindow?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let store = PreferencesStore.shared
        let host = NSHostingController(rootView: AboutView()
            .environment(\.theme, store.theme)
            .preferredColorScheme(store.isDark ? .dark : .light))
        let window = NSWindow(contentViewController: host)
        window.title = "About Tethera"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = store.theme.bg.nsColor
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Self.window = window
    }
}
