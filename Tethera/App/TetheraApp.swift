import AppKit
import SwiftUI
import TetheraKit
import UserNotifications

@main
struct TetheraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Tethera", id: "main") {
            RootView()
                .frame(minWidth: 760, minHeight: 440)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 780)
        .commands { TetheraCommands() }

        Settings {
            SettingsView()
                .preferredColorScheme(PreferencesStore.shared.isDark ? .dark : .light)
        }
    }
}

struct TetheraCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Shell") { Workspace.shared.newSession() }
                .keyboardShortcut("t", modifiers: .command)
            Menu("New Agent Session") {
                ForEach(Array(AgentDetector.launchable.filter { $0 != .ollama }.enumerated()), id: \.element) { index, kind in
                    if index < 4 {
                        Button(kind.displayName) { Workspace.shared.newSession(agent: kind) }
                            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command, .option])
                    } else {
                        Button(kind.displayName) { Workspace.shared.newSession(agent: kind) }
                    }
                }
            }
            Button("New Shell in Folder…") { SessionActions.newSessionInChosenFolder() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Split Right") { Workspace.shared.split(.horizontal) }
                .keyboardShortcut("d", modifiers: .command)
            Button("Split Down") { Workspace.shared.split(.vertical) }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Divider()
            Button("Close Pane") { closePaneOrWindow() }
                .keyboardShortcut("w", modifiers: .command)
            Button("End Session…") {
                if let session = Workspace.shared.focusedSession { SessionActions.confirmEnd(session) }
            }
            .keyboardShortcut("w", modifiers: [.command, .option])
        }
        CommandGroup(replacing: .appTermination) {
            Button("Quit Tethera") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
            Button("Quit and End All Sessions") { AppDelegate.quitEndingSessions() }
                .keyboardShortcut("q", modifiers: [.command, .option])
        }
        CommandGroup(replacing: .appInfo) {
            Button("About Tethera") { AboutWindow.show() }
        }
        CommandMenu("Session") {
            Button("Home") { Workspace.shared.showHome() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Button("Command Palette") { Workspace.shared.showPalette.toggle() }
                .keyboardShortcut("k", modifiers: .command)
            Button("Command Palette") { Workspace.shared.showPalette.toggle() }
                .keyboardShortcut("p", modifiers: .command)
            Button("Agents Overview") { Workspace.shared.showOverview.toggle() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Button("Go to Session That Needs You") { Workspace.shared.jumpToNeedsYou() }
                .keyboardShortcut("u", modifiers: [.command, .shift])
            Divider()
            Button("Next Session") { Workspace.shared.cycle(1) }
                .keyboardShortcut("]", modifiers: .command)
            Button("Previous Session") { Workspace.shared.cycle(-1) }
                .keyboardShortcut("[", modifiers: .command)
            ForEach(1..<10) { number in
                Button("Session \(number)") { Workspace.shared.show(index: number - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
            }
            Divider()
            Button("Rename Session…") { Workspace.shared.renaming = Workspace.shared.focusedSessionID }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Interrupt") {
                if let id = Workspace.shared.focusedSessionID { DaemonClient.shared.interrupt(id) }
            }
        }
        CommandGroup(after: .sidebar) {
            Button("Toggle Inspector") { PreferencesStore.shared.value.showInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Divider()
            Button("Bigger") { PreferencesStore.shared.adjustFontSize(by: 1) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Smaller") { PreferencesStore.shared.adjustFontSize(by: -1) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { PreferencesStore.shared.value.fontSize = Preferences().fontSize }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
        }
    }

    @MainActor
    private func closePaneOrWindow() {
        if Workspace.shared.panes.count > 1 {
            Workspace.shared.closeFocusedPane()
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            FontLoader.registerBundledFonts()
            _ = ShellEnvironment.shared
            _ = AgentDetector.shared
            if let icon = BrandAssets.appIcon { NSApp.applicationIconImage = icon }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            if FileManager.default.fileExists(atPath: AgentIntegrations.cliLink.path) {
                AgentIntegrations.refreshCLILink(to: DaemonClient.cliPath)
            }
            let client = DaemonClient.shared
            client.onUpdate = { [weak self] session, previous in self?.notifyIfNeeded(session, previous: previous) }
            client.connect()
            if Self.canNotify {
                UNUserNotificationCenter.current().delegate = self
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            }
            #if DEBUG
            DebugHooks.runIfRequested()
            #endif
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { Self.configure(window) }
        })
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Sessions live in the daemon; closing the window doesn't end them.
        true
    }

    /// Ends every session and stops the daemon, then quits.
    @MainActor
    static func quitEndingSessions() {
        let alert = NSAlert()
        let count = DaemonClient.shared.sessions.count
        alert.messageText = "End all \(count) session\(count == 1 ? "" : "s") and quit?"
        alert.informativeText = "Running programs and agents in every session will be stopped."
        alert.addButton(withTitle: "End Sessions and Quit")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        DaemonClient.shared.shutdownDaemon()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
    }

    @MainActor
    private static func configure(_ window: NSWindow) {
        guard window.styleMask.contains(.titled), !(window is NSPanel), window.identifier?.rawValue.contains("main") ?? true else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        window.backgroundColor = PreferencesStore.shared.theme.bg.nsColor
        window.tabbingMode = .disallowed
    }

    // MARK: Attention

    /// Notifications need a bundle identifier, which `swift run` builds don't have.
    private static var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    @MainActor
    private func notifyIfNeeded(_ session: SessionInfo, previous: SessionInfo?) {
        updateDockBadge()
        guard let previous, PreferencesStore.shared.value.notifyWhenAgentsNeedYou else { return }
        let visible = NSApp.isActive && Workspace.shared.panes.contains { $0.session == session.id }
        guard !visible else { return }

        let old = previous.agent?.state, new = session.agent?.state
        var body: String?
        if new == .needsInput && old != .needsInput {
            body = session.agent?.message ?? "\(session.agent?.kind.displayName ?? "The agent") is waiting for you."
        } else if (new == .done || (new == .idle && session.agent?.unseen == true)) && old == .working {
            body = "\(session.agent?.kind.displayName ?? "The agent") finished."
        } else if new == .error && old != .error {
            body = session.agent?.message ?? "\(session.agent?.kind.displayName ?? "The agent") hit an error."
        } else if session.attention > previous.attention, let text = session.lastNotification {
            body = text
        }
        guard let body else { return }
        if Self.canNotify {
            let content = UNMutableNotificationContent()
            content.title = session.name
            content.body = body
            content.userInfo = ["session": session.id.uuidString]
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        } else {
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    @MainActor
    private func updateDockBadge() {
        let waiting = DaemonClient.shared.sessions.filter(\.needsYou).count
        NSApp.dockTile.badgeLabel = waiting > 0 ? "\(waiting)" : nil
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo["session"] as? String, let id = UUID(uuidString: raw) else { return }
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            Workspace.shared.show(id)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

enum BrandAssets {
    static let appIcon: NSImage? = {
        guard let url = Bundle.tethera.url(forResource: "AppIcon", withExtension: "png", subdirectory: "Brand") else { return nil }
        return NSImage(contentsOf: url)
    }()
}
