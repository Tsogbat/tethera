import SwiftUI
import UniformTypeIdentifiers

struct SplitPaneView: View {
    @ObservedObject var pane: SplitPane
    @ObservedObject var splitPaneManager: SplitPaneManager
    @ObservedObject var tabManager: TabManager
    let onSplit: () -> Void
    @State private var hoverEdge: DropEdgeHighlight? = nil
    @State private var isHovered: Bool = false
    @EnvironmentObject private var userSettings: UserSettings
    
    var body: some View {
        GeometryReader { geometry in
            if pane.isLeaf {
                // Leaf pane - show terminal
                if let tab = pane.tab {
                    ZStack {
                        BlockTerminalView(viewModel: tab.viewModel, isActivePane: splitPaneManager.activePane == pane)
                        
                        // Close pane button (top-right corner)
                        VStack {
                            HStack {
                                Spacer()
                                Button(action: {
                                    splitPaneManager.removeTab(tab)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.65))
                                        .background(
                                            Circle().fill(
                                                SwiftUI.Color.black.opacity(userSettings.themeConfiguration.isDarkMode ? 0.30 : 0.10)
                                            )
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .opacity(isHovered ? 1 : 0)
                                .animation(.easeInOut(duration: 0.2), value: isHovered)
                                .padding(8)
                            }
                            Spacer()
                        }
                        
                        // Visual drop target highlight
                        if splitPaneManager.dropTarget == pane, let edge = hoverEdge {
                            DropHighlightOverlay(orientation: edge)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isHovered = hovering
                        }
                    }
                    .onTapGesture {
                        splitPaneManager.setActivePane(pane)
                    }
                    .onDrop(of: [UTType.plainText, UTType.text], delegate: PaneDropDelegate(
                        pane: pane,
                        splitPaneManager: splitPaneManager,
                        tabManager: tabManager,
                        onSplit: onSplit,
                        containerSize: geometry.size,
                        hoverEdge: $hoverEdge
                    ))
                }
            } else {
                // Container pane - show split layout
                if pane.orientation == .horizontal {
                    HStack(spacing: 0) {
                        if pane.children.count >= 1 {
                            SplitPaneView(pane: pane.children[0], splitPaneManager: splitPaneManager, tabManager: tabManager, onSplit: onSplit)
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
                            
                            SplitPaneView(pane: pane.children[1], splitPaneManager: splitPaneManager, tabManager: tabManager, onSplit: onSplit)
                                .frame(width: geometry.size.width * (1 - pane.splitRatio))
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        if pane.children.count >= 1 {
                            SplitPaneView(pane: pane.children[0], splitPaneManager: splitPaneManager, tabManager: tabManager, onSplit: onSplit)
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
                            
                            SplitPaneView(pane: pane.children[1], splitPaneManager: splitPaneManager, tabManager: tabManager, onSplit: onSplit)
                                .frame(height: geometry.size.height * (1 - pane.splitRatio))
                        }
                    }
                }
            }
        }
        // Smooth appearance of drop highlight
        .animation(.spring(response: 0.25, dampingFraction: 0.85, blendDuration: 0.1), value: hoverEdge)
    }
}

struct DividerView: View {
    let orientation: SplitOrientation
    let onDrag: (CGFloat) -> Void
    
    @State private var isDragging = false
    @State private var isHovered = false
    @EnvironmentObject private var userSettings: UserSettings
    
    var body: some View {
        Rectangle()
            .fill(
                isDragging ? userSettings.themeConfiguration.accentColor.color.opacity(0.5) : (
                    isHovered ?
                        (userSettings.themeConfiguration.isDarkMode ? SwiftUI.Color.white.opacity(0.22) : SwiftUI.Color.black.opacity(0.10)) :
                        (userSettings.themeConfiguration.isDarkMode ? SwiftUI.Color.white.opacity(0.12) : SwiftUI.Color.black.opacity(0.06))
                )
            )
            .frame(
                width: orientation == .vertical ? 4 : nil,
                height: orientation == .horizontal ? 4 : nil
            )
            .contentShape(Rectangle())
            .cursor(orientation == .vertical ? .resizeLeftRight : .resizeUpDown)
            .onHover { hovering in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85, blendDuration: 0.1)) {
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

// MARK: - Drop Highlight

private enum DropEdgeHighlight {
    case left, right, top, bottom
}

private struct DropHighlightOverlay: View {
    let orientation: DropEdgeHighlight
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: alignment(for: orientation)) {
                SwiftUI.Color.clear
                Rectangle()
                    .fill(SwiftUI.Color(red: 0.0, green: 0.48, blue: 1.0, opacity: 0.35))
                    .frame(width: orientation == .left || orientation == .right ? geo.size.width * 0.33 : geo.size.width,
                           height: orientation == .top || orientation == .bottom ? geo.size.height * 0.33 : geo.size.height)
                    .overlay(
                        Rectangle().stroke(SwiftUI.Color(red: 0.0, green: 0.48, blue: 1.0, opacity: 0.6), lineWidth: 2)
                    )
                    .animation(.spring(response: 0.22, dampingFraction: 0.85, blendDuration: 0.1), value: orientation)
            }
        }
    }
    private func alignment(for edge: DropEdgeHighlight) -> Alignment {
        switch edge {
        case .left: return .leading
        case .right: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        }
    }
}

// MARK: - Drop Delegate

private class PaneDropDelegate: DropDelegate {
    let pane: SplitPane
    let splitPaneManager: SplitPaneManager
    let tabManager: TabManager
    let onSplit: () -> Void
    let containerSize: CGSize
    @Binding var hoverEdge: DropEdgeHighlight?
    
    init(pane: SplitPane, splitPaneManager: SplitPaneManager, tabManager: TabManager, onSplit: @escaping () -> Void, containerSize: CGSize, hoverEdge: Binding<DropEdgeHighlight?>) {
        self.pane = pane
        self.splitPaneManager = splitPaneManager
        self.tabManager = tabManager
        self.onSplit = onSplit
        self.containerSize = containerSize
        self._hoverEdge = hoverEdge
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        // Only allow drops when we know which tab is being dragged
        return true
    }
    
    func dropEntered(info: DropInfo) {
        updateDropState(info: info)
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropState(info: info)
        return DropProposal(operation: .copy)
    }
    
    func dropExited(info: DropInfo) {
        clearDropState()
    }
    
    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [UTType.plainText.identifier]) + info.itemProviders(for: [UTType.text.identifier])
        guard let provider = providers.first else { clearDropState(); return false }
        // Return true immediately; complete asynchronously.
        let typeId = provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) ? UTType.plainText.identifier : UTType.text.identifier
        provider.loadItem(forTypeIdentifier: typeId, options: nil) { (data, error) in
            DispatchQueue.main.async {
                defer { self.clearDropState() }
                guard error == nil else { return }
                let uuidString: String
                if let str = data as? String { uuidString = str }
                else if let d = data as? Data, let s = String(data: d, encoding: .utf8) { uuidString = s }
                else if let ns = data as? NSString { uuidString = ns as String }
                else { return }
                guard let uuid = UUID(uuidString: uuidString), let tab = self.tabManager.tabs.first(where: { $0.id == uuid }) else { return }
                let orientation = self.orientation(for: info)
                self.splitPaneManager.handleTabDrop(tab, onto: self.pane, orientation: orientation)
                self.onSplit()
            }
        }
        return true
    }
    
    private func updateDropState(info: DropInfo) {
        splitPaneManager.dropTarget = pane
        // compute orientation from location
        splitPaneManager.dropOrientation = orientation(for: info)
        // store edge hint for visual overlay
        hoverEdge = edge(for: info)
    }
    
    private func clearDropState() {
        splitPaneManager.dropTarget = nil
        hoverEdge = nil
        splitPaneManager.draggedTab = nil
    }
    
    private func orientation(for info: DropInfo) -> SplitOrientation {
        let loc = info.location
        let x = loc.x / containerSize.width
        // Left/Right -> horizontal split (HStack)
        // Top/Bottom -> vertical split (VStack)
        if x < 0.33 { return .horizontal }
        if x > 0.66 { return .horizontal }
        // center vertical decision by y
        return .vertical
    }
    
    private func edge(for info: DropInfo) -> DropEdgeHighlight {
        let loc = info.location
        let x = loc.x / containerSize.width
        let y = loc.y / containerSize.height
        if x < 0.33 { return .left }
        if x > 0.66 { return .right }
        if y < 0.5 { return .top }
        return .bottom
    }
}

// (No manager storage needed; highlight is maintained as local view state.)

#Preview {
    let tabManager = TabManager()
    let splitPaneManager = SplitPaneManager(initialTab: tabManager.tabs[0])
    
    SplitPaneView(
        pane: splitPaneManager.rootPane,
        splitPaneManager: splitPaneManager,
        tabManager: tabManager,
        onSplit: {}
    )
    .frame(width: 800, height: 600)
    .background(.black)
}
