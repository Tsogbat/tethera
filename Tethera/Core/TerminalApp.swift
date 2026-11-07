import SwiftUI
import Combine

/// App-wide commands, sent from menus and buttons, handled by the window.
enum AppCommand: Equatable {
    case newTab
    case closeTab
    case splitRight
    case splitDown
    case nextTab
    case previousTab
    case selectTab(Int)
    case clear
    case palette
    case search
    case toggleAIMode
    case openSettings
    case fontBigger
    case fontSmaller
    case fontReset
    case previousBlock
    case nextBlock
    case copyBlock
    case restartShell
    case interrupt
    case runInNewTab(String)
    case launchAgent(AgentCLI)
    #if DEBUG
    case runInActiveTab(String)
    case debugInsert(String)
    case debugAsk(String)
    case debugGenerate(String)
    case debugSendKeys(String)
    #endif
}

@MainActor
final class AppCommands {
    static let shared = AppCommands()
    let publisher = PassthroughSubject<AppCommand, Never>()

    func send(_ command: AppCommand) {
        publisher.send(command)
    }
}

@main
struct TerminalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var userSettings = UserSettings.shared

    var body: some Scene {
        Window("Tethera", id: "main") {
            TabbedTerminalView()
                .environmentObject(userSettings)
                .frame(minWidth: 640, minHeight: 420)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 720)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { AppCommands.shared.send(.openSettings) }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { AppCommands.shared.send(.newTab) }
                    .keyboardShortcut("t", modifiers: .command)
                Button("Split Right") { AppCommands.shared.send(.splitRight) }
                    .keyboardShortcut("d", modifiers: .command)
                Button("Split Down") { AppCommands.shared.send(.splitDown) }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Divider()
                Button("Close Tab") { AppCommands.shared.send(.closeTab) }
                    .keyboardShortcut("w", modifiers: .command)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Copy Selected Block") { AppCommands.shared.send(.copyBlock) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Clear Blocks") { AppCommands.shared.send(.clear) }
                    .keyboardShortcut("k", modifiers: .command)
            }
            CommandMenu("Terminal") {
                Button("Command Palette") { AppCommands.shared.send(.palette) }
                    .keyboardShortcut("p", modifiers: .command)
                Button("Search History") { AppCommands.shared.send(.search) }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Toggle AI Mode") { AppCommands.shared.send(.toggleAIMode) }
                    .keyboardShortcut("i", modifiers: .command)
                Divider()
                Button("Select Previous Block") { AppCommands.shared.send(.previousBlock) }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Button("Select Next Block") { AppCommands.shared.send(.nextBlock) }
                    .keyboardShortcut(.downArrow, modifiers: .command)
                Divider()
                Button("Interrupt") { AppCommands.shared.send(.interrupt) }
                Button("Restart Shell") { AppCommands.shared.send(.restartShell) }
                Divider()
                Button("Next Tab") { AppCommands.shared.send(.nextTab) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Tab") { AppCommands.shared.send(.previousTab) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                ForEach(1..<10) { number in
                    Button("Tab \(number)") { AppCommands.shared.send(.selectTab(number)) }
                        .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                }
            }
            CommandGroup(after: .toolbar) {
                Button("Bigger") { AppCommands.shared.send(.fontBigger) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Smaller") { AppCommands.shared.send(.fontSmaller) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { AppCommands.shared.send(.fontReset) }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
            }
        }
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        FontLoader.shared.registerBundledFonts()
        _ = ShellEnvironment.shared
        _ = AgentDetector.shared
        _ = CommandHistoryManager.shared

        // `swift run` has no bundle icon; show the real one in the Dock.
        if let icon = BrandAssets.appIcon {
            NSApp.applicationIconImage = icon
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        #if DEBUG
        MainActor.assumeIsolated { DebugHooks.runIfRequested() }
        #endif

        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.configureWindows() }
        }
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResizeNotification,
                     NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let window = note.object as? NSWindow else { return }
                MainActor.assumeIsolated {
                    // Popovers, tooltips and menus post these too; they have no traffic lights.
                    guard AppDelegate.isMainWindow(window) else { return }
                    if name == NSWindow.didBecomeKeyNotification { self?.configure(window) }
                    WindowMetrics.shared.update(from: window)
                }
            })
        }
    }

    /// The terminal window: titled, not a panel. Popover and tooltip windows are untitled.
    @MainActor
    static func isMainWindow(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled) && !(window is NSPanel)
            && (window.identifier?.rawValue.contains("main") ?? true)
    }

    @MainActor
    private func configureWindows() {
        for window in NSApp.windows where window.isVisible && Self.isMainWindow(window) {
            configure(window)
        }
    }

    @MainActor
    private func configure(_ window: NSWindow) {
        guard Self.isMainWindow(window) else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarSeparatorStyle = .none
        if window.toolbar == nil {
            // An empty compact toolbar gives the title bar the height of the tab strip
            // and centers the traffic lights in it.
            let toolbar = NSToolbar(identifier: "tethera.titlebar")
            toolbar.showsBaselineSeparator = false
            window.toolbar = toolbar
            window.toolbarStyle = .unifiedCompact
        }
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 640, height: 420)
        WindowMetrics.shared.update(from: window)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            CommandHistoryManager.shared.saveNow()
        }
    }
}
