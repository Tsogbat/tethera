import Foundation
import SwiftUI

/// Owns the window's tabs.
@MainActor
final class TabManager: ObservableObject {
    @Published private(set) var tabs: [Tab] = []
    @Published private(set) var activeTabId: UUID?

    /// Called when the last tab closes, so the window can close too.
    var onEmpty: (() -> Void)?

    init() {
        createNewTab()
    }

    var activeTab: Tab? {
        guard let activeTabId else { return nil }
        return tabs.first { $0.id == activeTabId }
    }

    var activeViewModel: BlockTerminalViewModel? {
        activeTab?.viewModel
    }

    @discardableResult
    func createNewTab(workingDirectory: String? = nil, activate: Bool = true) -> Tab {
        let directory = workingDirectory ?? activeTab?.viewModel?.workingDirectory
        let tab = Tab(workingDirectory: directory)
        wire(tab)
        withAnimation(Motion.snappy) {
            if let active = activeTabId, let index = tabs.firstIndex(where: { $0.id == active }) {
                tabs.insert(tab, at: index + 1)
            } else {
                tabs.append(tab)
            }
        }
        if activate { setActiveTab(tab.id) }
        return tab
    }

    /// Opens a tab that immediately runs a command (agents, sign-in flows).
    func openTab(running command: String) {
        let tab = createNewTab()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            tab.viewModel?.submit(command)
        }
    }

    private func wire(_ tab: Tab) {
        tab.viewModel?.onCloseRequest = { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.closeTab(tab.id)
        }
    }

    func setActiveTab(_ tabId: UUID) {
        guard tabs.contains(where: { $0.id == tabId }) else { return }
        for tab in tabs { tab.isActive = tab.id == tabId }
        withAnimation(Motion.snappy) { activeTabId = tabId }
    }

    func selectTab(offset: Int) {
        guard let active = activeTabId, let index = tabs.firstIndex(where: { $0.id == active }), !tabs.isEmpty else { return }
        let next = (index + offset + tabs.count) % tabs.count
        setActiveTab(tabs[next].id)
    }

    func selectTab(number: Int) {
        guard !tabs.isEmpty else { return }
        let index = number >= 9 ? tabs.count - 1 : number - 1
        guard tabs.indices.contains(index) else { return }
        setActiveTab(tabs[index].id)
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]
        tab.shutdown()
        withAnimation(Motion.snappy) {
            _ = tabs.remove(at: index)
        }
        NotificationCenter.default.post(name: .tabClosed, object: nil, userInfo: ["tabId": id])
        if tabs.isEmpty {
            activeTabId = nil
            onEmpty?()
            return
        }
        if activeTabId == id {
            setActiveTab(tabs[min(index, tabs.count - 1)].id)
        }
    }

    func closeActiveTab() {
        if let id = activeTabId { closeTab(id) }
    }

    func closeAll() {
        for tab in tabs { tab.shutdown() }
    }

    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              tabs.indices.contains(sourceIndex),
              destinationIndex >= 0, destinationIndex <= tabs.count else { return }
        let tab = tabs.remove(at: sourceIndex)
        let insertIndex = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        tabs.insert(tab, at: insertIndex)
    }

    func tab(with id: UUID) -> Tab? {
        tabs.first { $0.id == id }
    }

    func renameTab(_ tabId: UUID, to newTitle: String) {
        tab(with: tabId)?.rename(to: newTitle)
    }

    func openSettingsTab() {
        if let existing = tabs.first(where: { $0.isSettingsTab }) {
            setActiveTab(existing.id)
            return
        }
        let settings = Tab.settings()
        withAnimation(Motion.snappy) { tabs.append(settings) }
        setActiveTab(settings.id)
    }
}

extension Notification.Name {
    static let tabClosed = Notification.Name("TabClosed")
}
