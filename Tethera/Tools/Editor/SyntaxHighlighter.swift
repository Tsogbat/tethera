import AppKit
import Foundation

/// A small, fast highlighter: a few regular expressions per language family, applied as
/// temporary attributes (they don't touch the text, undo or saving). Good enough to read code
/// at a glance; it isn't a parser.
struct SyntaxHighlighter {
    enum Token: CaseIterable {
        case comment, string, number, keyword, type, tag, attribute, heading, emphasis
    }

    struct Rule {
        let token: Token
        let regex: NSRegularExpression
        /// Which capture group to color (0 = the whole match).
        var group = 0
    }

    let rules: [Rule]

    /// Whole-document highlighting stops here; bigger files stay plain.
    static let sizeLimit = 250_000

    static func forFile(_ path: String) -> SyntaxHighlighter? {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()
        if ["makefile", "dockerfile", "gemfile", "rakefile", "brewfile", "podfile"].contains(name) { return script(keywords: shellKeywords) }
        if [".zshrc", ".bashrc", ".zprofile", ".bash_profile", ".profile", ".env"].contains(name) || name.hasPrefix(".env") {
            return script(keywords: shellKeywords)
        }
        switch ext {
        case "swift": return cLike(keywords: swiftKeywords)
        case "js", "jsx", "mjs", "cjs", "ts", "tsx", "mts": return cLike(keywords: jsKeywords, templates: true)
        case "go": return cLike(keywords: goKeywords, templates: true)
        case "rs": return cLike(keywords: rustKeywords)
        case "c", "h", "cc", "cpp", "hpp", "m", "mm", "java", "kt", "kts", "cs", "dart", "scala", "zig":
            return cLike(keywords: cKeywords)
        case "py", "pyi": return script(keywords: pythonKeywords, tripleQuotes: true)
        case "rb": return script(keywords: rubyKeywords)
        case "sh", "bash", "zsh", "fish": return script(keywords: shellKeywords)
        case "yml", "yaml", "toml", "ini", "conf", "cfg": return config()
        case "json", "jsonc", "json5": return json()
        case "md", "markdown", "mdx": return markdown()
        case "html", "htm", "xml", "svg", "plist", "vue", "svelte": return markup()
        case "css", "scss", "sass", "less": return css()
        case "sql": return cLike(keywords: sqlKeywords, lineComment: "--", caseInsensitive: true)
        default: return nil
        }
    }

    // MARK: Applying

    func highlight(_ layoutManager: NSLayoutManager, text: String, colors: [Token: NSColor]) {
        let full = NSRange(location: 0, length: (text as NSString).length)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
        guard full.length <= Self.sizeLimit else { return }
        // Later rules lose to earlier ones: comments and strings first, so keywords inside them stay quiet.
        var claimed = IndexSet()
        for rule in rules {
            guard let color = colors[rule.token] else { continue }
            rule.regex.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match else { return }
                let range = match.range(at: rule.group)
                guard range.location != NSNotFound, range.length > 0 else { return }
                let span = range.location..<(range.location + range.length)
                if claimed.intersects(integersIn: span) { return }
                if rule.token == .comment || rule.token == .string { claimed.insert(integersIn: span) }
                layoutManager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: range)
            }
        }
    }

    /// Colors from the terminal palette, muted for long reading; comments recede.
    static func colors(dark: Bool, palette: TerminalPalette, text: NSColor, dim: NSColor) -> [Token: NSColor] {
        func ansi(_ index: Int) -> NSColor { palette.ansi[index].nsColor }
        return [
            .comment: dim,
            .string: ansi(2),
            .number: ansi(6),
            .keyword: ansi(5),
            .type: ansi(4),
            .tag: ansi(4),
            .attribute: ansi(6),
            .heading: text,
            .emphasis: ansi(2),
        ]
    }

    // MARK: Families

    private static func re(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // Patterns are constants; a typo should fail loudly in development.
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static func words(_ list: [String]) -> String {
        "\\b(?:" + list.joined(separator: "|") + ")\\b"
    }

    private static let number = "\\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|\\d[\\d_]*(?:\\.\\d[\\d_]*)?(?:[eE][+-]?\\d+)?)\\b"

    private static func cLike(keywords: [String], templates: Bool = false, lineComment: String = "//", caseInsensitive: Bool = false) -> SyntaxHighlighter {
        var rules = [
            Rule(token: .comment, regex: re("/\\*[\\s\\S]*?\\*/")),
            Rule(token: .comment, regex: re(NSRegularExpression.escapedPattern(for: lineComment) + "[^\\n]*")),
            Rule(token: .string, regex: re("\"(?:[^\"\\\\\\n]|\\\\.)*\"")),
            Rule(token: .string, regex: re("'(?:[^'\\\\\\n]|\\\\.)*'")),
        ]
        if templates { rules.append(Rule(token: .string, regex: re("`(?:[^`\\\\]|\\\\.)*`"))) }
        rules += [
            Rule(token: .number, regex: re(number)),
            Rule(token: .keyword, regex: re(words(keywords), caseInsensitive ? [.caseInsensitive] : [])),
            Rule(token: .type, regex: re("\\b[A-Z][A-Za-z0-9_]*\\b")),
        ]
        return SyntaxHighlighter(rules: rules)
    }

    private static func script(keywords: [String], tripleQuotes: Bool = false) -> SyntaxHighlighter {
        var rules: [Rule] = []
        if tripleQuotes {
            rules.append(Rule(token: .string, regex: re("\"\"\"[\\s\\S]*?\"\"\"|'''[\\s\\S]*?'''")))
        }
        rules += [
            Rule(token: .comment, regex: re("(?:^|\\s)(#[^\\n]*)", [.anchorsMatchLines]), group: 1),
            Rule(token: .string, regex: re("\"(?:[^\"\\\\]|\\\\.)*\"")),
            Rule(token: .string, regex: re("'[^'\\n]*'")),
            Rule(token: .number, regex: re(number)),
            Rule(token: .keyword, regex: re(words(keywords))),
            Rule(token: .type, regex: re("\\$\\{?[A-Za-z_][A-Za-z0-9_]*\\}?")),
        ]
        return SyntaxHighlighter(rules: rules)
    }

    private static func config() -> SyntaxHighlighter {
        SyntaxHighlighter(rules: [
            Rule(token: .comment, regex: re("(?:^|\\s)([#;][^\\n]*)", [.anchorsMatchLines]), group: 1),
            Rule(token: .string, regex: re("\"(?:[^\"\\\\\\n]|\\\\.)*\"|'[^'\\n]*'")),
            Rule(token: .heading, regex: re("^\\s*\\[[^\\]\\n]+\\]", [.anchorsMatchLines])),
            Rule(token: .attribute, regex: re("^\\s*-?\\s*([A-Za-z0-9_.\\-\"']+)\\s*[:=]", [.anchorsMatchLines]), group: 1),
            Rule(token: .number, regex: re(number)),
            Rule(token: .keyword, regex: re(words(["true", "false", "null", "yes", "no", "on", "off"]))),
        ])
    }

    private static func json() -> SyntaxHighlighter {
        SyntaxHighlighter(rules: [
            Rule(token: .comment, regex: re("//[^\\n]*|/\\*[\\s\\S]*?\\*/")),
            Rule(token: .attribute, regex: re("(\"(?:[^\"\\\\\\n]|\\\\.)*\")\\s*:"), group: 1),
            Rule(token: .string, regex: re("\"(?:[^\"\\\\\\n]|\\\\.)*\"")),
            Rule(token: .number, regex: re("-?" + number)),
            Rule(token: .keyword, regex: re(words(["true", "false", "null"]))),
        ])
    }

    private static func markdown() -> SyntaxHighlighter {
        SyntaxHighlighter(rules: [
            Rule(token: .string, regex: re("```[\\s\\S]*?```")),
            Rule(token: .string, regex: re("`[^`\\n]+`")),
            Rule(token: .keyword, regex: re("^#{1,6} [^\\n]*", [.anchorsMatchLines])),
            Rule(token: .emphasis, regex: re("\\*\\*[^*\\n]+\\*\\*|__[^_\\n]+__")),
            Rule(token: .type, regex: re("\\[[^\\]\\n]+\\]\\([^)\\n]+\\)")),
            Rule(token: .comment, regex: re("^>[^\\n]*", [.anchorsMatchLines])),
            Rule(token: .number, regex: re("^\\s*(?:[-*+]|\\d+\\.)\\s", [.anchorsMatchLines])),
        ])
    }

    private static func markup() -> SyntaxHighlighter {
        SyntaxHighlighter(rules: [
            Rule(token: .comment, regex: re("<!--[\\s\\S]*?-->")),
            Rule(token: .string, regex: re("\"[^\"]*\"|'[^']*'")),
            Rule(token: .tag, regex: re("</?([A-Za-z][A-Za-z0-9:._-]*)"), group: 1),
            Rule(token: .attribute, regex: re("\\s([A-Za-z_:][A-Za-z0-9_:.-]*)="), group: 1),
        ])
    }

    private static func css() -> SyntaxHighlighter {
        SyntaxHighlighter(rules: [
            Rule(token: .comment, regex: re("/\\*[\\s\\S]*?\\*/|//[^\\n]*")),
            Rule(token: .string, regex: re("\"[^\"\\n]*\"|'[^'\\n]*'")),
            Rule(token: .attribute, regex: re("([a-zA-Z-]+)\\s*:(?!:)"), group: 1),
            Rule(token: .number, regex: re("-?\\d*\\.?\\d+(?:px|em|rem|%|vh|vw|s|ms|deg)?\\b")),
            Rule(token: .tag, regex: re("[.#][A-Za-z_-][A-Za-z0-9_-]*")),
            Rule(token: .keyword, regex: re("@[a-z-]+")),
        ])
    }

    // MARK: Keywords

    private static let swiftKeywords = ["actor", "as", "associatedtype", "async", "await", "break", "case", "catch", "class", "continue",
        "default", "defer", "deinit", "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate", "final", "for", "func",
        "guard", "if", "import", "in", "init", "inout", "internal", "is", "lazy", "let", "mutating", "nil", "nonisolated", "open",
        "operator", "override", "private", "protocol", "public", "repeat", "rethrows", "return", "self", "Self", "some", "any", "static",
        "struct", "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias", "var", "weak", "where", "while"]
    private static let jsKeywords = ["async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default",
        "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for", "from", "function", "if", "implements", "import",
        "in", "instanceof", "interface", "let", "new", "null", "of", "private", "protected", "public", "readonly", "return", "static",
        "super", "switch", "this", "throw", "true", "try", "type", "typeof", "undefined", "var", "void", "while", "yield", "as"]
    private static let goKeywords = ["break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "false",
        "for", "func", "go", "goto", "if", "import", "interface", "map", "nil", "package", "range", "return", "select", "struct",
        "switch", "true", "type", "var"]
    private static let rustKeywords = ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern",
        "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self",
        "static", "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while"]
    private static let cKeywords = ["auto", "break", "case", "catch", "class", "const", "continue", "default", "delete", "do", "else",
        "enum", "extends", "extern", "false", "final", "for", "fun", "goto", "if", "implements", "import", "inline", "interface", "new",
        "nil", "null", "nullptr", "override", "package", "private", "protected", "public", "return", "sizeof", "static", "struct",
        "super", "switch", "template", "this", "throw", "throws", "true", "try", "typedef", "union", "val", "var", "virtual", "void",
        "volatile", "when", "while", "@interface", "@implementation", "@end", "@property"]
    private static let pythonKeywords = ["and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif",
        "else", "except", "False", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "None", "nonlocal", "not",
        "or", "pass", "raise", "return", "self", "True", "try", "while", "with", "yield", "match", "case"]
    private static let rubyKeywords = ["alias", "and", "begin", "break", "case", "class", "def", "do", "else", "elsif", "end", "ensure",
        "false", "for", "if", "in", "module", "next", "nil", "not", "or", "redo", "rescue", "retry", "return", "self", "super", "then",
        "true", "undef", "unless", "until", "when", "while", "yield", "require"]
    private static let shellKeywords = ["if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac", "in",
        "function", "return", "local", "export", "source", "alias", "unset", "set", "shift", "exit", "eval", "exec", "readonly",
        "declare", "typeset", "echo", "cd", "test"]
    private static let sqlKeywords = ["select", "from", "where", "insert", "into", "values", "update", "set", "delete", "create", "table",
        "drop", "alter", "add", "index", "join", "left", "right", "inner", "outer", "on", "as", "and", "or", "not", "null", "is",
        "order", "by", "group", "having", "limit", "offset", "primary", "key", "foreign", "references", "default", "unique",
        "distinct", "union", "all", "case", "when", "then", "else", "end", "begin", "commit", "rollback", "with"]
}
