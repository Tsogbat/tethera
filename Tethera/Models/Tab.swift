import Foundation
import SwiftUI
import Combine
import UserNotifications

/// A tab: a terminal session, or the settings page.
@MainActor
final class Tab: ObservableObject, Identifiable {
    let id = UUID()
    let isSettingsTab: Bool
    let viewModel: BlockTerminalViewModel?

    @Published private(set) var title: String
    @Published private(set) var isCustomTitle = false
    @Published private(set) var isRunning = false
    @Published private(set) var runningAgent: AgentCLI?
    @Published var needsAttention = false
    @Published var isActive = false {
        didSet { if isActive { needsAttention = false } }
    }

    private var cancellables = Set<AnyCancellable>()

    init(workingDirectory: String? = nil) {
        self.isSettingsTab = false
        let viewModel = BlockTerminalViewModel(workingDirectory: workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path)
        self.viewModel = viewModel
        self.title = viewModel.title
        viewModel.tabID = id

        viewModel.$title
            .sink { [weak self] newTitle in
                guard let self, !self.isCustomTitle else { return }
                self.title = newTitle
            }
            .store(in: &cancellables)
        viewModel.$runningBlockID
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak self] running in self?.isRunning = running }
            .store(in: &cancellables)
        viewModel.$runningAgent
            .removeDuplicates()
            .sink { [weak self] agent in self?.runningAgent = agent }
            .store(in: &cancellables)
        viewModel.onAttention = { [weak self] message in
            self?.raiseAttention(message)
        }
    }

    private init(settingsTitle: String) {
        self.isSettingsTab = true
        self.viewModel = nil
        self.title = settingsTitle
    }

    static func settings() -> Tab {
        Tab(settingsTitle: "Settings")
    }

    func rename(to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        title = trimmed
        isCustomTitle = true
    }

    func resetToAutoTitle() {
        isCustomTitle = false
        title = viewModel?.title ?? title
    }

    func shutdown() {
        viewModel?.shutdown()
    }

    private func raiseAttention(_ message: String) {
        let appActive = NSApp.isActive
        if !isActive || !appActive {
            withAnimation(Motion.bouncy) { needsAttention = true }
        }
        if !appActive {
            AttentionNotifier.post(title: title, body: message)
            NSApp.requestUserAttention(.informationalRequest)
        }
    }
}

/// macOS notifications for agents waiting on the user. Requires a real app bundle.
enum AttentionNotifier {
    private static var authorized = false
    private static var requested = false

    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    static func post(title: String, body: String) {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        let send = {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
        if authorized {
            send()
        } else if !requested {
            requested = true
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                authorized = granted
                if granted { send() }
            }
        }
    }
}
