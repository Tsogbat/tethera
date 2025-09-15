import SwiftUI
import UniformTypeIdentifiers

struct TabbedTerminalView: View {
    @StateObject private var tabManager = TabManager()
    @StateObject private var userSettings = UserSettings()
    @State private var showSplitView = false
    @StateObject private var splitPaneManager: SplitPaneManager
    
    init() {
        let initialTab = Tab()
        let manager = SplitPaneManager(initialTab: initialTab)
        self._splitPaneManager = StateObject(wrappedValue: manager)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab bar - draggable area for window
            TabBarView(
                tabManager: tabManager, 
                splitPaneManager: splitPaneManager,
                onTabSplit: { showSplitView = true }
            )
            .background(WindowDragArea())
            
            // Content area - show either single tab or split view
            if showSplitView {
                SplitPaneView(
                    pane: splitPaneManager.rootPane,
                    splitPaneManager: splitPaneManager,
                    tabManager: tabManager,
                    onSplit: { showSplitView = true }
                )
            } else {
                // Show active tab content directly, but still accept drops to initiate split view
                GeometryReader { geo in
                    if let activeTab = tabManager.activeTab {
                        BlockTerminalView(viewModel: activeTab.viewModel, isActivePane: true)
                            .onDrop(of: [UTType.text.identifier], delegate: RootPaneDropDelegate(
                                splitPaneManager: splitPaneManager,
                                tabManager: tabManager,
                                onSplit: { showSplitView = true },
                                containerSize: geo.size
                            ))
                    }
                }
            }
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    userSettings.themeConfiguration.backgroundColor.color,
                    userSettings.themeConfiguration.backgroundColor.color.opacity(0.8)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            // Set up keyboard shortcut handling
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "t" {
                    tabManager.createNewTab()
                    return nil
                }
                return event
            }
        }
    }
}

// MARK: - Window Drag Area

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Enable window dragging for this view
        DispatchQueue.main.async {
            if let window = nsView.window {
                nsView.addGestureRecognizer(NSPanGestureRecognizer(target: WindowDragHandler(window: window), action: #selector(WindowDragHandler.handlePan(_:))))
            }
        }
    }
}

class WindowDragHandler: NSObject {
    weak var window: NSWindow?
    
    init(window: NSWindow) {
        self.window = window
        super.init()
    }
    
    @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
        guard let window = window else { return }
        
        switch gesture.state {
        case .began:
            window.performDrag(with: NSEvent())
        case .changed:
            let translation = gesture.translation(in: gesture.view)
            let currentLocation = window.frame.origin
            let newLocation = NSPoint(x: currentLocation.x + translation.x, y: currentLocation.y - translation.y)
            window.setFrameOrigin(newLocation)
            gesture.setTranslation(.zero, in: gesture.view)
        default:
            break
        }
    }
}

// MARK: - Root Pane Drop Delegate (for single-tab mode)

private class RootPaneDropDelegate: DropDelegate {
    let splitPaneManager: SplitPaneManager
    let tabManager: TabManager
    let onSplit: () -> Void
    let containerSize: CGSize
    
    init(splitPaneManager: SplitPaneManager, tabManager: TabManager, onSplit: @escaping () -> Void, containerSize: CGSize) {
        self.splitPaneManager = splitPaneManager
        self.tabManager = tabManager
        self.onSplit = onSplit
        self.containerSize = containerSize
    }
    
    func validateDrop(info: DropInfo) -> Bool { true }
    func dropEntered(info: DropInfo) {}
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }
    func dropExited(info: DropInfo) {}
    
    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [UTType.text.identifier]).first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { (data, error) in
            DispatchQueue.main.async {
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
    
    private func orientation(for info: DropInfo) -> SplitOrientation {
        let loc = info.location
        let x = loc.x / containerSize.width
        if x < 0.33 { return .horizontal }
        if x > 0.66 { return .horizontal }
        return .vertical
    }
}

#Preview {
    TabbedTerminalView()
        .frame(width: 1000, height: 700)
}
