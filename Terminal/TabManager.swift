import Foundation
import SwiftUI

/// Manages tabs and their lifecycle
class TabManager: ObservableObject {
    @Published var tabs: [Tab] = []
    @Published var activeTabId: UUID?
    
    init() {
        // Create initial tab
        createNewTab()
    }
    
    var activeTab: Tab? {
        guard let activeTabId = activeTabId else { return nil }
        return tabs.first { $0.id == activeTabId }
    }
    
    /// Create a new tab and make it active
    @discardableResult
    func createNewTab() -> Tab {
        let newTab = Tab()
        tabs.append(newTab)
        setActiveTab(newTab.id)
        return newTab
    }
    
    /// Set the active tab
    func setActiveTab(_ tabId: UUID) {
        // Deactivate all tabs
        tabs.forEach { $0.isActive = false }
        
        // Activate the selected tab
        if let tab = tabs.first(where: { $0.id == tabId }) {
            tab.isActive = true
            activeTabId = tabId
        }
    }
    
    /// Close a tab
    func closeTab(_ tabId: UUID) {
        guard tabs.count > 1 else { return } // Don't close the last tab
        
        if let index = tabs.firstIndex(where: { $0.id == tabId }) {
            tabs.remove(at: index)
            
            // If we closed the active tab, activate another one
            if activeTabId == tabId {
                let newActiveIndex = min(index, tabs.count - 1)
                setActiveTab(tabs[newActiveIndex].id)
            }
        }
    }
    
    /// Move a tab to a new position
    func moveTab(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
    }
    
    /// Get tab by ID
    func tab(with id: UUID) -> Tab? {
        return tabs.first { $0.id == id }
    }
    
    /// Rename a tab
    func renameTab(_ tabId: UUID, to newTitle: String) {
        if let tab = tabs.first(where: { $0.id == tabId }) {
            tab.rename(to: newTitle)
        }
    }
    
    /// Reset tab to auto-generated title
    func resetTabTitle(_ tabId: UUID) {
        if let tab = tabs.first(where: { $0.id == tabId }) {
            tab.resetToAutoTitle()
        }
    }
}
