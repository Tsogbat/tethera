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
                // Header with working directory - Liquid Glass Style
                HStack {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(userSettings.themeConfiguration.accentColor.color)
                            .font(.system(size: 14, weight: .medium))
                        Text(viewModel.displayWorkingDirectory)
                            .font(getFont(size: CGFloat(userSettings.themeConfiguration.fontSize)))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.ultraThinMaterial)
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.15), .white.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                    )
                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                    
                    // Git branch badge (inline, fast)
                    if let gitInfo = viewModel.gitInfo {
                        HStack(spacing: 6) {
                            Image(systemName: gitInfo.branchIcon)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(gitInfo.isMainBranch ? .green : .purple)
                            
                            Text(gitInfo.displayBranch)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.primary)
                            
                            if !gitInfo.statusIndicator.isEmpty {
                                Text(gitInfo.statusIndicator)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.orange)
                            }
                            
                            if let ab = gitInfo.aheadBehindText {
                                Text(ab)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.ultraThinMaterial)
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(
                                        gitInfo.isMainBranch ? SwiftUI.Color.green.opacity(0.4) : SwiftUI.Color.purple.opacity(0.4),
                                        lineWidth: 1
                                    )
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.9)).animation(.spring(response: 0.3)),
                            removal: .opacity.animation(.easeOut(duration: 0.15))
                        ))
                    }
                    
                    Spacer()
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.gitInfo != nil)
                .padding(.top, 16)
                .padding(.horizontal, 20)

                // Terminal blocks with proper safe area handling
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.blocks) { block in
                                TerminalBlockView(
                                    block: block,
                                    onRerun: { command in
                                        viewModel.rerunBlock(id: block.id, command: command)
                                    },
                                    onEdit: { command in
                                        // Legacy support or copy to clipboard? 
                                        // Internal edit mode handles inline editing now.
                                        commandInput = command
                                        isInputFocused = true
                                    }
                                )
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
                    // Liquid Glass Input Area
                    HStack(spacing: 14) {
                        HStack(spacing: 12) {
                            // Chevron with glow effect
                            Image(systemName: "chevron.right")
                                .foregroundStyle(userSettings.themeConfiguration.accentColor.color)
                                .font(.system(size: 14, weight: .semibold))
                                .shadow(color: userSettings.themeConfiguration.accentColor.color.opacity(0.4), radius: 4)
                            
                            ZStack(alignment: .leading) {
                                TextField("", text: $commandInput)
                                    .font(getFont(size: CGFloat(userSettings.themeConfiguration.fontSize)))
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .foregroundStyle(.primary)
                                    .tint(userSettings.themeConfiguration.accentColor.color)
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
                                        hasUsedArrowKeys = false
                                        if isInputFocused {
                                            // Update inline ghost completion (context-aware)
                                            autocompleteEngine.updateInlineCompletion(
                                                for: newValue,
                                                history: CommandHistoryManager.shared.allEntries.map { $0.command },
                                                workingDirectory: viewModel.workingDirectory
                                            )
                                            // Hide dropdown when typing (user can press Tab to reopen)
                                            if autocompleteEngine.isDropdownVisible {
                                                autocompleteEngine.hideDropdown()
                                            }
                                        }
                                    }
                                    .onSubmit { 
                                        autocompleteEngine.hideDropdown()
                                        submitCommand() 
                                    }
                                    .onKeyPress { keyPress in
                                        handleKeyPress(keyPress)
                                    }
                                
                                // Inline completion preview
                                if !autocompleteEngine.inlineCompletion.isEmpty && autocompleteEngine.inlineCompletion.hasPrefix(commandInput) {
                                    HStack(spacing: 0) {
                                        Text(commandInput)
                                            .font(getFont(size: CGFloat(userSettings.themeConfiguration.fontSize)))
                                            .foregroundColor(.clear)
                                        Text(String(autocompleteEngine.inlineCompletion.dropFirst(commandInput.count)))
                                            .font(getFont(size: CGFloat(userSettings.themeConfiguration.fontSize)))
                                            .foregroundStyle(.secondary.opacity(0.5))
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
                                                .foregroundStyle(.secondary.opacity(0.5))
                                            Spacer()
                                        }
                                    }
                                }
                            )
                        }
                        
                        // Submit button with glass effect
                        Button(action: submitCommand) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(userSettings.themeConfiguration.accentColor.color)
                                .shadow(color: userSettings.themeConfiguration.accentColor.color.opacity(0.3), radius: 6)
                        }
                        .buttonStyle(.plain)
                        .disabled(commandInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(commandInput.isEmpty ? 0.5 : 1)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.ultraThinMaterial)
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.2), .white.opacity(0.05)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1
                                )
                        }
                    )
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -4)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    // Floating dropdown - positioned directly above input
                    .overlay(alignment: .bottomLeading) {
                        if autocompleteEngine.isDropdownVisible && !autocompleteEngine.dropdownSuggestions.isEmpty {
                            AutocompleteSuggestionView(
                                suggestions: autocompleteEngine.dropdownSuggestions,
                                onSuggestionSelected: { suggestion in
                                    commandInput = autocompleteEngine.applySuggestion(suggestion, to: commandInput)
                                    if suggestion.type == .directory {
                                        autocompleteEngine.showDropdownSuggestions(for: commandInput, workingDirectory: viewModel.workingDirectory)
                                    } else {
                                        autocompleteEngine.hideDropdown()
                                        if suggestion.type == .command {
                                            commandInput += " "
                                        }
                                    }
                                },
                                onArrowNavigation: { _ in },
                                selectedIndex: $autocompleteEngine.selectedIndex
                            )
                            .frame(maxWidth: 380)
                            .offset(x: 36, y: -60) // Position right above input bar
                        }
                    }
                    .zIndex(100)
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
        // Tab: Toggle dropdown or accept inline completion
        if keyPress.key == .tab {
            if autocompleteEngine.isDropdownVisible {
                // Select current item in dropdown
                if let suggestion = autocompleteEngine.getSelectedSuggestion() {
                    commandInput = autocompleteEngine.applySuggestion(suggestion, to: commandInput)
                    if suggestion.type == .directory {
                        // Refresh dropdown for directory traversal
                        autocompleteEngine.showDropdownSuggestions(for: commandInput, workingDirectory: viewModel.workingDirectory)
                    } else {
                        autocompleteEngine.hideDropdown()
                        if suggestion.type == .command {
                            commandInput += " "
                        }
                    }
                }
            } else {
                // Show dropdown suggestions
                autocompleteEngine.showDropdownSuggestions(for: commandInput, workingDirectory: viewModel.workingDirectory)
            }
            return .handled
        }
        
        // Right Arrow: Accept inline ghost completion
        if keyPress.key == .rightArrow && !autocompleteEngine.inlineCompletion.isEmpty {
            commandInput = autocompleteEngine.inlineCompletion
            autocompleteEngine.clear()
            return .handled
        }
        
        // Escape: Close dropdown
        if keyPress.key == .escape && autocompleteEngine.isDropdownVisible {
            autocompleteEngine.hideDropdown()
            return .handled
        }
        
        // Arrow keys: Navigate dropdown or history
        if autocompleteEngine.isDropdownVisible {
            switch keyPress.key {
            case .downArrow:
                autocompleteEngine.navigateDown()
                return .handled
            case .upArrow:
                autocompleteEngine.navigateUp()
                return .handled
            case .return:
                // Select item from dropdown
                if let suggestion = autocompleteEngine.getSelectedSuggestion() {
                    commandInput = autocompleteEngine.applySuggestion(suggestion, to: commandInput)
                    if suggestion.type == .command {
                        commandInput += " "
                    }
                    autocompleteEngine.hideDropdown()
                    return .handled
                }
                return .ignored
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
    let onRerun: ((String) -> Void)?
    let onEdit: ((String) -> Void)?
    @EnvironmentObject private var userSettings: UserSettings
    @State private var isExpanded: Bool = true
    @State private var isHovered: Bool = false
    @State private var showCopied: Bool = false
    @State private var showRawOutput: Bool = false
    
    // Inline editing state
    @State private var isEditing: Bool = false
    @State private var editedCommand: String = ""
    @FocusState private var isEditFieldFocused: Bool
    
    init(block: TerminalBlock, onRerun: ((String) -> Void)? = nil, onEdit: ((String) -> Void)? = nil) {
        self.block = block
        self.onRerun = onRerun
        self.onEdit = onEdit
    }
    
    // Shortened directory path like ~/projects
    private var displayDirectory: String {
        guard let dir = block.workingDirectory else { return "~" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if dir.hasPrefix(home) {
            let relative = String(dir.dropFirst(home.count))
            return relative.isEmpty ? "~" : "~\(relative)"
        }
        return dir
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Warp-style header: directory and duration
            HStack(spacing: 8) {
                // Directory path
                Text(displayDirectory)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.5))
                
                // Execution duration
                if let duration = block.formattedDuration {
                    Text("(\(duration))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.4))
                }
                
                Spacer()
            }
            
                // Command input with status indicator
                HStack(spacing: 8) {
                    // Status indicator (Stage 2: Exit code visualization)
                    Image(systemName: block.statusIcon)
                        .foregroundColor(block.statusColor)
                        .font(.system(size: 12, weight: .semibold))
                    
                    if isEditing {
                        // Inline Editing Mode
                        TextField("Command", text: $editedCommand)
                            .font(getFont(size: CGFloat(userSettings.themeConfiguration.fontSize)))
                            .textFieldStyle(PlainTextFieldStyle())
                            .foregroundColor(userSettings.themeConfiguration.accentColor.color)
                            .focused($isEditFieldFocused)
                            .onSubmit {
                                isEditing = false
                                onRerun?(editedCommand)
                                // Restore focus to main input after running
                                NotificationCenter.default.post(name: .restoreTerminalFocus, object: nil)
                            }
                            
                        // Edit actions
                        HStack(spacing: 4) {
                            BlockActionButton(icon: "play.fill", tooltip: "Run") {
                                isEditing = false
                                onRerun?(editedCommand)
                                // Restore focus to main input after running
                                NotificationCenter.default.post(name: .restoreTerminalFocus, object: nil)
                            }
                            .foregroundColor(.green)
                            
                            BlockActionButton(icon: "xmark", tooltip: "Cancel") {
                                isEditing = false
                                editedCommand = block.input
                                // Restore focus to main input on cancel too
                                NotificationCenter.default.post(name: .restoreTerminalFocus, object: nil)
                            }
                            .foregroundColor(.red)
                        }
                    } else {
                        // Read-only Mode
                        Text(block.input)
                            .font(getFont(size: CGFloat(userSettings.themeConfiguration.fontSize)))
                            .foregroundColor(userSettings.themeConfiguration.accentColor.color)
                            .textSelection(.enabled)
                    }
                    
                    Spacer()
                    
                    // Action bar (visible on hover)
                    if isHovered && !isEditing {
                        HStack(spacing: 4) {
                            BlockActionButton(icon: "arrow.clockwise", tooltip: "Rerun") {
                                onRerun?(block.input)
                            }
                            
                            BlockActionButton(icon: "pencil", tooltip: "Edit") {
                                isEditing = true
                                editedCommand = block.input
                                isEditFieldFocused = true
                            }
                            
                            BlockActionButton(icon: "doc.on.doc", tooltip: "Copy Command") {
                                copyToClipboard(block.input)
                            }
                            
                            BlockActionButton(icon: "doc.on.doc.fill", tooltip: "Copy All") {
                                copyToClipboard("\(block.input)\n\(block.output)")
                            }
                            
                            // Markdown toggle for markdown content
                            if block.isMarkdownContent {
                                BlockActionButton(
                                    icon: showRawOutput ? "doc.richtext" : "doc.plaintext",
                                    tooltip: showRawOutput ? "Render Markdown" : "Show Raw"
                                ) {
                                    showRawOutput.toggle()
                                }
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                
                // Metadata badges (Stage 2: Enhanced block info)
                HStack(spacing: 8) {
                    // Duration badge
                    if let duration = block.formattedDuration {
                        Text(duration)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.5))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(userSettings.themeConfiguration.textColor.color.opacity(0.08))
                            )
                    }
                    
                    // Category badge
                    CategoryBadge(category: block.category)
                        .environmentObject(userSettings)
                    
                    // Collapse/Expand button for long output
                    if block.output.count > 200 {
                        Button(action: { isExpanded.toggle() }) {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.5))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
            // Command output (collapsible)
            if !block.output.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if isExpanded {
                        // Markdown toggle for markdown content
                        if block.isMarkdownContent && !showRawOutput {
                            MarkdownOutputView(content: block.output)
                                .environmentObject(userSettings)
                        } else {
                            Text(formatOutputForDisplay(block.output))
                                .font(.system(size: CGFloat(userSettings.themeConfiguration.fontSize), weight: .regular, design: .monospaced))
                                .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.88))
                                .textSelection(.enabled)
                        }
                    } else {
                        // Show summary when collapsed
                        HStack {
                            Text(block.autoSummary)
                                .font(getFont(size: CGFloat(userSettings.themeConfiguration.fontSize - 1)))
                                .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.6))
                                .italic()
                            
                            Spacer()
                            
                            Text("Click to expand")
                                .font(.system(size: 10))
                                .foregroundColor(userSettings.themeConfiguration.accentColor.color.opacity(0.7))
                        }
                        .onTapGesture { isExpanded = true }
                    }
                }
                .padding(.leading, 20)
            }
            
            // Media preview section (for preview/show commands)
            if block.hasMedia, let mediaFiles = block.mediaFiles {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(mediaFiles, id: \.self) { path in
                        MediaPreviewView(filePath: path)
                    }
                }
                .padding(.top, 8)
                .padding(.leading, 20)
            }
            
            // Copied indicator
            if showCopied {
                Text("Copied!")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.green)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .background(
            ZStack {
                // Liquid glass background
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                
                // Gradient border with status color accent
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                block.statusColor.opacity(isHovered ? 0.6 : 0.4),
                                .white.opacity(0.1),
                                block.statusColor.opacity(isHovered ? 0.4 : 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isHovered ? 1.5 : 1
                    )
            }
        )
        .shadow(color: block.statusColor.opacity(isHovered ? 0.25 : 0.15), radius: isHovered ? 12 : 8, x: 0, y: 4)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isExpanded)
    }
    
    /// Format output for display with proper column alignment like Warp
    private func formatOutputForDisplay(_ output: String) -> String {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        
        // Check if this looks like columnar output (multiple items on lines separated by tabs/spaces)
        if looksLikeColumnarOutput(output) {
            return formatColumnarOutput(output)
        }
        
        // Otherwise just expand tabs normally
        return expandTabs(output, tabWidth: 8)
    }
    
    /// Detect if output looks like ls-style columnar data (tab-separated short filenames)
    /// Very conservative - only true for tab-separated short items, never for prose
    private func looksLikeColumnarOutput(_ output: String) -> Bool {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > 0 && lines.count <= 10 else { return false }
        
        var tabLineCount = 0
        for line in lines {
            // Must have tabs - space-separated text is likely prose
            guard line.contains("\t") else { continue }
            
            // Split by tabs and check if items look like filenames (short, no sentences)
            let items = line.split(separator: "\t")
            
            // Each item should be short (filename-like, not prose)
            let allShort = items.allSatisfy { item in
                let trimmed = item.trimmingCharacters(in: .whitespaces)
                return trimmed.count <= 30 && !trimmed.contains(": ")
            }
            
            if allShort && items.count >= 2 {
                tabLineCount += 1
            }
        }
        
        // Only format as columns if most lines are tab-separated short items
        return tabLineCount > 0 && tabLineCount >= lines.count / 2
    }
    
    /// Format columnar output with even column widths
    private func formatColumnarOutput(_ output: String) -> String {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var formattedLines: [String] = []
        
        for line in lines {
            if line.isEmpty {
                formattedLines.append("")
                continue
            }
            
            // Split by tabs or multiple spaces
            let items = line.split(whereSeparator: { $0 == "\t" || $0.isWhitespace })
                .map(String.init)
                .filter { !$0.isEmpty }
            
            if items.count <= 1 {
                formattedLines.append(line)
                continue
            }
            
            // Find the appropriate column width (longest item + padding)
            let maxItemLen = items.map { $0.count }.max() ?? 0
            let columnWidth = ((maxItemLen / 8) + 1) * 8 // Round up to next 8-char boundary
            let minColumnWidth = max(16, columnWidth) // At least 16 chars
            
            // Format items into evenly-spaced columns
            var formattedLine = ""
            for (index, item) in items.enumerated() {
                if index > 0 {
                    // Pad to column width
                    let currentLen = formattedLine.count % minColumnWidth
                    let padding = minColumnWidth - currentLen
                    formattedLine += String(repeating: " ", count: max(2, padding))
                }
                formattedLine += item
            }
            formattedLines.append(formattedLine)
        }
        
        return formattedLines.joined(separator: "\n")
    }
    
    /// Simple tab expansion
    private func expandTabs(_ text: String, tabWidth: Int) -> String {
        var result = ""
        var column = 0
        
        for char in text {
            if char == "\t" {
                let spacesToAdd = tabWidth - (column % tabWidth)
                result += String(repeating: " ", count: spacesToAdd)
                column += spacesToAdd
            } else if char == "\n" {
                result.append(char)
                column = 0
            } else {
                result.append(char)
                column += 1
            }
        }
        return result
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        
        withAnimation {
            showCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopied = false
            }
        }
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

// MARK: - Block Action Button
struct BlockActionButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void
    @EnvironmentObject private var userSettings: UserSettings
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isHovered 
                    ? userSettings.themeConfiguration.accentColor.color
                    : userSettings.themeConfiguration.textColor.color.opacity(0.6))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered 
                            ? userSettings.themeConfiguration.accentColor.color.opacity(0.15)
                            : SwiftUI.Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Category Badge (Stage 2: Command categorization UI)
struct CategoryBadge: View {
    let category: CommandCategory
    @EnvironmentObject private var userSettings: UserSettings
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: categoryIcon)
                .font(.system(size: 8))
            Text(category.rawValue)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundColor(categoryColor.opacity(0.8))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 6)
                    .fill(categoryColor.opacity(0.1))
            }
        )
    }
    
    private var categoryIcon: String {
        switch category {
        case .fileOperation: return "doc"
        case .navigation: return "folder"
        case .gitOperation: return "arrow.triangle.branch"
        case .packageManager: return "shippingbox"
        case .process: return "gear"
        case .networkOperation: return "network"
        case .development: return "hammer"
        case .shell: return "terminal"
        case .unknown: return "questionmark"
        }
    }
    
    private var categoryColor: SwiftUI.Color {
        switch category {
        case .fileOperation: return .blue
        case .navigation: return .orange
        case .gitOperation: return .purple
        case .packageManager: return .green
        case .process: return .red
        case .networkOperation: return .cyan
        case .development: return .yellow
        case .shell: return .gray
        case .unknown: return .gray
        }
    }
}

// MARK: - Media Preview View

struct MediaPreviewView: View {
    let filePath: String
    @State private var image: NSImage?
    @State private var isHovered: Bool = false
    @State private var loadError: Bool = false
    
    private var fileName: String {
        (filePath as NSString).lastPathComponent
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let img = image {
                // Image display
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 500, maxHeight: 350)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.white.opacity(isHovered ? 0.3 : 0.1), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    .scaleEffect(isHovered ? 1.02 : 1.0)
                    .animation(.spring(response: 0.3), value: isHovered)
                    .onHover { hovering in
                        isHovered = hovering
                    }
                    .onTapGesture {
                        openInQuickLook()
                    }
                    .help("Click to open in Quick Look")
                
                // Filename label
                Text(fileName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            } else if loadError {
                // Error state
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Failed to load: \(fileName)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                )
            } else {
                // Loading placeholder
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading \(fileName)...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(12)
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        let url = URL(fileURLWithPath: filePath)
        if let nsImage = NSImage(contentsOf: url) {
            self.image = nsImage
        } else {
            self.loadError = true
        }
    }
    
    private func openInQuickLook() {
        let url = URL(fileURLWithPath: filePath)
        NSWorkspace.shared.open(url)
    }
}
