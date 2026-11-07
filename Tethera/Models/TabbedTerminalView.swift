import SwiftUI
import UniformTypeIdentifiers

enum SplitDirection: Equatable {
    case horizontal  // side by side
    case vertical    // stacked
}

struct SplitGroup: Identifiable, Equatable {
    let id: UUID
    var leftTabId: UUID
    var rightTabId: UUID
    var direction: SplitDirection
    var focusedPane: Int = 0

    func contains(_ tabId: UUID) -> Bool {
        leftTabId == tabId || rightTabId == tabId
    }
}

/// The window: title-bar tabs, the active tab (or a split pair), and app overlays.
struct TabbedTerminalView: View {
    @StateObject private var tabManager = TabManager()
    @EnvironmentObject private var settings: UserSettings
    @ObservedObject private var errorReporter = AppErrorReporter.shared
    @ObservedObject private var history = CommandHistoryManager.shared
    @ObservedObject private var metrics = WindowMetrics.shared

    @State private var splitGroups: [SplitGroup] = []
    @State private var activeSplitGroupId: UUID?
    @State private var dropEdge: DropEdge?
    @State private var isPaletteOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activeSplitGroup: SplitGroup? {
        guard let id = activeSplitGroupId else { return nil }
        return splitGroups.first { $0.id == id }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TabBarContent(tabManager: tabManager, splitGroups: splitGroups, activeSplitGroupId: activeSplitGroupId,
                              onOpenPalette: { togglePalette() })
                    .zIndex(2)

                GeometryReader { geo in
                    ZStack {
                        if let group = activeSplitGroup {
                            splitContent(for: group)
                                .transition(.opacity)
                        } else {
                            singleContent
                                .transition(.opacity)
                        }
                        if let edge = dropEdge {
                            DropIndicatorOverlay(edge: edge, size: geo.size)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    .animation(Motion.fade, value: dropEdge)
                    .animation(Motion.adaptive(Motion.smooth, reduceMotion: reduceMotion), value: activeSplitGroupId)
                    .onDrop(of: [.text], delegate: SplitDropDelegate(
                        tabManager: tabManager,
                        splitGroups: $splitGroups,
                        activeSplitGroupId: $activeSplitGroupId,
                        dropEdge: $dropEdge,
                        containerSize: geo.size
                    ))
                }
                // Scroll views extend under the title bar on macOS 26; keep blocks below the tabs.
                .clipped()
            }

            if isPaletteOpen {
                CommandPaletteView(actions: paletteActions, onDismiss: { togglePalette() })
                    .transition(.opacity)
                    .zIndex(10)
            }
            if history.isSearching {
                SearchOverlayView(historyManager: history, onJump: jump(to:), onDismiss: {
                    withAnimation(Motion.snappy) { history.closeSearch() }
                    tabManager.activeViewModel?.insert("")
                })
                .transition(.opacity)
                .zIndex(11)
            }
        }
        .overlay(alignment: .top) {
            if let error = errorReporter.current {
                ErrorBannerView(error: error) { errorReporter.clear() }
                    .padding(.top, metrics.titlebarHeight + 6)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(20)
            }
        }
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: isPaletteOpen)
        .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: history.isSearching)
        .animation(Motion.smooth, value: errorReporter.current)
        .ignoresSafeArea(.container, edges: .top)
        .background(
            WindowBackdrop(tint: settings.theme.backgroundNS, opacity: settings.terminal.windowOpacity)
                .ignoresSafeArea()
        )
        .preferredColorScheme(settings.themeConfiguration.isDarkMode ? .dark : .light)
        .animation(.easeInOut(duration: 0.25), value: settings.selectedThemeId)
        .onReceive(AppCommands.shared.publisher) { handle($0) }
        .onReceive(NotificationCenter.default.publisher(for: .tabClosed)) { note in
            guard let tabId = note.userInfo?["tabId"] as? UUID else { return }
            withAnimation(Motion.smooth) {
                splitGroups.removeAll { $0.contains(tabId) }
                if let active = activeSplitGroupId, !splitGroups.contains(where: { $0.id == active }) {
                    activeSplitGroupId = nil
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeSplitGroup)) { note in
            guard let groupId = note.userInfo?["groupId"] as? UUID else { return }
            withAnimation(Motion.smooth) {
                splitGroups.removeAll { $0.id == groupId }
                if activeSplitGroupId == groupId { activeSplitGroupId = nil }
            }
        }
        .onChange(of: tabManager.activeTabId) { _, newId in
            guard let newId else { return }
            dropEdge = nil
            if let index = splitGroups.firstIndex(where: { $0.contains(newId) }) {
                activeSplitGroupId = splitGroups[index].id
                splitGroups[index].focusedPane = newId == splitGroups[index].leftTabId ? 0 : 1
            } else {
                activeSplitGroupId = nil
            }
        }
        .onAppear {
            tabManager.onEmpty = {
                NSApp.keyWindow?.close()
            }
            #if DEBUG
            DebugState.tabManager = tabManager
            #endif
        }
    }

    // MARK: Content

    @ViewBuilder
    private var singleContent: some View {
        if let tab = tabManager.activeTab {
            if tab.isSettingsTab {
                NativeSettingsView()
            } else if let viewModel = tab.viewModel {
                TerminalPaneView(viewModel: viewModel, isActivePane: true)
                    .id(tab.id)
            }
        }
    }

    @ViewBuilder
    private func splitContent(for group: SplitGroup) -> some View {
        let left = tabManager.tab(with: group.leftTabId)
        let right = tabManager.tab(with: group.rightTabId)
        if group.direction == .horizontal {
            HSplitView {
                if let left { pane(left, index: 0, group: group) }
                if let right { pane(right, index: 1, group: group) }
            }
        } else {
            VSplitView {
                if let left { pane(left, index: 0, group: group) }
                if let right { pane(right, index: 1, group: group) }
            }
        }
    }

    @ViewBuilder
    private func pane(_ tab: Tab, index: Int, group: SplitGroup) -> some View {
        let focused = group.focusedPane == index
        Group {
            if let viewModel = tab.viewModel {
                TerminalPaneView(viewModel: viewModel, isActivePane: focused)
            } else {
                NativeSettingsView()
            }
        }
        .frame(minWidth: 280, minHeight: 200)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(settings.theme.accent.opacity(focused ? 0.35 : 0), lineWidth: 1)
                .padding(3)
                .allowsHitTesting(false)
                .animation(Motion.quick, value: focused)
        }
        .opacity(focused ? 1 : 0.86)
        .simultaneousGesture(TapGesture().onEnded {
            if let i = splitGroups.firstIndex(where: { $0.id == group.id }) {
                splitGroups[i].focusedPane = index
            }
            tabManager.setActiveTab(tab.id)
        })
    }

    // MARK: Commands

    private var activeViewModel: BlockTerminalViewModel? {
        tabManager.activeViewModel
    }

    private func handle(_ command: AppCommand) {
        switch command {
        case .newTab:
            tabManager.createNewTab()
        case .closeTab:
            if isPaletteOpen { togglePalette(); return }
            if history.isSearching { history.closeSearch(); return }
            tabManager.closeActiveTab()
        case .splitRight:
            split(.horizontal)
        case .splitDown:
            split(.vertical)
        case .nextTab:
            tabManager.selectTab(offset: 1)
        case .previousTab:
            tabManager.selectTab(offset: -1)
        case .selectTab(let number):
            tabManager.selectTab(number: number)
        case .clear:
            activeViewModel?.clearBlocks()
        case .palette:
            togglePalette()
        case .search:
            withAnimation(Motion.snappy) {
                if history.isSearching { history.closeSearch() } else { history.openSearch() }
            }
        case .toggleAIMode:
            guard let viewModel = activeViewModel else { return }
            viewModel.aiModeSticky.toggle()
            viewModel.insert("")
        case .openSettings:
            tabManager.openSettingsTab()
        case .fontBigger:
            settings.adjustFontSize(by: 1)
        case .fontSmaller:
            settings.adjustFontSize(by: -1)
        case .fontReset:
            settings.resetFontSize()
        case .previousBlock:
            activeViewModel?.selectAdjacent(-1)
        case .nextBlock:
            activeViewModel?.selectAdjacent(1)
        case .copyBlock:
            _ = activeViewModel?.copySelectedBlock()
        case .restartShell:
            activeViewModel?.restartShell()
        case .interrupt:
            activeViewModel?.interrupt()
        case .runInNewTab(let commandLine):
            tabManager.openTab(running: commandLine)
        case .launchAgent(let agent):
            if let viewModel = activeViewModel, !viewModel.isRunning {
                viewModel.launchAgent(agent)
            } else {
                tabManager.openTab(running: agent.interactiveCommand(prompt: nil))
            }
        #if DEBUG
        case .runInActiveTab(let commandLine):
            activeViewModel?.submit(commandLine)
        case .debugInsert(let text):
            activeViewModel?.insert(text)
        case .debugAsk(let question):
            activeViewModel?.ask(question)
        case .debugGenerate(let request):
            activeViewModel?.generateCommand(from: request)
        case .debugSendKeys(let keys):
            activeViewModel?.debugSendKeys(keys)
        #endif
        }
    }

    private func togglePalette() {
        isPaletteOpen.toggle()
        if !isPaletteOpen { activeViewModel?.insert("") }
    }

    private func split(_ direction: SplitDirection) {
        guard let active = tabManager.activeTab, !active.isSettingsTab else { return }
        let newTab = tabManager.createNewTab(activate: false)
        withAnimation(Motion.smooth) {
            splitGroups.removeAll { $0.contains(active.id) }
            let group = SplitGroup(id: UUID(), leftTabId: active.id, rightTabId: newTab.id, direction: direction, focusedPane: 1)
            splitGroups.append(group)
            activeSplitGroupId = group.id
        }
        tabManager.setActiveTab(newTab.id)
    }

    private func jump(to entry: CommandHistoryManager.HistoryEntry) {
        withAnimation(Motion.snappy) { history.closeSearch() }
        if let tabId = entry.tabId, let tab = tabManager.tab(with: tabId), tab.viewModel?.block(entry.id) != nil {
            tabManager.setActiveTab(tabId)
            tab.viewModel?.reveal(entry.id)
        } else {
            activeViewModel?.insert(entry.command)
        }
    }

    private var paletteActions: [PaletteAction] {
        var actions: [PaletteAction] = [
            PaletteAction(title: "New Tab", icon: "plus.square", shortcut: "⌘T") { handle(.newTab) },
            PaletteAction(title: "Split Right", icon: "rectangle.split.2x1", shortcut: "⌘D") { handle(.splitRight) },
            PaletteAction(title: "Split Down", icon: "rectangle.split.1x2", shortcut: "⇧⌘D") { handle(.splitDown) },
            PaletteAction(title: "Close Tab", icon: "xmark.square", shortcut: "⌘W") { tabManager.closeActiveTab() },
            PaletteAction(title: "Clear Blocks", icon: "eraser", shortcut: "⌘K") { handle(.clear) },
            PaletteAction(title: "Search History", icon: "magnifyingglass", shortcut: "⌘F") { handle(.search) },
            PaletteAction(title: "Toggle AI Mode", icon: "sparkle", shortcut: "⌘I") { handle(.toggleAIMode) },
            PaletteAction(title: "Restart Shell", icon: "arrow.clockwise") { handle(.restartShell) },
            PaletteAction(title: "Settings", icon: "gearshape", shortcut: "⌘,") { handle(.openSettings) },
            PaletteAction(title: "Re-detect AI CLIs", icon: "arrow.triangle.2.circlepath") {
                Task { await AgentDetector.shared.refresh() }
            },
        ]
        for agent in AgentCLI.allCases where AgentDetector.shared.status(for: agent)?.isInstalled ?? false {
            actions.append(PaletteAction(title: "Open \(agent.displayName)", subtitle: "Interactive session in this tab", agent: agent) {
                handle(.launchAgent(agent))
            })
        }
        for agent in AgentCLI.allCases {
            actions.append(PaletteAction(title: "Use \(agent.displayName) for AI", subtitle: agent.tagline, agent: agent,
                                         isChecked: settings.aiSettings.provider == agent) {
                settings.aiSettings.provider = agent
            })
        }
        for preset in UserSettings.presets {
            actions.append(PaletteAction(title: "Theme: \(preset.name)", icon: "paintpalette",
                                         isChecked: settings.selectedThemeId == preset.id) {
                settings.applyPreset(preset)
            })
        }
        return actions
    }
}

// MARK: - Drag to split

enum DropEdge: Equatable {
    case left, right, top, bottom
}

struct DropIndicatorOverlay: View {
    @EnvironmentObject private var settings: UserSettings
    let edge: DropEdge
    let size: CGSize

    var body: some View {
        ZStack(alignment: alignment) {
            Color.clear
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(settings.theme.accent.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(settings.theme.accent.opacity(0.5), lineWidth: 1.5))
                .frame(width: isHorizontal ? size.width * 0.45 : nil, height: isHorizontal ? nil : size.height * 0.45)
                .padding(10)
        }
    }

    private var isHorizontal: Bool { edge == .left || edge == .right }

    private var alignment: Alignment {
        switch edge {
        case .left: return .leading
        case .right: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        }
    }
}

final class SplitDropDelegate: DropDelegate {
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
    func dropEntered(info: DropInfo) { dropEdge = edge(for: info) }
    func dropExited(info: DropInfo) { dropEdge = nil }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        dropEdge = edge(for: info)
        return DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        let edge = dropEdge ?? edge(for: info)
        guard let provider = info.itemProviders(for: [UTType.text.identifier]).first
                ?? info.itemProviders(for: [UTType.plainText.identifier]).first else {
            dropEdge = nil
            return false
        }
        _ = provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                defer { self.dropEdge = nil }
                guard let string = object as? String,
                      let uuid = UUID(uuidString: string),
                      let dropped = self.tabManager.tab(with: uuid), !dropped.isSettingsTab,
                      let current = self.tabManager.activeTabId, dropped.id != current else { return }
                self.splitGroups.removeAll { $0.contains(dropped.id) || $0.contains(current) }
                let direction: SplitDirection = (edge == .left || edge == .right) ? .horizontal : .vertical
                let leadingDropped = edge == .left || edge == .top
                let group = SplitGroup(id: UUID(),
                                       leftTabId: leadingDropped ? dropped.id : current,
                                       rightTabId: leadingDropped ? current : dropped.id,
                                       direction: direction,
                                       focusedPane: leadingDropped ? 0 : 1)
                withAnimation(Motion.smooth) {
                    self.splitGroups.append(group)
                    self.activeSplitGroupId = group.id
                }
                self.tabManager.setActiveTab(dropped.id)
            }
        }
        return true
    }

    private func edge(for info: DropInfo) -> DropEdge {
        let x = info.location.x / max(containerSize.width, 1)
        let y = info.location.y / max(containerSize.height, 1)
        if min(x, 1 - x) < min(y, 1 - y) {
            return x < 0.5 ? .left : .right
        }
        return y < 0.5 ? .top : .bottom
    }
}
