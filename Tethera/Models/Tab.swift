import Foundation
import SwiftUI
import Combine

/// Represents a terminal tab with its own session and view model
@MainActor
class Tab: ObservableObject, Identifiable {
    let id = UUID()
    @Published var title: String
    @Published var viewModel: BlockTerminalViewModel
    @Published var isActive: Bool = false
    @Published var isCustomTitle: Bool = false
    @Published var isSettingsTab: Bool = false
    
    init(title: String = "Terminal") {
        self.title = title
        self.viewModel = BlockTerminalViewModel()
        
        // Auto-update title when blocks change (only if not custom)
        viewModel.objectWillChange.sink { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if self?.isCustomTitle == false && self?.isSettingsTab == false {
                    self?.updateTitle()
                }
            }
        }.store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    /// Update tab title based on current working directory or last command
    func updateTitle() {
        // Do not auto-update for Settings tab
        if isSettingsTab { return }
        
        // Try to get the last command first
        if let lastBlock = viewModel.blocks.last, !lastBlock.input.isEmpty {
            let command = lastBlock.input.components(separatedBy: " ").first ?? ""
            if !command.isEmpty && command != "cd" {
                self.title = command
                return
            }
        }
        
        // Fall back to directory name
        let displayDir = viewModel.displayWorkingDirectory
        if displayDir == "~" {
            self.title = "Home"
        } else {
            let dirName = displayDir.components(separatedBy: "/").last ?? "Terminal"
            self.title = dirName.isEmpty ? "Terminal" : dirName
        }
    }
    
    /// Rename the tab with a custom title
    func rename(to newTitle: String) {
        let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            self.title = trimmedTitle
            self.isCustomTitle = true
        }
    }
    
    /// Reset to auto-generated title
    func resetToAutoTitle() {
        self.isCustomTitle = false
        updateTitle()
    }
    
}

