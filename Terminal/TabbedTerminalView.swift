import SwiftUI

struct TabbedTerminalView: View {
    @StateObject private var tabManager = TabManager()
    @State private var showSplitView = false
    @StateObject private var splitPaneManager: SplitPaneManager
    
    init() {
        let initialTab = Tab()
        let manager = SplitPaneManager(initialTab: initialTab)
        self._splitPaneManager = StateObject(wrappedValue: manager)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            TabBarView(
                tabManager: tabManager, 
                splitPaneManager: splitPaneManager,
                onTabSplit: { showSplitView = true }
            )
            
            // Content area - show either single tab or split view
            if showSplitView {
                SplitPaneView(
                    pane: splitPaneManager.rootPane,
                    splitPaneManager: splitPaneManager,
                    tabManager: tabManager
                )
            } else {
                // Show active tab content directly
                if let activeTab = tabManager.activeTab {
                    BlockTerminalView(viewModel: activeTab.viewModel)
                }
            }
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    SwiftUI.Color(red: 0.06, green: 0.07, blue: 0.10),
                    SwiftUI.Color(red: 0.09, green: 0.11, blue: 0.15)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            // Set up keyboard shortcut handling
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "t" {
                    tabManager.createNewTab()
                    return nil
                }
                return event
            }
        }
    }
}

#Preview {
    TabbedTerminalView()
        .frame(width: 1000, height: 700)
}
