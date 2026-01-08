import SwiftUI
import UniformTypeIdentifiers

// MARK: - Split Direction
enum SplitDirection {
    case horizontal  // Side by side
    case vertical    // Top and bottom
}

// MARK: - Split State
struct SplitState {
    var isActive: Bool = false
    var direction: SplitDirection = .horizontal
    var leftTabId: UUID?
    var rightTabId: UUID?
    var splitRatio: CGFloat = 0.5
    var focusedPane: Int = 0  // 0 = left/top, 1 = right/bottom
}

// MARK: - Main Tabbed Terminal View
struct TabbedTerminalView: View {
    @StateObject private var tabManager = TabManager()
    @EnvironmentObject private var userSettings: UserSettings
    @State private var splitState = SplitState()
    @State private var dropEdge: DropEdge? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab bar at top - pass split state for indicators
            TabBarContent(
                tabManager: tabManager,
                splitTabIds: [splitState.leftTabId, splitState.rightTabId].compactMap { $0 },
                activeSplitTabId: splitState.isActive ? (splitState.focusedPane == 0 ? splitState.leftTabId : splitState.rightTabId) : nil
            )
            
            // Content area
            GeometryReader { geo in
                ZStack {
                    if splitState.isActive {
                        splitContentView
                    } else {
                        singleContentView
                    }
                    
                    // Drop indicator overlay (only when NOT in split mode)
                    if let edge = dropEdge, !splitState.isActive {
                        DropIndicatorOverlay(edge: edge, size: geo.size)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: dropEdge)
                .animation(.easeInOut(duration: 0.2), value: splitState.isActive)
                .onDrop(of: [.text], delegate: SplitDropDelegate(
                    tabManager: tabManager,
                    splitState: $splitState,
                    dropEdge: $dropEdge,
                    containerSize: geo.size
                ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(userSettings.themeConfiguration.backgroundColor.color)
        .preferredColorScheme(userSettings.themeConfiguration.isDarkMode ? .dark : .light)
        // Handle tab switching with split view
        .onChange(of: tabManager.activeTabId) { _, newActiveId in
            guard let newId = newActiveId else { return }
            
            // Always clear drop indicator on tab change
            dropEdge = nil
            
            let isInSplit = newId == splitState.leftTabId || newId == splitState.rightTabId
            
            if splitState.isActive {
                if isInSplit {
                    // Update focused pane to match clicked tab
                    if newId == splitState.leftTabId {
                        splitState.focusedPane = 0
                    } else if newId == splitState.rightTabId {
                        splitState.focusedPane = 1
                    }
                } else {
                    // User clicked a tab outside the split - hide split but keep tab IDs
                    withAnimation(.easeInOut(duration: 0.2)) {
                        splitState.isActive = false
                        // DON'T clear leftTabId/rightTabId - preserve split for later
                    }
                }
            } else {
                // Not currently in split mode - check if clicked tab is in saved split
                if isInSplit && splitState.leftTabId != nil && splitState.rightTabId != nil {
                    // Restore split view and set focused pane
                    withAnimation(.easeInOut(duration: 0.2)) {
                        splitState.isActive = true
                        splitState.focusedPane = (newId == splitState.leftTabId) ? 0 : 1
                    }
                }
            }
        }
        .onAppear {
            setupKeyboardShortcuts()
            setupTabCloseHandler()
        }
    }
    
    // MARK: - Handle Tab Closure
    private func setupTabCloseHandler() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name("TabClosed"), object: nil, queue: .main) { notification in
            guard let tabId = notification.userInfo?["tabId"] as? UUID else { return }
            Task { @MainActor in
                // Clear split state if closed tab was in split
                if tabId == splitState.leftTabId || tabId == splitState.rightTabId {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        splitState.isActive = false
                        splitState.leftTabId = nil
                        splitState.rightTabId = nil
                    }
                }
            }
        }
    }
    
    // MARK: - Single Content View
    @ViewBuilder
    private var singleContentView: some View {
        if let activeTab = tabManager.activeTab {
            if activeTab.isSettingsTab {
                NativeSettingsView()
            } else {
                BlockTerminalView(viewModel: activeTab.viewModel, isActivePane: true)
            }
        }
    }
    
    // MARK: - Split Content View
    @ViewBuilder
    private var splitContentView: some View {
        let leftTab = splitState.leftTabId.flatMap { id in tabManager.tabs.first { $0.id == id } }
        let rightTab = splitState.rightTabId.flatMap { id in tabManager.tabs.first { $0.id == id } }
        
        if splitState.direction == .horizontal {
            HSplitView {
                if let tab = leftTab {
                    paneView(for: tab, paneIndex: 0)
                }
                if let tab = rightTab {
                    paneView(for: tab, paneIndex: 1)
                }
            }
        } else {
            VSplitView {
                if let tab = leftTab {
                    paneView(for: tab, paneIndex: 0)
                }
                if let tab = rightTab {
                    paneView(for: tab, paneIndex: 1)
                }
            }
        }
    }
    
    private func paneView(for tab: Tab, paneIndex: Int) -> some View {
        BlockTerminalView(viewModel: tab.viewModel, isActivePane: splitState.focusedPane == paneIndex)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        splitState.focusedPane == paneIndex 
                            ? userSettings.themeConfiguration.accentColor.color.opacity(0.5) 
                            : SwiftUI.Color.clear,
                        lineWidth: 2
                    )
                    .padding(2)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                splitState.focusedPane = paneIndex
                // Also update active tab in tab manager
                tabManager.setActiveTab(tab.id)
            }
    }
    
    // MARK: - Keyboard Shortcuts
    private func setupKeyboardShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Cmd+T: New tab
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "t" {
                tabManager.createNewTab()
                return nil
            }
            // Cmd+W: Close tab or unsplit
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "w" {
                if splitState.isActive {
                    closeSplit()
                } else if tabManager.tabs.count > 1 {
                    if let activeId = tabManager.activeTabId {
                        tabManager.closeTab(activeId)
                    }
                }
                return nil
            }
            return event
        }
        
        // Settings tab notification
        NotificationCenter.default.addObserver(forName: .openSettingsTab, object: nil, queue: .main) { _ in
            Task { @MainActor in
                tabManager.openSettingsTab()
            }
        }
    }
    
    private func closeSplit() {
        // Keep the focused pane, close split
        let keepTabId = splitState.focusedPane == 0 ? splitState.leftTabId : splitState.rightTabId
        splitState.isActive = false
        splitState.leftTabId = nil
        splitState.rightTabId = nil
        if let id = keepTabId {
            tabManager.setActiveTab(id)
        }
    }
}

// MARK: - Drop Edge
enum DropEdge {
    case left, right, top, bottom
}

// MARK: - Drop Indicator Overlay
struct DropIndicatorOverlay: View {
    let edge: DropEdge
    let size: CGSize
    
    var body: some View {
        ZStack(alignment: alignment) {
            SwiftUI.Color.clear
            Rectangle()
                .fill(SwiftUI.Color.blue.opacity(0.3))
                .frame(
                    width: isHorizontal ? size.width * 0.4 : size.width,
                    height: isHorizontal ? size.height : size.height * 0.4
                )
                .overlay(
                    Rectangle()
                        .stroke(SwiftUI.Color.blue.opacity(0.6), lineWidth: 2)
                )
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.15), value: edge)
    }
    
    private var isHorizontal: Bool {
        edge == .left || edge == .right
    }
    
    private var alignment: Alignment {
        switch edge {
        case .left: return .leading
        case .right: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        }
    }
}

// MARK: - Split Drop Delegate
class SplitDropDelegate: DropDelegate {
    let tabManager: TabManager
    @Binding var splitState: SplitState
    @Binding var dropEdge: DropEdge?
    let containerSize: CGSize
    
    init(tabManager: TabManager, splitState: Binding<SplitState>, dropEdge: Binding<DropEdge?>, containerSize: CGSize) {
        self.tabManager = tabManager
        self._splitState = splitState
        self._dropEdge = dropEdge
        self.containerSize = containerSize
    }
    
    func validateDrop(info: DropInfo) -> Bool { true }
    
    func dropEntered(info: DropInfo) {
        updateEdge(info: info)
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateEdge(info: info)
        return DropProposal(operation: .copy)
    }
    
    func dropExited(info: DropInfo) {
        dropEdge = nil
    }
    
    func performDrop(info: DropInfo) -> Bool {
        // Capture edge NOW before async - info may not be valid later
        let capturedEdge = dropEdge ?? calculateEdge(info: info)
        
        // Try both text types
        var providers = info.itemProviders(for: [UTType.text.identifier])
        if providers.isEmpty {
            providers = info.itemProviders(for: [UTType.plainText.identifier])
        }
        
        guard let provider = providers.first else {
            print("[Split] No valid provider found")
            dropEdge = nil
            return false
        }
        
        let typeId = provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) 
            ? UTType.plainText.identifier 
            : UTType.text.identifier
        
        provider.loadItem(forTypeIdentifier: typeId, options: nil) { [weak self] data, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                defer { self.dropEdge = nil }
                
                if let error = error {
                    print("[Split] Load error: \(error)")
                    return
                }
                
                let uuidString: String
                if let str = data as? String { uuidString = str }
                else if let d = data as? Data, let s = String(data: d, encoding: .utf8) { uuidString = s }
                else if let ns = data as? NSString { uuidString = ns as String }
                else {
                    print("[Split] Could not parse UUID from data")
                    return
                }
                
                guard let uuid = UUID(uuidString: uuidString) else {
                    print("[Split] Invalid UUID: \(uuidString)")
                    return
                }
                
                guard let droppedTab = self.tabManager.tabs.first(where: { $0.id == uuid }) else {
                    print("[Split] Tab not found for UUID: \(uuid)")
                    return
                }
                
                guard let currentActiveId = self.tabManager.activeTabId,
                      droppedTab.id != currentActiveId else {
                    print("[Split] Same tab or no active tab")
                    return
                }
                
                // Create split using captured edge
                print("[Split] Creating split with edge: \(capturedEdge)")
                self.splitState.direction = (capturedEdge == .left || capturedEdge == .right) ? .horizontal : .vertical
                
                if capturedEdge == .left || capturedEdge == .top {
                    self.splitState.leftTabId = droppedTab.id
                    self.splitState.rightTabId = currentActiveId
                } else {
                    self.splitState.leftTabId = currentActiveId
                    self.splitState.rightTabId = droppedTab.id
                }
                
                self.splitState.isActive = true
                self.splitState.focusedPane = 1
                print("[Split] Split activated!")
            }
        }
        return true
    }
    
    private func updateEdge(info: DropInfo) {
        dropEdge = calculateEdge(info: info)
    }
    
    private func calculateEdge(info: DropInfo) -> DropEdge {
        let loc = info.location
        let x = loc.x / containerSize.width
        let y = loc.y / containerSize.height
        
        // Check if closer to horizontal or vertical edge
        let distToLeft = x
        let distToRight = 1 - x
        let distToTop = y
        let distToBottom = 1 - y
        
        let minHorizontal = min(distToLeft, distToRight)
        let minVertical = min(distToTop, distToBottom)
        
        if minHorizontal < minVertical {
            return distToLeft < distToRight ? .left : .right
        } else {
            return distToTop < distToBottom ? .top : .bottom
        }
    }
}

#Preview {
    TabbedTerminalView()
        .environmentObject(UserSettings())
        .frame(width: 1000, height: 700)
        .background(.black)
}
