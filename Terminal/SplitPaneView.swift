import SwiftUI

struct SplitPaneView: View {
    @ObservedObject var pane: SplitPane
    @ObservedObject var splitPaneManager: SplitPaneManager
    @ObservedObject var tabManager: TabManager
    
    var body: some View {
        GeometryReader { geometry in
            if pane.isLeaf {
                // Leaf pane - show terminal
                if let tab = pane.tab {
                    BlockTerminalView(viewModel: tab.viewModel)
                        .dropDestination(for: Tab.self) { droppedTabs, location in
                            guard let droppedTab = droppedTabs.first else { return false }
                            
                            // Determine split orientation based on drop location
                            let orientation: SplitOrientation = location.x < geometry.size.width / 2 ? .vertical : .horizontal
                            
                            splitPaneManager.handleTabDrop(droppedTab, onto: pane, orientation: orientation)
                            return true
                        } isTargeted: { isTargeted in
                            // Visual feedback for drop target
                        }
                }
            } else {
                // Container pane - show split layout
                if pane.orientation == .horizontal {
                    HStack(spacing: 0) {
                        if pane.children.count >= 1 {
                            SplitPaneView(pane: pane.children[0], splitPaneManager: splitPaneManager, tabManager: tabManager)
                                .frame(width: geometry.size.width * pane.splitRatio)
                        }
                        
                        if pane.children.count >= 2 {
                            DividerView(
                                orientation: .vertical,
                                onDrag: { delta in
                                    let newRatio = pane.splitRatio + (delta / geometry.size.width)
                                    splitPaneManager.updateSplitRatio(pane, ratio: newRatio)
                                }
                            )
                            
                            SplitPaneView(pane: pane.children[1], splitPaneManager: splitPaneManager, tabManager: tabManager)
                                .frame(width: geometry.size.width * (1 - pane.splitRatio))
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        if pane.children.count >= 1 {
                            SplitPaneView(pane: pane.children[0], splitPaneManager: splitPaneManager, tabManager: tabManager)
                                .frame(height: geometry.size.height * pane.splitRatio)
                        }
                        
                        if pane.children.count >= 2 {
                            DividerView(
                                orientation: .horizontal,
                                onDrag: { delta in
                                    let newRatio = pane.splitRatio + (delta / geometry.size.height)
                                    splitPaneManager.updateSplitRatio(pane, ratio: newRatio)
                                }
                            )
                            
                            SplitPaneView(pane: pane.children[1], splitPaneManager: splitPaneManager, tabManager: tabManager)
                                .frame(height: geometry.size.height * (1 - pane.splitRatio))
                        }
                    }
                }
            }
        }
    }
}

struct DividerView: View {
    let orientation: SplitOrientation
    let onDrag: (CGFloat) -> Void
    
    @State private var isDragging = false
    @State private var isHovered = false
    
    var body: some View {
        Rectangle()
            .fill(isDragging ? .blue.opacity(0.5) : (isHovered ? .white.opacity(0.2) : .white.opacity(0.1)))
            .frame(
                width: orientation == .vertical ? 4 : nil,
                height: orientation == .horizontal ? 4 : nil
            )
            .contentShape(Rectangle())
            .cursor(orientation == .vertical ? .resizeLeftRight : .resizeUpDown)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        let delta = orientation == .vertical ? value.translation.width : value.translation.height
                        onDrag(delta)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
}

// Custom cursor modifier
extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { isHovered in
            if isHovered {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

#Preview {
    let tabManager = TabManager()
    let splitPaneManager = SplitPaneManager(initialTab: tabManager.tabs[0])
    
    SplitPaneView(
        pane: splitPaneManager.rootPane,
        splitPaneManager: splitPaneManager,
        tabManager: tabManager
    )
    .frame(width: 800, height: 600)
    .background(.black)
}
