import Foundation
import SwiftUI

/// Manages the split pane layout and operations
@MainActor
class SplitPaneManager: ObservableObject {
    @Published var rootPane: SplitPane
    @Published var draggedTab: Tab?
    @Published var dropTarget: SplitPane?
    @Published var dropOrientation: SplitOrientation = .horizontal
    @Published var activePane: SplitPane?
    @Published var isSplit: Bool = false
    
    init(initialTab: Tab) {
        self.rootPane = SplitPane(tab: initialTab)
        self.activePane = self.rootPane
        self.isSplit = false
        
        // Listen for tab closure notifications
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TabClosed"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let tabId = notification.userInfo?["tabId"] as? UUID {
                Task { @MainActor in
                    self?.handleTabClosure(tabId)
                }
            }
        }
    }
    
    /// Find a pane containing the specified tab
    func findPane(containing tab: Tab) -> SplitPane? {
        return findPane(in: rootPane, containing: tab)
    }
    
    private func findPane(in pane: SplitPane, containing tab: Tab) -> SplitPane? {
        if pane.tab?.id == tab.id {
            return pane
        }
        
        for child in pane.children {
            if let found = findPane(in: child, containing: tab) {
                return found
            }
        }
        
        return nil
    }
    
    /// Split a pane with a new tab
    func splitPane(_ pane: SplitPane, with tab: Tab, orientation: SplitOrientation) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9, blendDuration: 0.1)) {
            pane.split(with: tab, orientation: orientation)
            isSplit = rootPane.children.count > 0
        }
    }
    
    /// Remove a tab from the pane system
    func removeTab(_ tab: Tab) {
        guard let pane = findPane(containing: tab) else { return }
        
        if pane == rootPane && pane.isLeaf {
            // Don't remove the root pane if it's the only one
            return
        }
        
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9, blendDuration: 0.1)) {
            pane.remove()
            isSplit = rootPane.children.count > 0
        }
    }
    
    /// Get all leaf panes (panes that contain tabs)
    func getAllLeafPanes() -> [SplitPane] {
        return getLeafPanes(from: rootPane)
    }
    
    private func getLeafPanes(from pane: SplitPane) -> [SplitPane] {
        if pane.isLeaf {
            return [pane]
        }
        
        var leafPanes: [SplitPane] = []
        for child in pane.children {
            leafPanes.append(contentsOf: getLeafPanes(from: child))
        }
        return leafPanes
    }
    
    /// Handle tab drop onto a pane
    func handleTabDrop(_ tab: Tab, onto targetPane: SplitPane, orientation: SplitOrientation) {
        // Prevent splitting with Settings tab
        if tab.isSettingsTab { return }
        // Remove tab from its current pane if it exists
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9, blendDuration: 0.1)) {
            if findPane(containing: tab) != nil {
                removeTab(tab)
            }
            // Split the target pane with the dropped tab
            splitPane(targetPane, with: tab, orientation: orientation)
            isSplit = rootPane.children.count > 0
        }
    }
    
    /// Update split ratio for a pane
    func updateSplitRatio(_ pane: SplitPane, ratio: CGFloat) {
        pane.splitRatio = max(0.1, min(0.9, ratio))
    }
    
    /// Set the active pane for focus management
    func setActivePane(_ pane: SplitPane) {
        activePane = pane
    }
    
    private func handleTabClosure(_ tabId: UUID) {
        // Simply reset to single pane when any tab is closed
        // This ensures split views don't persist after tab removal
        if rootPane.children.count > 0 {
            // Reset to single pane with the first available tab
            rootPane = SplitPane(tab: rootPane.tab ?? Tab())
            activePane = rootPane
            isSplit = false
        }
    }
}

