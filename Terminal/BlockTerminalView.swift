import SwiftUI

struct BlockTerminalView: View {
    @ObservedObject var viewModel: BlockTerminalViewModel
    @State private var commandInput: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            // Modern, subtle gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    SwiftUI.Color(red: 0.06, green: 0.07, blue: 0.10),
                    SwiftUI.Color(red: 0.09, green: 0.11, blue: 0.15)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with working directory
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 14, weight: .medium))
                        Text(viewModel.displayWorkingDirectory)
                            .font(getFont(size: 13))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(SwiftUI.Color.white.opacity(0.03))
                    .cornerRadius(8)
                    
                    Spacer()
                }
                .padding(.top, 20)
                .padding(.horizontal, 20)

                // Terminal blocks with proper safe area handling
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.blocks) { block in
                                TerminalBlockView(block: block)
                                    .id(block.id)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 100) // Ensure content doesn't overlap with input
                    }
                    .onChange(of: viewModel.blocks.count) { _, _ in
                        if let last = viewModel.blocks.last {
                            withAnimation(.easeOut(duration: 0.3)) {
                                scrollProxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Modern command input area
                VStack(spacing: 0) {
                    Divider()
                        .background(SwiftUI.Color.white.opacity(0.1))
                    
                    HStack(spacing: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: "chevron.right")
                                .foregroundColor(.green)
                                .font(.system(size: 14, weight: .semibold))
                            
                            TextField("", text: $commandInput)
                                .font(getFont(size: 15))
                                .textFieldStyle(PlainTextFieldStyle())
                                .foregroundColor(.white)
                                .accentColor(.green)
                                .focused($isInputFocused)
                                .onAppear { isInputFocused = true }
                                .onSubmit { submitCommand() }
                                .overlay(
                                    Group {
                                        if commandInput.isEmpty {
                                            HStack {
                                                Text("Enter command...")
                                                    .font(getFont(size: 15))
                                                    .foregroundColor(.white.opacity(0.6))
                                                    .padding(.leading, 12)
                                                Spacer()
                                            }
                                        }
                                    }
                                )
                        }
                        
                        Button(action: submitCommand) {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 20))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(commandInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(SwiftUI.Color.white.opacity(0.03))
                    )
                }
            }
        }
        .safeAreaInset(edge: .top) {
            SwiftUI.Color.clear.frame(height: 0)
        }
    }

    private func submitCommand() {
        let trimmed = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        commandInput = ""
        guard !trimmed.isEmpty else { return }
        viewModel.runShellCommand(trimmed)
        isInputFocused = true
    }
    
    private func getFont(size: CGFloat) -> Font {
        if FontLoader.shared.isFontAvailable("JetBrainsMono-Medium") {
            return .custom("JetBrainsMono-Medium", size: size)
        } else if FontLoader.shared.isFontAvailable("JetBrainsMono-Regular") {
            return .custom("JetBrainsMono-Regular", size: size)
        } else {
            return .system(size: size, design: .monospaced)
        }
    }
}



// Separate view for terminal blocks for better organization
struct TerminalBlockView: View {
    let block: TerminalBlock
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Command input
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .foregroundColor(.green)
                    .font(.system(size: 12, weight: .semibold))
                
                Text(block.input)
                    .font(getFont(size: 14))
                    .foregroundColor(.white)
                    .textSelection(.enabled)
                
                Spacer()
                
                // Working directory indicator
                if let workingDir = block.workingDirectory {
                    let displayPath = workingDir.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path) ? 
                        "~\(String(workingDir.dropFirst(FileManager.default.homeDirectoryForCurrentUser.path.count)))" : workingDir
                    Text(displayPath)
                        .font(getFont(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            
            // Command output
            if !block.output.isEmpty {
                Text(block.output)
                    .font(getFont(size: 13))
                    .foregroundColor(.white.opacity(0.8))
                    .textSelection(.enabled)
                    .padding(.leading, 20)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(SwiftUI.Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(SwiftUI.Color.white.opacity(0.05), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private func getFont(size: CGFloat) -> Font {
        if FontLoader.shared.isFontAvailable("JetBrainsMono-Medium") {
            return .custom("JetBrainsMono-Medium", size: size)
        } else if FontLoader.shared.isFontAvailable("JetBrainsMono-Regular") {
            return .custom("JetBrainsMono-Regular", size: size)
        } else {
            return .system(size: size, design: .monospaced)
        }
    }
}
