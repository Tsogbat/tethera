import SwiftUI

struct TerminalSettingsView: View {
    @ObservedObject var viewModel: BlockTerminalViewModel
    @State private var shellPath: String = "/bin/zsh"
    @State private var fontSize: Double = 15
    @State private var colorScheme: String = "Default"
    var body: some View {
        Form {
            Section(header: Text("Shell")) {
                TextField("Shell Path", text: $shellPath)
            }
            Section(header: Text("Font")) {
                Stepper(value: $fontSize, in: 10...32, step: 1) {
                    Text("Font Size: \(Int(fontSize))")
                }
            }
            Section(header: Text("Color Scheme")) {
                Picker("Color Scheme", selection: $colorScheme) {
                    Text("Default").tag("Default")
                    Text("Solarized Dark").tag("Solarized Dark")
                    Text("Solarized Light").tag("Solarized Light")
                }
            }
        }
        .padding()
        .frame(width: 350)
        .onAppear {
            shellPath = viewModel.blocks.last?.workingDirectory ?? "/bin/zsh"
        }
    }
}
