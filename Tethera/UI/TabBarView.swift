import SwiftUI

struct TabBarView: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var splitPaneManager: SplitPaneManager
    @EnvironmentObject private var userSettings: UserSettings
    let onTabSplit: () -> Void
    @State private var draggedTab: Tab?
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        HStack(spacing: 0) {
            // Tabs - Remove ScrollView that's blocking interactions
            HStack(spacing: 8) {
                ForEach(tabManager.tabs) { tab in
                    TabView(
                        tab: tab,
                        isActive: tab.id == tabManager.activeTabId,
                        onSelect: { tabManager.setActiveTab(tab.id) },
                        onClose: { tabManager.closeTab(tab.id) },
                        onDragStart: { draggedTab = tab },
                        onDragEnd: { 
                            draggedTab = nil
                            dragOffset = .zero
                        },
                        onRename: { newTitle in
                            tabManager.renameTab(tab.id, to: newTitle)
                        },
                        onResetTitle: {
                            tabManager.resetTabTitle(tab.id)
                        },
                        draggedTab: $draggedTab
                    )
                    .offset(draggedTab?.id == tab.id ? dragOffset : .zero)
                    .zIndex(draggedTab?.id == tab.id ? 100 : (tab.id == tabManager.activeTabId ? 10 : 0))
                    .onDrop(of: [.text], delegate: TabDropDelegate(
                        tab: tab,
                        tabManager: tabManager,
                        draggedTab: $draggedTab
                    ))
                }
                
                // New tab button
                Button(action: {
                    tabManager.createNewTab()
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.7))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(PlainButtonStyle())

            }
            .padding(.horizontal, 12)
            
            Spacer()
        }
        .frame(height: 40)
        .background(userSettings.themeConfiguration.backgroundColor.color)
    }
}

struct TabView: View {
    @ObservedObject var tab: Tab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onDragStart: () -> Void
    let onDragEnd: () -> Void
    let onRename: (String) -> Void
    let onResetTitle: () -> Void
    @Binding var draggedTab: Tab?
    @EnvironmentObject private var userSettings: UserSettings
    
    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editingTitle = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Tab title or text field for editing
            if isEditing {
                TextField("", text: $editingTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(userSettings.themeConfiguration.textColor.color)
                    .textFieldStyle(PlainTextFieldStyle())
                    .focused($isTextFieldFocused)
                    .frame(width: max(80, CGFloat(editingTitle.count * 10 + 20)))
                    .onSubmit {
                        finishEditing()
                    }
                    .onExitCommand {
                        cancelEditing()
                    }
            } else {
                Text(tab.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isActive ? userSettings.themeConfiguration.textColor.color : userSettings.themeConfiguration.textColor.color.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contextMenu {
                        if !tab.isSettingsTab {
                            Button("Rename") { startEditing() }
                            if tab.isCustomTitle {
                                Button("Reset to Auto Title") { onResetTitle() }
                            }
                        }
                    }
            }
            
            // Close button
            if !isEditing {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.6))
                }
                .buttonStyle(PlainButtonStyle())
                .opacity(isHovered ? 1 : 0.3)
                .frame(width: 20, height: 20)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isActive ?
                        userSettings.themeConfiguration.backgroundColor.color.opacity(userSettings.themeConfiguration.isDarkMode ? 0.4 : 0.15) :
                        userSettings.themeConfiguration.backgroundColor.color.opacity(userSettings.themeConfiguration.isDarkMode ? (isHovered ? 0.3 : 0.25) : (isHovered ? 0.1 : 0.08))
                )
        )
        .overlay(
            // Bottom accent for active tab
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isActive ? userSettings.themeConfiguration.accentColor.color : SwiftUI.Color.clear,
                    lineWidth: isActive ? 2 : 0
                ),
            alignment: .bottom
        )
        .contentShape(Rectangle())
        .highPriorityGesture(
            TapGesture(count: 1).onEnded {
                if !isEditing { onSelect() }
            }
        )
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8, blendDuration: 0.05)) {
                isHovered = hovering
            }
        }
        .onDrag {
            if !isEditing {
                onDragStart()
                return NSItemProvider(object: tab.id.uuidString as NSString)
            }
            return NSItemProvider()
        }
        .scaleEffect(draggedTab?.id == tab.id ? 0.92 : 1.0)
        .opacity(draggedTab?.id == tab.id ? 0.7 : 1.0)
        .rotationEffect(.degrees(draggedTab?.id == tab.id ? 2 : 0))
        .animation(.spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0.1), value: draggedTab?.id == tab.id)
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    if !isEditing && !tab.isSettingsTab {
                        startEditing()
                    }
                }
        )
    }
    
    private func startEditing() {
        editingTitle = tab.title
        isEditing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            isTextFieldFocused = true
        }
    }
    
    private func finishEditing() {
        onRename(editingTitle)
        isEditing = false
        isTextFieldFocused = false
        // Restore focus to terminal input
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: .restoreTerminalFocus, object: nil)
        }
    }
    
    private func cancelEditing() {
        editingTitle = tab.title
        isEditing = false
        isTextFieldFocused = false
        // Restore focus to terminal input
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: .restoreTerminalFocus, object: nil)
        }
    }
}

#Preview {
    let tabManager = TabManager()
    let splitPaneManager = SplitPaneManager(initialTab: tabManager.tabs[0])
    
    TabBarView(tabManager: tabManager, splitPaneManager: splitPaneManager, onTabSplit: {})
        .environmentObject(UserSettings())
        .frame(width: 600, height: 44)
        .background(.black)
}
 