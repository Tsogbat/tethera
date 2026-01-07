import SwiftUI

@main
struct TerminalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var userSettings = UserSettings()
    
    var body: some Scene {
        WindowGroup {
            TabbedTerminalView()
                .environmentObject(userSettings)
        }
        // Don't hide title bar - we need traffic lights visible
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NotificationCenter.default.post(name: .openSettingsTab, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            
            // Search menu
            CommandGroup(after: .textEditing) {
                Button("Search History...") {
                    Task { @MainActor in
                        CommandHistoryManager.shared.openSearch()
                    }
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 960, height: 640)
    }
}

// MARK: - App Delegate for window configuration
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.configureWindow()
        }
    }
    
    private func configureWindow() {
        guard let window = NSApp.windows.first else { return }
        
        window.makeKeyAndOrderFront(nil)
        
        // Make titlebar transparent so tabs blend with it
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1.0)
        
        // Allow content to extend into titlebar area
        window.styleMask.insert(.fullSizeContentView)
        
        window.minSize = NSSize(width: 600, height: 400)
        window.isMovableByWindowBackground = false
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
