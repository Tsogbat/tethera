import SwiftUI
import AppKit

// MARK: - Tab Bar (Chrome Style)
struct TabBarContent: View {
    @ObservedObject var tabManager: TabManager
    var splitGroups: [SplitGroup] = []
    var activeSplitGroupId: UUID? = nil
    @EnvironmentObject private var userSettings: UserSettings
    @State private var draggedTab: Tab?
    
    // Helper to find split group for a tab
    private func splitGroup(for tabId: UUID) -> SplitGroup? {
        splitGroups.first { $0.contains(tabId) }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(tabManager.tabs) { tab in
                        let group = splitGroup(for: tab.id)
                        let isActiveSplitPane = group?.id == activeSplitGroupId && 
                            (group?.focusedPane == 0 ? group?.leftTabId : group?.rightTabId) == tab.id
                        
                        ChromeTabView(
                            tab: tab,
                            isActive: tab.id == tabManager.activeTabId,
                            splitGroupColor: group?.color,
                            isActiveSplitPane: isActiveSplitPane,
                            onSelect: { tabManager.setActiveTab(tab.id) },
                            onClose: { tabManager.closeTab(tab.id) },
                            onRename: { newName in tabManager.renameTab(tab.id, to: newName) }
                        )
                        .id("\(tab.id)-\(tab.id == tabManager.activeTabId)-\(group?.id.uuidString ?? "none")")
                        .onDrag {
                            draggedTab = tab
                            return NSItemProvider(object: tab.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: TabDropDelegate(
                            tab: tab,
                            tabManager: tabManager,
                            draggedTab: $draggedTab
                        ))
                    }
                    
                    Button(action: { tabManager.createNewTab() }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.5))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
            }
            .id(tabManager.activeTabId)
        }
        .frame(height: 38)
        .background(userSettings.themeConfiguration.backgroundColor.color)
    }
}

// MARK: - Individual Tab (Chrome Style)
struct ChromeTabView: View {
    @ObservedObject var tab: Tab
    let isActive: Bool
    var splitGroupColor: SwiftUI.Color? = nil  // Color if in a split group
    var isActiveSplitPane: Bool = false
    let onSelect: () -> Void
    let onClose: () -> Void
    let onRename: (String) -> Void
    @EnvironmentObject private var userSettings: UserSettings
    
    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editingName = ""
    @FocusState private var isTextFieldFocused: Bool
    
    private var isInSplit: Bool { splitGroupColor != nil }
    
    var body: some View {
        HStack(spacing: 0) {
            // Colored left border for split groups
            if let color = splitGroupColor {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isActiveSplitPane ? color : color.opacity(0.5))
                    .frame(width: 3)
                    .padding(.vertical, 4)
                    .padding(.trailing, 8)
            }
            
            HStack(spacing: 8) {
                // Icon
                Image(systemName: tab.isSettingsTab ? "gearshape.fill" : "terminal.fill")
                    .font(.system(size: 11))
                    .foregroundColor(isActive || isActiveSplitPane
                        ? (splitGroupColor ?? userSettings.themeConfiguration.accentColor.color)
                        : userSettings.themeConfiguration.textColor.color.opacity(0.5))
            
            // Title
            if isEditing {
                TextField("", text: $editingName)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .frame(minWidth: 40, maxWidth: 100)
                    .focused($isTextFieldFocused)
                    .onSubmit { finishEditing() }
                    .onExitCommand { cancelEditing() }
                    .onChange(of: isTextFieldFocused) { _, focused in
                        // Save when focus is lost (clicking outside)
                        if !focused && isEditing {
                            finishEditing()
                        }
                    }
            } else {
                Text(tab.title)
                    .font(.system(size: 12, weight: isActive ? .medium : .regular))
                    .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(isActive ? 1.0 : 0.6))
                    .lineLimit(1)
            }
            
            // Close button (visible on hover or active)
            if !isEditing && (isHovered || isActive) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.5))
                        .frame(width: 16, height: 16)
                        .background(
                            Circle()
                                .fill(userSettings.themeConfiguration.textColor.color.opacity(isHovered ? 0.15 : 0))
                        )
                }
                .buttonStyle(.plain)
            }
            }  // Close inner HStack
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            ZStack {
                if isActive || isHovered || isActiveSplitPane {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                    
                    // Border with split group color
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    (splitGroupColor ?? .white).opacity(isActive || isActiveSplitPane ? 0.4 : 0.08),
                                    (splitGroupColor ?? .white).opacity(isActive || isActiveSplitPane ? 0.15 : 0.02)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isActive || isActiveSplitPane ? 1.5 : 1
                        )
                }
                
                // Subtle underline for inactive split tabs
                if isInSplit && !isActiveSplitPane && !isActive && !isHovered {
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(splitGroupColor ?? userSettings.themeConfiguration.textColor.color.opacity(0.2))
                            .frame(height: 2)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        )
        .shadow(color: isActiveSplitPane ? (splitGroupColor ?? .clear).opacity(0.2) : (isActive ? .black.opacity(0.08) : .clear), radius: 6, x: 0, y: 2)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing { onSelect() }
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if !tab.isSettingsTab { startEditing() }
            }
        )
        .onHover { isHovered = $0 }
        .contextMenu {
            if !tab.isSettingsTab {
                Button("Rename Tab") { startEditing() }
            }
            Button("Close Tab") { onClose() }
        }
    }
    
    private func startEditing() {
        editingName = tab.title
        isEditing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isTextFieldFocused = true
        }
    }
    
    private func finishEditing() {
        isTextFieldFocused = false  // Release focus
        let trimmed = editingName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { onRename(trimmed) }
        isEditing = false
        
        // Reset window first responder to allow terminal to receive keyboard input
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
    
    private func cancelEditing() {
        isTextFieldFocused = false
        isEditing = false
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
}

// MARK: - Chrome Tab Shape (rounded top corners)
struct ChromeTabShape: Shape {
    let isActive: Bool
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius: CGFloat = 8
        
        // Start at bottom left
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        
        // Line up to curve start
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        
        // Top left corner
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        
        // Top edge
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        
        // Top right corner
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        
        // Right edge to bottom
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        
        // Close path (bottom edge)
        path.closeSubpath()
        
        return path
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
    func makeNSView(context: Context) -> DraggableView { DraggableView() }
    func updateNSView(_ nsView: DraggableView, context: Context) {}
}

class DraggableView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

#Preview {
    TabBarContent(tabManager: TabManager())
        .environmentObject(UserSettings())
        .frame(width: 600, height: 40)
}