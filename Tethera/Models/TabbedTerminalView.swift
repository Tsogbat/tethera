import SwiftUI
import UniformTypeIdentifiers

// MARK: - Split Direction
enum SplitDirection {
    case horizontal  // Side by side
    case vertical    // Top and bottom
}

// MARK: - Split Group (supports multiple splits)
struct SplitGroup: Identifiable, Equatable {
    let id: UUID
    var leftTabId: UUID
    var rightTabId: UUID
    var direction: SplitDirection
    var colorIndex: Int  // 0-5 for color palette
    var focusedPane: Int = 0  // 0 = left, 1 = right
    
    static let colors: [SwiftUI.Color] = [
        .blue, SwiftUI.Color(red: 0.6, green: 0.4, blue: 0.8), .green, SwiftUI.Color(red: 1, green: 0.6, blue: 0.2), SwiftUI.Color(red: 1, green: 0.4, blue: 0.6), .cyan
    ]
    
    var color: SwiftUI.Color {
        SplitGroup.colors[colorIndex % SplitGroup.colors.count]
    }
    
    func contains(_ tabId: UUID) -> Bool {
        leftTabId == tabId || rightTabId == tabId
    }
}

// MARK: - Main Tabbed Terminal View
struct TabbedTerminalView: View {
    @StateObject private var tabManager = TabManager()
    @EnvironmentObject private var userSettings: UserSettings
    @State private var splitGroups: [SplitGroup] = []
    @State private var activeSplitGroupId: UUID? = nil
    @State private var dropEdge: DropEdge? = nil
    
    // Computed: get active split group
    private var activeSplitGroup: SplitGroup? {
        guard let id = activeSplitGroupId else { return nil }
        return splitGroups.first { $0.id == id }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab bar with split group info
            TabBarContent(
                tabManager: tabManager,
                splitGroups: splitGroups,
                activeSplitGroupId: activeSplitGroupId
            )
            
            // Content area
            GeometryReader { geo in
                ZStack {
                    if let group = activeSplitGroup {
                        splitContentView(for: group)
                    } else {
                        singleContentView
                    }
                    
                    // Drop indicator overlay
                    if let edge = dropEdge {
                        DropIndicatorOverlay(edge: edge, size: geo.size)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: dropEdge)
                .animation(.easeInOut(duration: 0.2), value: activeSplitGroupId)
                .onDrop(of: [.text], delegate: SplitDropDelegate(
                    tabManager: tabManager,
                    splitGroups: $splitGroups,
                    activeSplitGroupId: $activeSplitGroupId,
                    dropEdge: $dropEdge,
                    containerSize: geo.size
                ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(userSettings.themeConfiguration.backgroundColor.color)
        .preferredColorScheme(userSettings.themeConfiguration.isDarkMode ? .dark : .light)
        .onChange(of: tabManager.activeTabId) { _, newActiveId in
            guard let newId = newActiveId else { return }
            dropEdge = nil
            
            // Check if clicked tab is in any split group
            if let group = splitGroups.first(where: { $0.contains(newId) }) {
                // Activate this split group and update focused pane
                withAnimation(.easeInOut(duration: 0.2)) {
                    activeSplitGroupId = group.id
                    if let idx = splitGroups.firstIndex(where: { $0.id == group.id }) {
                        splitGroups[idx].focusedPane = (newId == group.leftTabId) ? 0 : 1
                    }
                }
            } else {
                // Tab not in any split - deactivate split view
                withAnimation(.easeInOut(duration: 0.2)) {
                    activeSplitGroupId = nil
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
                withAnimation(.easeInOut(duration: 0.2)) {
                    splitGroups.removeAll { $0.contains(tabId) }
                    if let activeId = activeSplitGroupId, !splitGroups.contains(where: { $0.id == activeId }) {
                        activeSplitGroupId = nil
                    }
                }
            }
        }
        
        // Handle close split group (X button on grouped tab)
        NotificationCenter.default.addObserver(forName: NSNotification.Name("CloseSplitGroup"), object: nil, queue: .main) { notification in
            guard let groupId = notification.userInfo?["groupId"] as? UUID else { return }
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.2)) {
                    splitGroups.removeAll { $0.id == groupId }
                    if activeSplitGroupId == groupId {
                        activeSplitGroupId = nil
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
    private func splitContentView(for group: SplitGroup) -> some View {
        let leftTab = tabManager.tabs.first { $0.id == group.leftTabId }
        let rightTab = tabManager.tabs.first { $0.id == group.rightTabId }
        
        if group.direction == .horizontal {
            HSplitView {
                if let tab = leftTab {
                    paneView(for: tab, paneIndex: 0, group: group)
                }
                if let tab = rightTab {
                    paneView(for: tab, paneIndex: 1, group: group)
                }
            }
        } else {
            VSplitView {
                if let tab = leftTab {
                    paneView(for: tab, paneIndex: 0, group: group)
                }
                if let tab = rightTab {
                    paneView(for: tab, paneIndex: 1, group: group)
                }
            }
        }
    }
    
    private func paneView(for tab: Tab, paneIndex: Int, group: SplitGroup) -> some View {
        BlockTerminalView(viewModel: tab.viewModel, isActivePane: group.focusedPane == paneIndex)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        group.focusedPane == paneIndex 
                            ? group.color.opacity(0.6) 
                            : SwiftUI.Color.clear,
                        lineWidth: 2
                    )
                    .padding(2)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if let idx = splitGroups.firstIndex(where: { $0.id == group.id }) {
                    splitGroups[idx].focusedPane = paneIndex
                }
                tabManager.setActiveTab(tab.id)
            }
    }
    
    // MARK: - Keyboard Shortcuts
    private func setupKeyboardShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "t" {
                tabManager.createNewTab()
                return nil
            }
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "w" {
                if activeSplitGroupId != nil {
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
        
        NotificationCenter.default.addObserver(forName: .openSettingsTab, object: nil, queue: .main) { _ in
            Task { @MainActor in
                tabManager.openSettingsTab()
            }
        }
    }
    
    private func closeSplit() {
        guard let group = activeSplitGroup else { return }
        let keepTabId = group.focusedPane == 0 ? group.leftTabId : group.rightTabId
        withAnimation(.easeInOut(duration: 0.2)) {
            splitGroups.removeAll { $0.id == group.id }
            activeSplitGroupId = nil
        }
        tabManager.setActiveTab(keepTabId)
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
    @Binding var splitGroups: [SplitGroup]
    @Binding var activeSplitGroupId: UUID?
    @Binding var dropEdge: DropEdge?
    let containerSize: CGSize
    
    init(tabManager: TabManager, splitGroups: Binding<[SplitGroup]>, activeSplitGroupId: Binding<UUID?>, dropEdge: Binding<DropEdge?>, containerSize: CGSize) {
        self.tabManager = tabManager
        self._splitGroups = splitGroups
        self._activeSplitGroupId = activeSplitGroupId
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
        let capturedEdge = dropEdge ?? calculateEdge(info: info)
        
        var providers = info.itemProviders(for: [UTType.text.identifier])
        if providers.isEmpty {
            providers = info.itemProviders(for: [UTType.plainText.identifier])
        }
        
        guard let provider = providers.first else {
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
                
                if error != nil { return }
                
                let uuidString: String
                if let str = data as? String { uuidString = str }
                else if let d = data as? Data, let s = String(data: d, encoding: .utf8) { uuidString = s }
                else if let ns = data as? NSString { uuidString = ns as String }
                else { return }
                
                guard let uuid = UUID(uuidString: uuidString),
                      let droppedTab = self.tabManager.tabs.first(where: { $0.id == uuid }),
                      let currentActiveId = self.tabManager.activeTabId,
                      droppedTab.id != currentActiveId else { return }
                
                // Check if either tab is already in a split - remove from old split first
                self.splitGroups.removeAll { $0.contains(droppedTab.id) || $0.contains(currentActiveId) }
                
                // Create new split group with next color
                let nextColorIndex = self.splitGroups.count % SplitGroup.colors.count
                let direction: SplitDirection = (capturedEdge == .left || capturedEdge == .right) ? .horizontal : .vertical
                
                let leftId = (capturedEdge == .left || capturedEdge == .top) ? droppedTab.id : currentActiveId
                let rightId = (capturedEdge == .left || capturedEdge == .top) ? currentActiveId : droppedTab.id
                
                let newGroup = SplitGroup(
                    id: UUID(),
                    leftTabId: leftId,
                    rightTabId: rightId,
                    direction: direction,
                    colorIndex: nextColorIndex,
                    focusedPane: 1
                )
                
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.splitGroups.append(newGroup)
                    self.activeSplitGroupId = newGroup.id
                }
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
