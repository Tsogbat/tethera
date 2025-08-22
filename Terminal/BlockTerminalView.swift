import SwiftUI

struct BlockTerminalView: View {
    @ObservedObject var viewModel: BlockTerminalViewModel
    @State private var commandInput: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    SwiftUI.Color(red: 0.08, green: 0.09, blue: 0.13),
                    SwiftUI.Color(red: 0.13, green: 0.15, blue: 0.20)
                ]),
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(viewModel.blocks) { block in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Image(systemName: "chevron.right.circle.fill")
                                            .foregroundColor(.green)
                                        Text(block.input)
                                            .foregroundColor(.white)
                                    }
                                    .padding(.bottom, 2)
                                    Text(block.output)
                                        .foregroundColor(.gray)
                                        .textSelection(.enabled)
                                }
                                .padding()
                                .background(
                                    SwiftUI.Color.white.opacity(0.05)
                                        .blur(radius: 0.5)
                                )
                                .cornerRadius(12)
                                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
                                .id(block.id)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                    }
                    .onChange(of: viewModel.blocks.count) { _, _ in
                        if let last = viewModel.blocks.last {
                            scrollProxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }

                HStack {
                    Image(systemName: "terminal.fill")
                        .foregroundColor(.green)
                    TextField("Enter command...", text: $commandInput)
                        .textFieldStyle(PlainTextFieldStyle())
                        .foregroundColor(.white)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 8)
                        .background(SwiftUI.Color.white.opacity(0.08))
                        .cornerRadius(8)
                        .focused($isInputFocused)
                        .onAppear { isInputFocused = true }
                        .onSubmit { submitCommand() }
                    Button(action: submitCommand) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: -2)
            }
        }
        .font(.custom("JetBrainsMono-Medium", size: 15))
    }

    private func submitCommand() {
        let trimmed = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        commandInput = "" // Clear input immediately, before any return
        guard !trimmed.isEmpty else { return }
        viewModel.runShellCommand(trimmed)
        isInputFocused = true
    }
}
