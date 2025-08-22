import SwiftUI

struct BlockTerminalView: View {
    @ObservedObject var viewModel: BlockTerminalViewModel
    @State private var commandInput: String = ""
    @FocusState private var isInputFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.blocks) { block in
                            TerminalBlockView(block: block, theme: viewModel.theme)
                                .padding(.bottom, 8)
                                .background(viewModel.selectedBlockID == block.id ? SwiftUI.Color.gray.opacity(0.2) : SwiftUI.Color.clear)
                                .onTapGesture {
                                    viewModel.selectedBlockID = block.id
                                }
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.blocks.count) { oldValue, newValue in
                    if let last = viewModel.blocks.last {
                        scrollProxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            Divider()
            HStack(spacing: 12) {
                TextField("Type a command...", text: $commandInput)
                    .font(.custom("JetBrainsMono-Regular", size: 16, relativeTo: .body))
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                    .focused($isInputFocused)
                    .onAppear { isInputFocused = true }
                    .onSubmit {
                        let input = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !input.isEmpty {
                            commandInput = ""
                            runCommand(input)
                        }
                    }
                Button(action: {
                    let input = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !input.isEmpty {
                        commandInput = ""
                        runCommand(input)
                    }
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.accentColor)
                        .shadow(color: .accentColor.opacity(0.2), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    SwiftUI.Color(red: 0.08, green: 0.09, blue: 0.13),
                    SwiftUI.Color(red: 0.13, green: 0.15, blue: 0.20)
                ]),
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .overlay(
            CommandPaletteView(isPresented: $viewModel.isPalettePresented, actions: viewModel.paletteActions)
        )
        .sheet(isPresented: $viewModel.isSettingsPresented) {
            TerminalSettingsView(viewModel: viewModel)
        }
        .onAppear {
            viewModel.loadFont()
        }
    }

    private func runCommand(_ input: String) {
        isInputFocused = true
        viewModel.runShellCommand(input)
    }
}

struct TerminalBlockView: View {
    let block: TerminalBlock
    let theme: TerminalTheme
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "terminal.fill")
                    .foregroundColor(theme.prompt)
                    .font(.system(size: 18))
                    .padding(.top, 2)
                Text(block.input)
                    .font(.custom("JetBrainsMono-Regular", size: 16, relativeTo: .body))
                    .foregroundColor(theme.prompt)
                    .textSelection(.enabled)
            }
            Divider().background(theme.blockDivider)
            Text(block.output)
                .font(.custom("JetBrainsMono-Regular", size: 15, relativeTo: .body))
                .foregroundColor(theme.foreground)
                .textSelection(.enabled)
                .modifier(LinkifyModifier(theme: theme))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 4)
        )
        .padding(.vertical, 6)
    }
}

struct LinkifyModifier: ViewModifier {
    let theme: TerminalTheme
    func body(content: Content) -> some View {
        content
            .onAppear {}
            // TODO: Implement regex link/file path detection and clickable links
    }
}
