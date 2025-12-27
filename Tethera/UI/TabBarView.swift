import SwiftUI
import AppKit

// MARK: - Tab Bar Content for Toolbar
struct TabBarContent: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var splitPaneManager: SplitPaneManager
    @EnvironmentObject private var userSettings: UserSettings
    let onTabSplit: () -> Void
    @State private var draggedTab: Tab?
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabManager.tabs) { tab in
                TabItemView(
                    tab: tab,
                    isActive: tab.id == tabManager.activeTabId,
                    onSelect: { tabManager.setActiveTab(tab.id) },
                    onClose: { tabManager.closeTab(tab.id) },
                    onDragStart: { draggedTab = tab },
                    onDragEnd: { draggedTab = nil }
                )
                .onDrop(of: [.text], delegate: TabDropDelegate(
                    tab: tab,
                    tabManager: tabManager,
                    draggedTab: $draggedTab
                ))
            }
            
            // New tab button
            Button(action: { tabManager.createNewTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
    }
}

// MARK: - Clean Tab Item
struct TabItemView: View {
    @ObservedObject var tab: Tab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onDragStart: () -> Void
    let onDragEnd: () -> Void
    @EnvironmentObject private var userSettings: UserSettings
    
    @State private var isHovered = false
    @State private var isCloseHovered = false
    
    var body: some View {
        HStack(spacing: 5) {
            // Icon
            Image(systemName: tab.isSettingsTab ? "gearshape" : "terminal")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isActive ? userSettings.themeConfiguration.accentColor.color : userSettings.themeConfiguration.textColor.color.opacity(0.4))
            
            // Title
            Text(tab.title)
                .font(.system(size: 12, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
            
            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(isCloseHovered ? SwiftUI.Color.red : userSettings.themeConfiguration.textColor.color.opacity(0.4))
            }
            .buttonStyle(.plain)
            .opacity(isActive || isHovered ? 1 : 0)
            .onHover { isCloseHovered = $0 }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Group {
                if isActive {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary.opacity(0.5))
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovered = $0 }
        .onDrag {
            onDragStart()
            return NSItemProvider(object: tab.id.uuidString as NSString)
        }
    }
}

// MARK: - Legacy TabBarView (compatibility)
struct TabBarView: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var splitPaneManager: SplitPaneManager
    @EnvironmentObject private var userSettings: UserSettings
    let onTabSplit: () -> Void
    
    var body: some View {
        EmptyView()
    }
}

// MARK: - Window Drag Area
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggableView {
        DraggableView()
    }
    
    func updateNSView(_ nsView: DraggableView, context: Context) {}
}

class DraggableView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

// MARK: - Glass View Modifiers
extension View {
    func glassBackground(cornerRadius: CGFloat = 12) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            )
    }
    
    func glassCard() -> some View {
        self
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }
}

#Preview {
    TabBarContent(
        tabManager: TabManager(),
        splitPaneManager: SplitPaneManager(initialTab: Tab()),
        onTabSplit: {}
    )
    .environmentObject(UserSettings())
    .padding()
    .background(SwiftUI.Color(red: 0.1, green: 0.1, blue: 0.12))
}