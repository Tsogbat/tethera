import SwiftUI

struct TabBarView: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var splitPaneManager: SplitPaneManager
    let onTabSplit: () -> Void
    @State private var draggedTab: Tab?
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        HStack(spacing: 0) {
            // Tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
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
                            }
                        )
                        .offset(draggedTab?.id == tab.id ? dragOffset : .zero)
                        .zIndex(draggedTab?.id == tab.id ? 1 : 0)
                    }
                }
                .padding(.horizontal, 8)
            }
            
            Spacer()
            
            // New tab button
            Button(action: {
                tabManager.createNewTab()
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(.white.opacity(0.1))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.trailing, 12)
        }
        .frame(height: 36)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    SwiftUI.Color(red: 0.06, green: 0.07, blue: 0.10),
                    SwiftUI.Color(red: 0.09, green: 0.11, blue: 0.15)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                Rectangle()
                    .fill(.white.opacity(0.05))
                    .frame(height: 1),
                alignment: .bottom
            )
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
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Tab title
            Text(tab.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isActive ? .white : .white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)
            
            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(PlainButtonStyle())
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? .white.opacity(0.1) : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isActive ? .white.opacity(0.2) : .clear, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.1)) {
                isHovered = hovering
            }
        }
        .onDrag {
            onDragStart()
            return NSItemProvider(object: tab.id.uuidString as NSString)
        }
        // Smoothen state-driven changes
        .animation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.1), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.1), value: isActive)
    }
}

#Preview {
    let tabManager = TabManager()
    let splitPaneManager = SplitPaneManager(initialTab: tabManager.tabs[0])
    
    TabBarView(tabManager: tabManager, splitPaneManager: splitPaneManager, onTabSplit: {})
        .frame(width: 600, height: 36)
        .background(.black)
} 