import SwiftUI

struct TabDropDelegate: DropDelegate {
    let tab: Tab
    let tabManager: TabManager
    @Binding var draggedTab: Tab?
    
    func performDrop(info: DropInfo) -> Bool {
        guard let draggedTab = draggedTab else { return false }
        
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75, blendDuration: 0.2)) {
            if let sourceIndex = tabManager.tabs.firstIndex(where: { $0.id == draggedTab.id }),
               let destinationIndex = tabManager.tabs.firstIndex(where: { $0.id == tab.id }) {
                
                // Better insertion logic for left-to-right dragging
                let location = info.location
                let tabFrame = CGRect(x: 0, y: 0, width: 150, height: 32)
                let insertAtEnd = location.x > tabFrame.width / 2
                
                let finalDestination = insertAtEnd ? destinationIndex + 1 : destinationIndex
                tabManager.moveTab(from: sourceIndex, to: finalDestination)
            }
        }
        
        self.draggedTab = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggedTab = draggedTab,
              draggedTab.id != tab.id else { return }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0.1)) {
            if let sourceIndex = tabManager.tabs.firstIndex(where: { $0.id == draggedTab.id }),
               let destinationIndex = tabManager.tabs.firstIndex(where: { $0.id == tab.id }) {
                
                // Determine insertion point based on drag direction
                let location = info.location
                let tabFrame = CGRect(x: 0, y: 0, width: 150, height: 32) // Approximate tab size
                let insertAtEnd = location.x > tabFrame.width / 2
                
                let finalDestination = insertAtEnd ? destinationIndex + 1 : destinationIndex
                tabManager.moveTab(from: sourceIndex, to: finalDestination)
            }
        }
    }
    
    func dropExited(info: DropInfo) {
        // Smooth exit animation handled by tab view
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        return draggedTab != nil && draggedTab?.id != tab.id
    }
}
