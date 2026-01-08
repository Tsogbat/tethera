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
        .windowStyle(HiddenTitleBarWindowStyle())
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
        // Load fonts once at startup (not in each ViewModel)
        FontLoader.shared.loadJetBrainsMono()
        
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.configureWindow()
        }
    }
    
    private func configureWindow() {
        guard let window = NSApp.windows.first else { return }
        
        window.makeKeyAndOrderFront(nil)
        
        // Full transparent title bar - no text, no background
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "" // Remove title text completely
        
        // Make titlebar separator invisible
        window.titlebarSeparatorStyle = .none
        
        // Allow full content under title bar
        window.styleMask.insert(.fullSizeContentView)
        
        // Keep traffic lights visible
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
        
        window.minSize = NSSize(width: 600, height: 400)
        window.isMovableByWindowBackground = false
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
