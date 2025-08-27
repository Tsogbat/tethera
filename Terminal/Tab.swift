import Foundation
import SwiftUI
import Combine

/// Represents a terminal tab with its own session and view model
class Tab: ObservableObject, Identifiable, Transferable {
    let id = UUID()
    @Published var title: String
    @Published var viewModel: BlockTerminalViewModel
    @Published var isActive: Bool = false
    
    init(title: String = "Terminal") {
        self.title = title
        self.viewModel = BlockTerminalViewModel()
        
        // Auto-update title when blocks change
        viewModel.objectWillChange.sink { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.updateTitle()
            }
        }.store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    /// Update tab title based on current working directory or last command
    func updateTitle() {
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
    
    // MARK: - Transferable
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.id.uuidString)
    }
}
