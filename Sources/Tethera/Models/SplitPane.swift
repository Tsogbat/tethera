import Foundation
import SwiftUI

/// Represents the orientation of a split
enum SplitOrientation {
    case horizontal
    case vertical
}

/// Represents a pane in the split view system
class SplitPane: ObservableObject, Identifiable, Equatable {
    let id = UUID()
    @Published var tab: Tab?
    @Published var children: [SplitPane] = []
    @Published var orientation: SplitOrientation = .horizontal
    @Published var splitRatio: CGFloat = 0.5 // Ratio for splitting (0.0 to 1.0)
    
    weak var parent: SplitPane?
    
    init(tab: Tab? = nil) {
        self.tab = tab
    }
    
    var isLeaf: Bool {
        return children.isEmpty
    }
    
    /// Split this pane with a new tab
    func split(with newTab: Tab, orientation: SplitOrientation) {
        guard isLeaf else { return }
        
        // Create a new pane for the existing tab
        let existingPane = SplitPane(tab: self.tab)
        existingPane.parent = self
        
        // Create a new pane for the new tab
        let newPane = SplitPane(tab: newTab)
        newPane.parent = self
        
        // Update this pane to be a container
        self.tab = nil
        self.orientation = orientation
        self.children = [existingPane, newPane]
        self.splitRatio = 0.5
    }
    
    /// Remove this pane from its parent
    func remove() {
        guard let parent = parent else { return }
        
        if let index = parent.children.firstIndex(where: { $0.id == self.id }) {
            parent.children.remove(at: index)
            
            // If parent only has one child left, collapse it
            if parent.children.count == 1 {
                let remainingChild = parent.children[0]
                parent.tab = remainingChild.tab
                parent.children = remainingChild.children
                parent.orientation = remainingChild.orientation
                parent.splitRatio = remainingChild.splitRatio
                
                // Update parent references
                parent.children.forEach { $0.parent = parent }
            }
        }
    }
    
    // MARK: - Equatable
    static func == (lhs: SplitPane, rhs: SplitPane) -> Bool {
        return lhs.id == rhs.id
    }
}
