import SwiftUI

struct TabBarView: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var splitPaneManager: SplitPaneManager
    let onTabSplit: () -> Void
    @State private var draggedTab: Tab?
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        HStack(spacing: 0) {
            // Tabs - Remove ScrollView that's blocking interactions
            HStack(spacing: 0) {
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
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 8)
            
            Spacer()
        }
        .frame(height: 32)
        .background(
            SwiftUI.Color(red: 0.08, green: 0.08, blue: 0.10)
        )
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
    
    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editingTitle = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Tab title or text field for editing
            if isEditing {
                TextField("", text: $editingTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .textFieldStyle(PlainTextFieldStyle())
                    .focused($isTextFieldFocused)
                    .frame(width: max(60, CGFloat(editingTitle.count * 8 + 20)))
                    .onSubmit {
                        finishEditing()
                    }
                    .onExitCommand {
                        cancelEditing()
                    }
            } else {
                Text(tab.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isActive ? .white : .white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contextMenu {
                        Button("Rename") {
                            startEditing()
                        }
                        if tab.isCustomTitle {
                            Button("Reset to Auto Title") {
                                onResetTitle()
                            }
                        }
                    }
            }
            
            // Close button
            if !isEditing {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(PlainButtonStyle())
                .opacity(isHovered ? 1 : 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isActive ? 
                    SwiftUI.Color(red: 0.18, green: 0.18, blue: 0.20) : 
                    SwiftUI.Color(red: 0.12, green: 0.12, blue: 0.14).opacity(isHovered ? 0.8 : 0.6)
                )
        )
        .overlay(
            // Bottom accent for active tab
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isActive ? SwiftUI.Color(red: 0.4, green: 0.6, blue: 1.0) : SwiftUI.Color.clear,
                    lineWidth: isActive ? 2 : 0
                ),
            alignment: .bottom
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing {
                onSelect()
            }
        }
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
                    if !isEditing {
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
        .frame(width: 600, height: 36)
        .background(.black)
} 