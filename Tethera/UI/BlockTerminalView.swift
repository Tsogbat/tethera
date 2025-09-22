import SwiftUI

extension Notification.Name {
    static let restoreTerminalFocus = Notification.Name("restoreTerminalFocus")
    static let openSettingsTab = Notification.Name("openSettingsTab")
}

struct BlockTerminalView: View {
    @ObservedObject var viewModel: BlockTerminalViewModel
    @EnvironmentObject private var userSettings: UserSettings
    @State private var commandInput: String = ""
    @FocusState private var isInputFocused: Bool
    @StateObject private var autocompleteEngine = AutocompleteEngine()
    let isActivePane: Bool
    @State private var hasUsedArrowKeys = false

    var body: some View {
        ZStack {
            // Use container background (set in TabbedTerminalView) for a unified look
            SwiftUI.Color.clear
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with working directory
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundColor(userSettings.themeConfiguration.accentColor.color)
                            .font(.system(size: 14, weight: .medium))
                        Text(viewModel.displayWorkingDirectory)
                            .font(getFont(size: CGFloat(userSettings.themeConfiguration.fontSize)))
                            .foregroundColor(userSettings.themeConfiguration.textColor.color)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        (userSettings.themeConfiguration.isDarkMode ? SwiftUI.Color.white : SwiftUI.Color.black).opacity(0.05)
                    )
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
                    .scrollIndicators(.hidden)
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
                    // Autocomplete suggestions overlay
                    if autocompleteEngine.isShowingSuggestions && !autocompleteEngine.suggestions.isEmpty {
                        VStack {
                            Spacer()
                            HStack {
                                AutocompleteSuggestionView(
                                    suggestions: autocompleteEngine.suggestions,
                                    onSuggestionSelected: { suggestion in
                                        commandInput = autocompleteEngine.getCompletion(for: commandInput, suggestion: suggestion)
                                        autocompleteEngine.clearSuggestions()
                                        // Add space after completion for better UX
                                        if suggestion.type == .command {
                                            commandInput += " "
                                        }
                                    },
                                    onArrowNavigation: { index in
                                        autocompleteEngine.updateSelectedIndex(index, currentInput: commandInput)
                                    },
                                    selectedIndex: $autocompleteEngine.selectedSuggestionIndex
                                )
                                .frame(maxWidth: 400)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                        }
                    }
                    
                    Divider()
                        .background(
                            (userSettings.themeConfiguration.isDarkMode ? SwiftUI.Color.white.opacity(0.1) : SwiftUI.Color.black.opacity(0.06))
                        )
                    
                    HStack(spacing: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: "chevron.right")
                                .foregroundColor(userSettings.themeConfiguration.accentColor.color)
                                .font(.system(size: 14, weight: .semibold))
                            
                            ZStack(alignment: .leading) {
                                TextField("", text: $commandInput)
                                    .font(getFont(size: CGFloat(userSettings.themeConfiguration.fontSize)))
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .foregroundColor(userSettings.themeConfiguration.textColor.color)
                                    .accentColor(userSettings.themeConfiguration.accentColor.color)
                                    .focused($isInputFocused)
                                    .onAppear { 
                                        if isActivePane {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                isInputFocused = true
                                            }
                                        }
                                    }
                                    .onChange(of: isActivePane) { _, newValue in
                                        if newValue {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                                isInputFocused = true
                                            }
                                        }
                                    }
                                    .onReceive(NotificationCenter.default.publisher(for: .restoreTerminalFocus)) { _ in
                                        if isActivePane {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                isInputFocused = true
                                            }
                                        }
                                    }
                                    .onChange(of: commandInput) { _, newValue in
                                        hasUsedArrowKeys = false // Reset arrow key state when typing
                                        if isInputFocused {
                                            autocompleteEngine.getSuggestions(for: newValue, in: viewModel.workingDirectory)
                                        }
                                    }
                                    .onSubmit { 
                                        if autocompleteEngine.isShowingSuggestions {
                                            autocompleteEngine.clearSuggestions()
                                        }
                                        submitCommand() 
                                    }
                                    .onKeyPress { keyPress in
                                        handleKeyPress(keyPress)
                                    }
                                
                                // Inline completion preview - fixed spacing
                                if !autocompleteEngine.inlineCompletion.isEmpty && autocompleteEngine.inlineCompletion.hasPrefix(commandInput) {
                                    HStack(spacing: 0) {
                                        Text(commandInput)
                                            .font(getFont(size: CGFloat(userSettings.themeConfiguration.fontSize)))
                                            .foregroundColor(.clear)
                                        Text(String(autocompleteEngine.inlineCompletion.dropFirst(commandInput.count)))
                                            .font(getFont(size: CGFloat(userSettings.themeConfiguration.fontSize)))
                                            .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.4))
                                        Spacer()
                                    }
                                    .allowsHitTesting(false)
                                }
                            }
                                .overlay(
                                    Group {
                                        if commandInput.isEmpty && autocompleteEngine.inlineCompletion.isEmpty {
                                            HStack {
                                                Text("Enter command...")
                                                    .font(getFont(size: CGFloat(userSettings.themeConfiguration.fontSize)))
                                                    .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.6))
                                                    .padding(.leading, 12)
                                                Spacer()
                                            }
                                        }
                                    }
                                )
                        }
                        
                        Button(action: submitCommand) {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundColor(userSettings.themeConfiguration.accentColor.color)
                                .font(.system(size: 20))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(commandInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                (userSettings.themeConfiguration.isDarkMode ? SwiftUI.Color.white : SwiftUI.Color.black).opacity(0.05)
                            )
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
        if isActivePane {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isInputFocused = true
            }
        }
    }
    
    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        // Handle Tab for completion and directory browsing
        if keyPress.key == .tab {
            if !autocompleteEngine.inlineCompletion.isEmpty {
                commandInput = autocompleteEngine.inlineCompletion
                autocompleteEngine.clearSuggestions()
                return .handled
            } else if autocompleteEngine.isShowingSuggestions {
                let selectedIndex = autocompleteEngine.selectedSuggestionIndex
                if selectedIndex < autocompleteEngine.suggestions.count {
                    let suggestion = autocompleteEngine.suggestions[selectedIndex]
                    commandInput = autocompleteEngine.getCompletion(for: commandInput, suggestion: suggestion)
                    if suggestion.type == .command {
                        commandInput += " "
                    }
                    autocompleteEngine.clearSuggestions()
                }
                return .handled
            } else {
                // Smart Tab behavior: directory completion or force show suggestions
                let components = commandInput.split(separator: " ", omittingEmptySubsequences: false)
                let shouldShowDirectories = shouldUseDirectoryCompletion(components: components)
                
                if shouldShowDirectories {
                    // Force show path suggestions for directory browsing
                    autocompleteEngine.getSuggestions(for: commandInput, in: viewModel.workingDirectory, forceShow: true)
                } else {
                    // Force show command suggestions
                    autocompleteEngine.getSuggestions(for: commandInput, in: viewModel.workingDirectory, forceShow: true)
                }
                return .handled
            }
        }
        
        // Handle Right Arrow for instant inline completion
        if keyPress.key == .rightArrow && !autocompleteEngine.inlineCompletion.isEmpty {
            commandInput = autocompleteEngine.inlineCompletion
            autocompleteEngine.clearSuggestions()
            return .handled
        }
        
        if autocompleteEngine.isShowingSuggestions {
            switch keyPress.key {
            case .downArrow:
                hasUsedArrowKeys = true
                let newIndex = min(autocompleteEngine.selectedSuggestionIndex + 1, autocompleteEngine.suggestions.count - 1)
                autocompleteEngine.updateSelectedIndex(newIndex, currentInput: commandInput)
                return .handled
            case .upArrow:
                hasUsedArrowKeys = true
                let newIndex = max(autocompleteEngine.selectedSuggestionIndex - 1, 0)
                autocompleteEngine.updateSelectedIndex(newIndex, currentInput: commandInput)
                return .handled
            case .return:
                if hasUsedArrowKeys {
                    let selectedIndex = autocompleteEngine.selectedSuggestionIndex
                    if selectedIndex < autocompleteEngine.suggestions.count {
                        let suggestion = autocompleteEngine.suggestions[selectedIndex]
                        commandInput = autocompleteEngine.getCompletion(for: commandInput, suggestion: suggestion)
                        if suggestion.type == .command {
                            commandInput += " "
                        }
                        autocompleteEngine.clearSuggestions()
                        hasUsedArrowKeys = false
                        return .handled
                    }
                }
                return .ignored
            case .escape:
                autocompleteEngine.clearSuggestions()
                hasUsedArrowKeys = false
                return .handled
            default:
                break
            }
        } else {
            // No suggestion list: use history navigation on up/down
            switch keyPress.key {
            case .upArrow:
                if let prev = viewModel.historyPrevious(currentInput: commandInput) {
                    commandInput = prev
                }
                return .handled
            case .downArrow:
                if let next = viewModel.historyNext() {
                    commandInput = next
                }
                return .handled
            default:
                break
            }
        }
        return .ignored
    }
    
    private func shouldUseDirectoryCompletion(components: [Substring]) -> Bool {
        let firstWord = String(components.first ?? "").lowercased()
        
        // Commands that commonly work with directories/files
        let pathCommands = ["cd", "ls", "cat", "less", "more", "rm", "cp", "mv", "mkdir", "rmdir", "touch", "open", "vim", "nano", "emacs", "code", "grep", "find"]
        
        // For path commands, always prefer directory completion
        if pathCommands.contains(firstWord) {
            return true
        }
        
        // For other commands, only use directory completion if we have multiple components
        return components.count > 1
    }
    
    private func getFont(size: CGFloat) -> Font {
        let family = userSettings.themeConfiguration.fontFamily
        // Try a medium weight face first if available
        if FontLoader.shared.isFontAvailable("\(family)-Medium") {
            return .custom("\(family)-Medium", size: size)
        }
        if FontLoader.shared.isFontAvailable(family) {
            return .custom(family, size: size)
        }
        return .system(size: size, design: .monospaced)
    }
}



// Separate view for terminal blocks for better organization
struct TerminalBlockView: View {
    let block: TerminalBlock
    @EnvironmentObject private var userSettings: UserSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Command input
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .foregroundColor(userSettings.themeConfiguration.accentColor.color)
                    .font(.system(size: 12, weight: .semibold))
                
                Text(block.input)
                    .font(getFont(size: CGFloat(userSettings.themeConfiguration.fontSize)))
                    .foregroundColor(userSettings.themeConfiguration.textColor.color)
                    .textSelection(.enabled)
                
                Spacer()
                
                // Working directory indicator
                if let workingDir = block.workingDirectory {
                    let displayPath = workingDir.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path) ? 
                        "~\(String(workingDir.dropFirst(FileManager.default.homeDirectoryForCurrentUser.path.count)))" : workingDir
                    Text(displayPath)
                        .font(getFont(size: max(11, CGFloat(userSettings.themeConfiguration.fontSize - 2))))
                        .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.7))
                        .lineLimit(1)
                }
            }
            
            // Command output
            if !block.output.isEmpty {
                Text(block.output)
                    .font(getFont(size: CGFloat(userSettings.themeConfiguration.fontSize)))
                    .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.88))
                    .textSelection(.enabled)
                    .padding(.leading, 20)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    userSettings.themeConfiguration.isDarkMode ?
                        SwiftUI.Color.white.opacity(0.05) :
                        SwiftUI.Color.black.opacity(0.04)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            userSettings.themeConfiguration.isDarkMode ?
                                SwiftUI.Color.white.opacity(0.10) :
                                SwiftUI.Color.black.opacity(0.08),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: SwiftUI.Color.black.opacity(userSettings.themeConfiguration.isDarkMode ? 0.2 : 0.08), radius: 4, x: 0, y: 2)
    }
    
    private func getFont(size: CGFloat) -> Font {
        let family = userSettings.themeConfiguration.fontFamily
        if FontLoader.shared.isFontAvailable("\(family)-Medium") {
            return .custom("\(family)-Medium", size: size)
        }
        if FontLoader.shared.isFontAvailable(family) {
            return .custom(family, size: size)
        }
        return .system(size: size, design: .monospaced)
    }
}
