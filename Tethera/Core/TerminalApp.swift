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
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 600)
    }
}

// Add NSApplicationDelegate to handle app activation
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Bring the app to front and activate it
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        // Make sure the window comes to front
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            
            // Set window properties for better appearance
            window.backgroundColor = NSColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 1.0)
            // Restrict window dragging to explicit drag areas (e.g., the tab bar)
            window.isMovableByWindowBackground = false
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
