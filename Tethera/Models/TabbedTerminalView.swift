import SwiftUI
import UniformTypeIdentifiers

struct TabbedTerminalView: View {
    @StateObject private var tabManager: TabManager
    @EnvironmentObject private var userSettings: UserSettings
    @State private var showSplitView = false
    @StateObject private var splitPaneManager: SplitPaneManager
    
    init() {
        let tm = TabManager()
        let manager = SplitPaneManager(initialTab: tm.tabs.first ?? Tab())
        self._tabManager = StateObject(wrappedValue: tm)
        self._splitPaneManager = StateObject(wrappedValue: manager)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Content area
            if let activeTab = tabManager.activeTab, activeTab.isSettingsTab {
                NativeSettingsView()
            } else if showSplitView {
                SplitPaneView(
                    pane: splitPaneManager.rootPane,
                    splitPaneManager: splitPaneManager,
                    tabManager: tabManager,
                    onSplit: { showSplitView = true }
                )
            } else {
                RootDroppableSinglePane(
                    splitPaneManager: splitPaneManager,
                    tabManager: tabManager,
                    onSplit: { showSplitView = true }
                )
            }
        }
        .background(userSettings.themeConfiguration.backgroundColor.color)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                TabBarContent(
                    tabManager: tabManager,
                    splitPaneManager: splitPaneManager,
                    onTabSplit: { showSplitView = true }
                )
            }
        }
        .preferredColorScheme(userSettings.themeConfiguration.isDarkMode ? .dark : .light)
        .onAppear {
            // Set up keyboard shortcut handling
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "t" {
                    tabManager.createNewTab()
                    return nil
                }
                // Broadcast specific keys for terminal/autocomplete handling
                switch event.keyCode {
                case 124, 125, 126, 48: // right, down, up, tab
                    NotificationCenter.default.post(name: NSNotification.Name("TerminalKeyDown"), object: event.keyCode)
                    NotificationCenter.default.post(name: NSNotification.Name("AutocompleteKeyDown"), object: event.keyCode)
                default:
                    break
                }
                return event
            }
            // Listen to requests to open Settings tab
            NotificationCenter.default.addObserver(forName: .openSettingsTab, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    tabManager.openSettingsTab()
                }
            }
        }
    }
}

// MARK: - Single-Tab Root Droppable with Preview

private enum RootDropEdgeHighlight { case left, right, top, bottom }

private struct RootDropHighlightOverlay: View {
    let edge: RootDropEdgeHighlight
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: alignment(for: edge)) {
                SwiftUI.Color.clear
                Rectangle()
                    .fill(SwiftUI.Color.blue.opacity(0.35))
                    .frame(
                        width: (edge == .left || edge == .right) ? geo.size.width * 0.33 : geo.size.width,
                        height: (edge == .top || edge == .bottom) ? geo.size.height * 0.33 : geo.size.height
                    )
                    .overlay(
                        Rectangle().stroke(SwiftUI.Color.blue.opacity(0.6), lineWidth: 2)
                    )
            }
        }
    }
    private func alignment(for edge: RootDropEdgeHighlight) -> Alignment {
        switch edge {
        case .left: return .leading
        case .right: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        }
    }
}

private struct RootDroppableSinglePane: View {
    @ObservedObject var splitPaneManager: SplitPaneManager
    @ObservedObject var tabManager: TabManager
    let onSplit: () -> Void
    @State private var hoverEdge: RootDropEdgeHighlight? = nil
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let activeTab = tabManager.activeTab {
                    BlockTerminalView(viewModel: activeTab.viewModel, isActivePane: true)
                }
                if let edge = hoverEdge {
                    RootDropHighlightOverlay(edge: edge)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .onDrop(of: [UTType.plainText, UTType.text], delegate: RootPaneDropDelegate(
                splitPaneManager: splitPaneManager,
                tabManager: tabManager,
                onSplit: onSplit,
                containerSize: geo.size,
                hoverEdge: $hoverEdge
            ))
            .animation(.spring(response: 0.25, dampingFraction: 0.85, blendDuration: 0.1), value: hoverEdge)
        }
    }
}

private class RootPaneDropDelegate: DropDelegate {
    let splitPaneManager: SplitPaneManager
    let tabManager: TabManager
    let onSplit: () -> Void
    let containerSize: CGSize
    @Binding var hoverEdge: RootDropEdgeHighlight?
    
    init(splitPaneManager: SplitPaneManager, tabManager: TabManager, onSplit: @escaping () -> Void, containerSize: CGSize, hoverEdge: Binding<RootDropEdgeHighlight?>) {
        self.splitPaneManager = splitPaneManager
        self.tabManager = tabManager
        self.onSplit = onSplit
        self.containerSize = containerSize
        self._hoverEdge = hoverEdge
    }
    
    func validateDrop(info: DropInfo) -> Bool { true }
    func dropEntered(info: DropInfo) { updateDropState(info: info) }
    func dropUpdated(info: DropInfo) -> DropProposal? { updateDropState(info: info); return DropProposal(operation: .copy) }
    func dropExited(info: DropInfo) { clearDropState() }
    
    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [UTType.plainText.identifier]) + info.itemProviders(for: [UTType.text.identifier])
        guard let provider = providers.first else { clearDropState(); return false }
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
                self.splitPaneManager.handleTabDrop(tab, onto: self.splitPaneManager.rootPane, orientation: orientation)
                self.onSplit()
            }
        }
        return true
    }
    
    private func updateDropState(info: DropInfo) -> Void {
        splitPaneManager.dropTarget = splitPaneManager.rootPane
        splitPaneManager.dropOrientation = orientation(for: info)
        hoverEdge = edge(for: info)
    }
    
    private func clearDropState() {
        splitPaneManager.dropTarget = nil
        hoverEdge = nil
    }
    
    private func orientation(for info: DropInfo) -> SplitOrientation {
        let loc = info.location
        let x = loc.x / containerSize.width
        if x < 0.33 { return .horizontal }
        if x > 0.66 { return .horizontal }
        return .vertical
    }
    private func edge(for info: DropInfo) -> RootDropEdgeHighlight {
        let loc = info.location
        let x = loc.x / containerSize.width
        let y = loc.y / containerSize.height
        if x < 0.33 { return .left }
        if x > 0.66 { return .right }
        return y < 0.5 ? .top : .bottom
    }
}

#Preview {
    TabbedTerminalView()
        .environmentObject(UserSettings())
        .frame(width: 1000, height: 700)
        .background(.black)
}
