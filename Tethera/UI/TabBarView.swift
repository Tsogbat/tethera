import SwiftUI
import AppKit

// MARK: - Tab Bar (Chrome Style)
struct TabBarContent: View {
    @ObservedObject var tabManager: TabManager
    @EnvironmentObject private var userSettings: UserSettings
    @State private var draggedTab: Tab?
    
    var body: some View {
        HStack(spacing: 0) {
            // Scrollable tabs area
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(tabManager.tabs) { tab in
                        ChromeTabView(
                            tab: tab,
                            isActive: tab.id == tabManager.activeTabId,
                            onSelect: { tabManager.setActiveTab(tab.id) },
                            onClose: { tabManager.closeTab(tab.id) },
                            onRename: { newName in tabManager.renameTab(tab.id, to: newName) }
                        )
                        .id("\(tab.id)-\(tab.id == tabManager.activeTabId)")
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
                    
                    // New tab button
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
    let onSelect: () -> Void
    let onClose: () -> Void
    let onRename: (String) -> Void
    @EnvironmentObject private var userSettings: UserSettings
    
    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editingName = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Icon
            Image(systemName: tab.isSettingsTab ? "gearshape.fill" : "terminal.fill")
                .font(.system(size: 11))
                .foregroundColor(isActive
                    ? userSettings.themeConfiguration.accentColor.color
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            ZStack {
                // Glass background for active/hovered tabs
                if isActive || isHovered {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                    
                    // Gradient border
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(isActive ? 0.2 : 0.08),
                                    .white.opacity(isActive ? 0.08 : 0.02)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isActive ? 1.5 : 1
                        )
                }
            }
        )
        .shadow(color: isActive ? .black.opacity(0.08) : .clear, radius: 4, x: 0, y: 2)
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