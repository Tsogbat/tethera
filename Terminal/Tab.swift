import Foundation
import SwiftUI

/// Represents a terminal tab with its own session and view model
class Tab: ObservableObject, Identifiable, Transferable {
    let id = UUID()
    @Published var title: String
    @Published var viewModel: BlockTerminalViewModel
    @Published var isActive: Bool = false
    
    init(title: String = "Terminal") {
        self.title = title
        self.viewModel = BlockTerminalViewModel()
    }
    
    /// Update tab title based on current working directory
    func updateTitle() {
        let displayDir = viewModel.displayWorkingDirectory
        self.title = displayDir == "~" ? "Terminal" : displayDir.components(separatedBy: "/").last ?? "Terminal"
    }
    
    // MARK: - Transferable
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.id.uuidString)
    }
}
