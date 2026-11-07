import SwiftUI

/// Renders Markdown from `cat file.md` blocks and AI answers.
struct MarkdownOutputView: View {
    @EnvironmentObject private var settings: UserSettings
    let content: String
    /// When set, shell code blocks get an "Insert" button that puts the command in the prompt.
    var onInsertCode: ((String) -> Void)? = nil

    var body: some View {
        let elements = MarkdownParser.parse(content)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                render(element)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var theme: DesignTheme { settings.theme }
    private var bodySize: CGFloat { max(12, CGFloat(settings.themeConfiguration.fontSize)) }

    @ViewBuilder
    private func render(_ element: MarkdownElement) -> some View {
        switch element {
        case .heading(let level, let text):
            Text(inline(text))
                .font(.system(size: bodySize + CGFloat(max(0, 4 - level)) * 2.5, weight: level <= 2 ? .bold : .semibold))
                .foregroundStyle(theme.textPrimary)
                .padding(.top, level <= 2 ? 6 : 3)
        case .paragraph(let text):
            Text(inline(text))
                .font(.system(size: bodySize))
                .foregroundStyle(theme.textPrimary.opacity(0.88))
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let indent, let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let marker {
                    Text(marker)
                        .font(.system(size: bodySize - 1, weight: .semibold).monospacedDigit())
                        .foregroundStyle(theme.textTertiary)
                } else {
                    Circle().fill(theme.accent.opacity(0.8)).frame(width: 4.5, height: 4.5)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                }
                Text(inline(text))
                    .font(.system(size: bodySize))
                    .foregroundStyle(theme.textPrimary.opacity(0.88))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 14)
        case .quote(let text):
            HStack(spacing: 10) {
                Capsule().fill(theme.border).frame(width: 2.5)
                Text(inline(text))
                    .font(.system(size: bodySize).italic())
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .code(let language, let code):
            CodeBlockView(language: language, code: code, onInsert: insertHandler(for: language))
        case .table(let rows):
            MarkdownTable(rows: rows)
        case .rule:
            Rectangle().fill(theme.hairline).frame(height: 1).padding(.vertical, 4)
        }
    }

    private func insertHandler(for language: String) -> ((String) -> Void)? {
        guard let onInsertCode, CommandSanitizer.shellLanguages.contains(language) else { return nil }
        return onInsertCode
    }

    private func inline(_ text: String) -> AttributedString {
        var attributed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
            attributed[run.range].font = Typography.mono(settings.themeConfiguration.fontFamily, size: bodySize - 1, weight: .medium)
            attributed[run.range].foregroundColor = theme.accent
            attributed[run.range].backgroundColor = theme.accentSoft.opacity(0.6)
        }
        for run in attributed.runs where run.link != nil {
            attributed[run.range].foregroundColor = theme.accent
            attributed[run.range].underlineStyle = .single
        }
        return attributed
    }
}

struct CodeBlockView: View {
    @EnvironmentObject private var settings: UserSettings
    let language: String
    let code: String
    var onInsert: ((String) -> Void)?
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(language.isEmpty ? "code" : language)
                    .font(Typography.mono(settings.themeConfiguration.fontFamily, size: 10, weight: .semibold))
                    .foregroundStyle(settings.theme.textTertiary)
                Spacer()
                IconButton(systemName: copied ? "checkmark" : "doc.on.doc", help: "Copy", tint: copied ? settings.theme.success : nil, size: 22) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    withAnimation(Motion.bouncy) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation(Motion.quick) { copied = false } }
                }
                if let onInsert {
                    PillButton(title: "Insert", systemImage: "arrow.down.to.line", prominent: true) { onInsert(code) }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(settings.theme.surfaceRaised.opacity(0.7))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(Typography.mono(settings.themeConfiguration.fontFamily, size: CGFloat(settings.themeConfiguration.fontSize) - 0.5))
                    .foregroundStyle(settings.theme.textPrimary)
                    .textSelection(.enabled)
                    .padding(11)
                    .fixedSize(horizontal: true, vertical: true)
            }
        }
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(settings.theme.background.opacity(settings.theme.isDark ? 0.55 : 0.75)))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(settings.theme.hairline, lineWidth: 0.75))
        .padding(.vertical, 3)
    }
}

struct MarkdownTable: View {
    @EnvironmentObject private var settings: UserSettings
    let rows: [[String]]

    var body: some View {
        let columns = rows.map(\.count).max() ?? 0
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        Text((try? AttributedString(markdown: column < row.count ? row[column] : "")) ?? AttributedString())
                            .font(.system(size: CGFloat(settings.themeConfiguration.fontSize) - 0.5, weight: index == 0 ? .semibold : .regular))
                            .foregroundStyle(index == 0 ? settings.theme.textPrimary : settings.theme.textPrimary.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(index == 0 ? settings.theme.surfaceRaised : (index.isMultiple(of: 2) ? settings.theme.surface.opacity(0.6) : .clear))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(settings.theme.hairline, lineWidth: 0.75))
    }
}

// MARK: - Parsing

enum MarkdownElement: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(indent: Int, marker: String?, text: String)
    case quote(String)
    case code(language: String, code: String)
    case table([[String]])
    case rule
}

enum MarkdownParser {
    static func parse(_ content: String) -> [MarkdownElement] {
        var elements: [MarkdownElement] = []
        var paragraph: [String] = []
        var table: [[String]] = []
        var codeLines: [String] = []
        var codeLanguage = ""
        var inCode = false

        func flushParagraph() {
            if !paragraph.isEmpty {
                elements.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph.removeAll()
            }
        }
        func flushTable() {
            if !table.isEmpty {
                elements.append(.table(table))
                table.removeAll()
            }
        }

        for rawLine in content.components(separatedBy: "\n") {
            let line = rawLine.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCode {
                    elements.append(.code(language: codeLanguage, code: codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    inCode = false
                } else {
                    flushParagraph(); flushTable()
                    codeLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces).lowercased()
                    inCode = true
                }
                continue
            }
            if inCode {
                codeLines.append(line)
                continue
            }
            if trimmed.isEmpty {
                flushParagraph(); flushTable()
                continue
            }
            if trimmed.hasPrefix("|") {
                flushParagraph()
                let isSeparator = trimmed.allSatisfy { "|-: ".contains($0) }
                if !isSeparator {
                    var cells = trimmed.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                    if cells.first == "" { cells.removeFirst() }
                    if cells.last == "" { cells.removeLast() }
                    table.append(cells)
                }
                continue
            }
            flushTable()
            if let heading = headingLevel(trimmed) {
                flushParagraph()
                elements.append(.heading(level: heading.level, text: heading.text))
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                elements.append(.rule)
            } else if trimmed.hasPrefix("> ") {
                flushParagraph()
                elements.append(.quote(String(trimmed.dropFirst(2))))
            } else if let bullet = bulletItem(line) {
                flushParagraph()
                elements.append(bullet)
            } else {
                paragraph.append(trimmed)
            }
        }
        if inCode {
            elements.append(.code(language: codeLanguage, code: codeLines.joined(separator: "\n")))
        }
        flushParagraph()
        flushTable()
        return elements
    }

    private static func headingLevel(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        for character in line {
            if character == "#" { level += 1 } else { break }
        }
        guard (1...6).contains(level), line.count > level, line[line.index(line.startIndex, offsetBy: level)] == " " else { return nil }
        return (level, String(line.dropFirst(level + 1)))
    }

    private static func bulletItem(_ line: String) -> MarkdownElement? {
        let indentWidth = line.prefix(while: { $0 == " " }).count
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let indent = indentWidth / 2
        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            var text = String(trimmed.dropFirst(2))
            if text.hasPrefix("[ ] ") { text = "☐ " + text.dropFirst(4) }
            if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") { text = "☑ " + text.dropFirst(4) }
            return .bullet(indent: indent, marker: nil, text: text)
        }
        let digits = trimmed.prefix(while: { $0.isNumber })
        if !digits.isEmpty, digits.count <= 3 {
            let rest = trimmed.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
                return .bullet(indent: indent, marker: "\(digits).", text: String(rest.dropFirst(2)))
            }
        }
        return nil
    }
}
