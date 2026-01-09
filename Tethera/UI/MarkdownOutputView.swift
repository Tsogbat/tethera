import SwiftUI

/// A view that renders markdown content with proper formatting
struct MarkdownOutputView: View {
    let content: String
    @EnvironmentObject private var userSettings: UserSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parseMarkdownLines().enumerated()), id: \.offset) { _, element in
                renderElement(element)
            }
        }
    }
    
    private func parseMarkdownLines() -> [MarkdownElement] {
        var elements: [MarkdownElement] = []
        let lines = content.components(separatedBy: .newlines)
        var inCodeBlock = false
        var codeBlockContent: [String] = []
        var codeLanguage = ""
        
        // print("[MD] Parsing \(lines.count) lines")
        
        for (idx, rawLine) in lines.enumerated() {
            // Clean the line - remove all control characters
            let line = rawLine.filter { !$0.isASCII || $0.asciiValue! >= 32 || $0 == "\t" }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // if idx < 10 {
            //     print("[MD] Line \(idx): '\(trimmed.prefix(40))...' starts with: \(trimmed.prefix(4).map { "\\u{\(String(format: "%04X", $0.asciiValue ?? 0))}" })")
            // }
            
            // Check for code block delimiters
            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    elements.append(.codeBlock(codeBlockContent.joined(separator: "\n"), language: codeLanguage))
                    codeBlockContent = []
                    codeLanguage = ""
                    inCodeBlock = false
                } else {
                    codeLanguage = String(trimmed.dropFirst(3))
                    inCodeBlock = true
                }
            } else if inCodeBlock {
                codeBlockContent.append(line)
            } else if isHeader1(trimmed) {
                elements.append(.header1(String(trimmed.dropFirst(2))))
            } else if isHeader2(trimmed) {
                elements.append(.header2(String(trimmed.dropFirst(3))))
            } else if isHeader3(trimmed) {
                elements.append(.header3(String(trimmed.dropFirst(4))))
            } else if isListItem(trimmed) {
                elements.append(.listItem(String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("|") && trimmed.contains("|") {
                elements.append(.tableRow(trimmed))
            } else if trimmed.isEmpty {
                elements.append(.blank)
            } else {
                elements.append(.paragraph(line))
            }
        }
        
        if inCodeBlock && !codeBlockContent.isEmpty {
            elements.append(.codeBlock(codeBlockContent.joined(separator: "\n"), language: codeLanguage))
        }
        
        // print("[MD] Parsed \(elements.count) elements")
        return elements
    }
    
    private func isHeader1(_ s: String) -> Bool {
        guard s.count >= 2 else { return false }
        let chars = Array(s)
        return chars[0] == "#" && chars[1] == " "
    }
    
    private func isHeader2(_ s: String) -> Bool {
        guard s.count >= 3 else { return false }
        let chars = Array(s)
        return chars[0] == "#" && chars[1] == "#" && chars[2] == " "
    }
    
    private func isHeader3(_ s: String) -> Bool {
        guard s.count >= 4 else { return false }
        let chars = Array(s)
        return chars[0] == "#" && chars[1] == "#" && chars[2] == "#" && chars[3] == " "
    }
    
    private func isListItem(_ s: String) -> Bool {
        guard s.count >= 2 else { return false }
        let chars = Array(s)
        return (chars[0] == "-" || chars[0] == "*") && chars[1] == " "
    }
    
    @ViewBuilder
    private func renderElement(_ element: MarkdownElement) -> some View {
        switch element {
        case .header1(let text):
            Text(renderInline(text))
                .font(.system(size: CGFloat(userSettings.themeConfiguration.fontSize + 6), weight: .bold))
                .foregroundColor(userSettings.themeConfiguration.accentColor.color)
                .padding(.top, 8)
                .padding(.bottom, 4)
            
        case .header2(let text):
            Text(renderInline(text))
                .font(.system(size: CGFloat(userSettings.themeConfiguration.fontSize + 3), weight: .semibold))
                .foregroundColor(userSettings.themeConfiguration.textColor.color)
                .padding(.top, 6)
                .padding(.bottom, 2)
            
        case .header3(let text):
            Text(renderInline(text))
                .font(.system(size: CGFloat(userSettings.themeConfiguration.fontSize + 1), weight: .medium))
                .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.9))
                .padding(.top, 4)
            
        case .codeBlock(let code, _):
            Text(code)
                .font(.system(size: CGFloat(userSettings.themeConfiguration.fontSize - 1), design: .monospaced))
                .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.9))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(SwiftUI.Color.black.opacity(0.3))
                )
                .textSelection(.enabled)
            
        case .listItem(let text):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .foregroundColor(userSettings.themeConfiguration.accentColor.color)
                Text(renderInline(text))
                    .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.88))
            }
            .font(.system(size: CGFloat(userSettings.themeConfiguration.fontSize)))
            
        case .tableRow(let text):
            let cells = parseTableCells(text)
            if cells.isEmpty || isSeparatorRow(text) {
                // Skip separator rows (|---|---|)
                EmptyView()
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                        Text(renderInline(cell.trimmingCharacters(in: .whitespaces)))
                            .font(.system(size: CGFloat(userSettings.themeConfiguration.fontSize), design: .monospaced))
                            .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.88))
                            .frame(minWidth: 80, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SwiftUI.Color.white.opacity(0.03))
                )
            }
            
        case .paragraph(let text):
            Text(renderInline(text))
                .font(.system(size: CGFloat(userSettings.themeConfiguration.fontSize)))
                .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.88))
                .textSelection(.enabled)
            
        case .blank:
            Spacer().frame(height: 4)
        }
    }
    
    /// Render inline markdown (bold, italic, code, links)
    private func renderInline(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attributed
        }
        return AttributedString(text)
    }
    
    /// Parse table row into cells
    private func parseTableCells(_ row: String) -> [String] {
        // Split by | and filter empty strings
        let cells = row.split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return cells
    }
    
    /// Check if row is a separator (|---|---|)
    private func isSeparatorRow(_ row: String) -> Bool {
        let trimmed = row.trimmingCharacters(in: .whitespaces)
        // Separator rows contain only |, -, :, and spaces
        let allowedChars = CharacterSet(charactersIn: "|-: ")
        return trimmed.unicodeScalars.allSatisfy { allowedChars.contains($0) } && trimmed.contains("-")
    }
}

enum MarkdownElement {
    case header1(String)
    case header2(String)
    case header3(String)
    case codeBlock(String, language: String)
    case listItem(String)
    case tableRow(String)
    case paragraph(String)
    case blank
}

/// Detects if content is likely markdown
struct MarkdownDetector {
    /// Check if the command output looks like markdown
    static func isMarkdownContent(_ content: String, command: String) -> Bool {
        // Check if command is reading a markdown file
        let mdFilePattern = command.contains(".md") || command.contains(".markdown")
        if mdFilePattern && (command.hasPrefix("cat ") || command.hasPrefix("less ") || command.hasPrefix("more ") || command.hasPrefix("bat ")) {
            return true
        }
        
        // Check for markdown patterns in content
        return hasMarkdownPatterns(content)
    }
    
    /// Check if content has markdown patterns
    static func hasMarkdownPatterns(_ content: String) -> Bool {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        var markdownScore = 0
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Headers
            if trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") || trimmed.hasPrefix("### ") {
                markdownScore += 3
            }
            
            // Bold/italic
            if trimmed.contains("**") || trimmed.contains("__") {
                markdownScore += 2
            }
            
            // Inline code
            if trimmed.contains("`") && !trimmed.hasPrefix("`") {
                markdownScore += 1
            }
            
            // Lists
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("1. ") {
                markdownScore += 1
            }
            
            // Links
            if trimmed.contains("](") && trimmed.contains("[") {
                markdownScore += 2
            }
            
            // Code blocks
            if trimmed.hasPrefix("```") {
                markdownScore += 3
            }
        }
        
        // Consider it markdown if score is high enough relative to content length
        let threshold = max(3, lines.count / 5)
        return markdownScore >= threshold
    }
}

#Preview {
    MarkdownOutputView(content: """
    # Hello World
    
    This is **bold** and *italic* text.
    
    - Item 1
    - Item 2
    
    `code snippet`
    """)
    .padding()
    .environmentObject(UserSettings())
}
