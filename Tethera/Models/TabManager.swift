import Foundation
import SwiftUI

/// Manages tabs and their lifecycle
@MainActor
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
    func closeTab(_ id: UUID) {
        guard tabs.count > 1 else { return }
        
        if let index = tabs.firstIndex(where: { $0.id == id }) {
            tabs.remove(at: index)
            
            // If we closed the active tab, set a new active tab
            if activeTabId == id {
                let newIndex = min(index, tabs.count - 1)
                activeTabId = tabs[newIndex].id
            }
            
            // Notify split pane manager about tab closure
            NotificationCenter.default.post(
                name: NSNotification.Name("TabClosed"),
                object: nil,
                userInfo: ["tabId": id]
            )
        }
    }
    
    /// Move a tab to a new position
    func moveTab(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
    }
    
    /// Move tab from one index to another
    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < tabs.count,
              destinationIndex >= 0, destinationIndex <= tabs.count else { return }
        
        let tab = tabs.remove(at: sourceIndex)
        let insertIndex = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        tabs.insert(tab, at: insertIndex)
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
    
    /// Open Settings tab or focus if already open
    func openSettingsTab() {
        if let existing = tabs.first(where: { $0.isSettingsTab }) {
            setActiveTab(existing.id)
            return
        }
        let settingsTab = Tab(title: "Settings")
        settingsTab.isSettingsTab = true
        tabs.append(settingsTab)
        setActiveTab(settingsTab.id)
    }
    
}

