import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = BlockTerminalViewModel()
    var body: some View {
        BlockTerminalView(viewModel: viewModel)
    }
}

#Preview {
    ContentView()
}
