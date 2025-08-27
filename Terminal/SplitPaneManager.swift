import Foundation
import SwiftUI

/// Manages the split pane layout and operations
class SplitPaneManager: ObservableObject {
    @Published var rootPane: SplitPane
    @Published var draggedTab: Tab?
    @Published var dropTarget: SplitPane?
    @Published var dropOrientation: SplitOrientation = .horizontal
    @Published var activePane: SplitPane?
    
    init(initialTab: Tab) {
        self.rootPane = SplitPane(tab: initialTab)
        self.activePane = self.rootPane
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
        pane.split(with: tab, orientation: orientation)
    }
    
    /// Remove a tab from the pane system
    func removeTab(_ tab: Tab) {
        guard let pane = findPane(containing: tab) else { return }
        
        if pane == rootPane && pane.isLeaf {
            // Don't remove the root pane if it's the only one
            return
        }
        
        pane.remove()
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
        // Remove tab from its current pane if it exists
        if findPane(containing: tab) != nil {
            removeTab(tab)
        }
        
        // Split the target pane with the dropped tab
        splitPane(targetPane, with: tab, orientation: orientation)
    }
    
    /// Update split ratio for a pane
    func updateSplitRatio(_ pane: SplitPane, ratio: CGFloat) {
        pane.splitRatio = max(0.1, min(0.9, ratio))
    }
    
    /// Set the active pane for focus management
    func setActivePane(_ pane: SplitPane) {
        activePane = pane
    }
}
