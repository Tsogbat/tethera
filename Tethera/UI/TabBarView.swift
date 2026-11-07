import SwiftUI
import AppKit

enum TabDisplayItem: Identifiable {
    case singleTab(Tab)
    case splitGroup(SplitGroup, leftTab: Tab, rightTab: Tab)

    var id: String {
        switch self {
        case .singleTab(let tab): return "single-\(tab.id)"
        case .splitGroup(let group, _, _): return "group-\(group.id)"
        }
    }
}

/// Tabs live in the title bar, beside the traffic lights.
struct TabBarContent: View {
    @EnvironmentObject private var settings: UserSettings
    @ObservedObject var tabManager: TabManager
    @ObservedObject private var metrics = WindowMetrics.shared
    var splitGroups: [SplitGroup] = []
    var activeSplitGroupId: UUID?
    var onOpenPalette: () -> Void = {}

    @Namespace private var pillNamespace
    @State private var draggedTab: Tab?

    private var displayItems: [TabDisplayItem] {
        var items: [TabDisplayItem] = []
        var handled = Set<UUID>()
        for tab in tabManager.tabs where !handled.contains(tab.id) {
            if let group = splitGroups.first(where: { $0.leftTabId == tab.id }),
               let right = tabManager.tab(with: group.rightTabId) {
                items.append(.splitGroup(group, leftTab: tab, rightTab: right))
                handled.insert(tab.id)
                handled.insert(right.id)
            } else if !splitGroups.contains(where: { $0.rightTabId == tab.id }) {
                items.append(.singleTab(tab))
                handled.insert(tab.id)
            }
        }
        return items
    }

    var body: some View {
        HStack(spacing: 0) {
            WindowDragArea().frame(width: metrics.leadingInset)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(displayItems) { item in
                        switch item {
                        case .singleTab(let tab):
                            TabPill(tab: tab,
                                    isActive: tab.id == tabManager.activeTabId,
                                    namespace: pillNamespace,
                                    onSelect: { tabManager.setActiveTab(tab.id) },
                                    onClose: { tabManager.closeTab(tab.id) },
                                    onRename: { tabManager.renameTab(tab.id, to: $0) })
                                .onDrag {
                                    draggedTab = tab
                                    return NSItemProvider(object: tab.id.uuidString as NSString)
                                }
                                .onDrop(of: [.text], delegate: TabDropDelegate(tab: tab, tabManager: tabManager, draggedTab: $draggedTab))
                                .transition(.scale(scale: 0.85).combined(with: .opacity))
                        case .splitGroup(let group, let left, let right):
                            SplitTabGroupView(group: group, leftTab: left, rightTab: right,
                                              isActive: group.id == activeSplitGroupId,
                                              namespace: pillNamespace,
                                              onSelect: { tabManager.setActiveTab($0) },
                                              onClose: {
                                                  NotificationCenter.default.post(name: .closeSplitGroup, object: nil, userInfo: ["groupId": group.id])
                                              })
                                .transition(.scale(scale: 0.85).combined(with: .opacity))
                        }
                    }

                    NewTabButton { tabManager.createNewTab() }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
                .animation(Motion.snappy, value: tabManager.tabs.map(\.id))
                .animation(Motion.snappy, value: tabManager.activeTabId)
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)

            WindowDragArea()
                .frame(minWidth: 24, maxWidth: .infinity)

            HStack(spacing: 2) {
                IconButton(systemName: "command", help: "Command palette (⌘P)", action: onOpenPalette)
                IconButton(systemName: "gearshape", help: "Settings (⌘,)") { tabManager.openSettingsTab() }
            }
            .padding(.trailing, 10)
        }
        .frame(height: metrics.titlebarHeight)
        .background(WindowDragArea())
    }
}

struct TabPill: View {
    @EnvironmentObject private var settings: UserSettings
    @ObservedObject var tab: Tab
    let isActive: Bool
    let namespace: Namespace.ID
    let onSelect: () -> Void
    let onClose: () -> Void
    let onRename: (String) -> Void

    @State private var hovering = false
    @State private var isEditing = false
    @State private var editingName = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 7) {
            TabIcon(tab: tab, isActive: isActive)

            if isEditing {
                TextField("", text: $editingName)
                    .textFieldStyle(.plain)
                    .font(Typography.ui(12, weight: .medium))
                    .frame(minWidth: 50, maxWidth: 130)
                    .focused($fieldFocused)
                    .onSubmit(finishEditing)
                    .onExitCommand { isEditing = false }
                    .onChange(of: fieldFocused) { _, focused in if !focused && isEditing { finishEditing() } }
            } else {
                Text(tab.title)
                    .font(Typography.ui(12, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? settings.theme.textPrimary : settings.theme.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: 150)
            }

            ZStack {
                if tab.needsAttention && !isActive && !hovering {
                    PulsingDot(color: settings.theme.warning, size: 6)
                        .transition(.scale.combined(with: .opacity))
                } else if hovering || isActive {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(settings.theme.textTertiary)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(hovering ? settings.theme.surfaceRaised : .clear))
                    }
                    .buttonStyle(.plain)
                    .help("Close tab (⌘W)")
                    .transition(.opacity)
                }
            }
            .frame(width: 16, height: 16)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 28)
        .background {
            if isActive {
                Color.clear
                    .glassSurface(RoundedRectangle(cornerRadius: 9, style: .continuous), tint: settings.theme.accent)
                    .matchedGeometryEffect(id: "activeTab", in: namespace)
            } else if hovering {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(settings.theme.surfaceRaised.opacity(0.6))
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if !tab.isSettingsTab { startEditing() } }
        .simultaneousGesture(TapGesture().onEnded { if !isEditing { onSelect() } })
        .onHover { inside in withAnimation(Motion.quick) { hovering = inside } }
        .animation(Motion.snappy, value: tab.needsAttention)
        .contextMenu {
            if !tab.isSettingsTab {
                Button("Rename Tab…") { startEditing() }
                if tab.isCustomTitle { Button("Reset Title") { tab.resetToAutoTitle() } }
                Divider()
            }
            Button("Close Tab") { onClose() }
        }
    }

    private func startEditing() {
        editingName = tab.title
        isEditing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { fieldFocused = true }
    }

    private func finishEditing() {
        let name = editingName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { onRename(name) }
        isEditing = false
        fieldFocused = false
    }
}

struct TabIcon: View {
    @EnvironmentObject private var settings: UserSettings
    @ObservedObject var tab: Tab
    let isActive: Bool

    var body: some View {
        ZStack {
            if tab.isSettingsTab {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isActive ? settings.theme.accent : settings.theme.textTertiary)
            } else if let agent = tab.runningAgent {
                AgentBadge(agent: agent, size: 15)
                    .transition(.scale.combined(with: .opacity))
            } else if tab.isRunning {
                TabSpinner(color: settings.theme.accent)
                    .transition(.opacity)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isActive ? settings.theme.accent : settings.theme.textTertiary)
                    .transition(.opacity)
            }
        }
        .frame(width: 16, height: 16)
        .animation(Motion.snappy, value: tab.isRunning)
        .animation(Motion.snappy, value: tab.runningAgent)
    }
}

struct TabSpinner: View {
    let color: Color
    @State private var rotating = false

    var body: some View {
        Circle()
            .trim(from: 0.15, to: 0.85)
            .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: 11, height: 11)
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { rotating = true }
            }
    }
}

private struct NewTabButton: View {
    @EnvironmentObject private var settings: UserSettings
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? settings.theme.textPrimary : settings.theme.textTertiary)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? settings.theme.surfaceRaised.opacity(0.6) : .clear))
                .rotationEffect(.degrees(hovering ? 90 : 0))
        }
        .buttonStyle(.plain)
        .help("New tab (⌘T)")
        .onHover { inside in withAnimation(Motion.snappy) { hovering = inside } }
    }
}

struct SplitTabGroupView: View {
    @EnvironmentObject private var settings: UserSettings
    let group: SplitGroup
    let leftTab: Tab
    let rightTab: Tab
    let isActive: Bool
    let namespace: Namespace.ID
    let onSelect: (UUID) -> Void
    let onClose: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 2) {
            mini(leftTab, focused: group.focusedPane == 0)
            Image(systemName: group.direction == .horizontal ? "rectangle.split.2x1" : "rectangle.split.1x2")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(settings.theme.textTertiary)
            mini(rightTab, focused: group.focusedPane == 1)
            if hovering || isActive {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(settings.theme.textTertiary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help("Unsplit")
            }
        }
        .padding(.horizontal, 5)
        .frame(height: 28)
        .background {
            if isActive {
                Color.clear
                    .glassSurface(RoundedRectangle(cornerRadius: 9, style: .continuous), tint: settings.theme.accent)
                    .matchedGeometryEffect(id: "activeTab", in: namespace)
            } else if hovering {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(settings.theme.surfaceRaised.opacity(0.6))
            }
        }
        .onHover { inside in withAnimation(Motion.quick) { hovering = inside } }
    }

    private func mini(_ tab: Tab, focused: Bool) -> some View {
        HStack(spacing: 5) {
            TabIcon(tab: tab, isActive: focused && isActive)
            Text(tab.title)
                .font(Typography.ui(11.5, weight: focused && isActive ? .semibold : .medium))
                .foregroundStyle(focused && isActive ? settings.theme.textPrimary : settings.theme.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: 90)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(focused && isActive ? settings.theme.accentSoft : .clear))
        .contentShape(Rectangle())
        .onTapGesture { onSelect(tab.id) }
    }
}

// MARK: - Window chrome helpers

/// Lets empty title-bar space drag the window.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggableView { DraggableView() }
    func updateNSView(_ nsView: DraggableView, context: Context) {}
}

final class DraggableView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performZoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }
}

/// Title-bar geometry so tabs line up with the traffic lights.
@MainActor
final class WindowMetrics: ObservableObject {
    static let shared = WindowMetrics()
    @Published var titlebarHeight: CGFloat = 40
    @Published var leadingInset: CGFloat = Layout.trafficLightInset

    func update(from window: NSWindow) {
        let isFullScreen = window.styleMask.contains(.fullScreen)
        let measured = window.frame.height - window.contentLayoutRect.height
        let height = isFullScreen ? 40 : max(34, min(measured, 60))
        if abs(height - titlebarHeight) > 0.5 { titlebarHeight = height }
        var inset: CGFloat = 12
        if !isFullScreen, let zoom = window.standardWindowButton(.zoomButton), !zoom.isHidden {
            inset = zoom.frame.maxX + 14
        }
        if abs(inset - leadingInset) > 0.5 { leadingInset = inset }
    }
}

extension Notification.Name {
    static let closeSplitGroup = Notification.Name("CloseSplitGroup")
}
