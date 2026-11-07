import AppKit
import SwiftUI

/// The editor: the terminal's font, line numbers, find bar, a quiet bar when the file
/// changes underneath you.
struct EditorPane: View {
    @ObservedObject var document: EditorDocument
    let paneID: UUID
    @ObservedObject private var preferences = PreferencesStore.shared
    @Environment(\.theme) private var theme
    @State private var showingDiff = false

    var body: some View {
        VStack(spacing: 0) {
            if let conflict = document.conflict {
                notice(conflict == .deleted ? "Deleted on disk." : "Changed on disk.") {
                    if conflict == .changedOnDisk {
                        Button("Reload") { document.reloadFromDisk() }
                        Button("Keep Mine") { document.keepMine() }
                        Button("Compare") { showingDiff = true }
                    } else {
                        Button("Keep Mine") { document.keepMine() }
                    }
                }
            } else if let error = document.error {
                notice(error) { EmptyView() }
            } else if document.isReadOnly {
                notice("Read-only: the file is large or not writable.") { EmptyView() }
            }
            EditorTextHost(document: document, paneID: paneID, font: preferences.terminalFont,
                           theme: theme, palette: preferences.terminalPalette)
        }
        .sheet(isPresented: $showingDiff) {
            DiffSheet(title: (document.path as NSString).lastPathComponent, diff: document.diffAgainstDisk()) { showingDiff = false }
        }
    }

    private func notice<Actions: View>(_ text: String, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: 12) {
            Text(text).font(TypeScale.ui(12, .medium)).foregroundStyle(theme.text.color)
            Spacer()
            actions()
                .buttonStyle(.plain)
                .font(TypeScale.ui(12, .semibold))
                .foregroundStyle(theme.text.color)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(theme.raised.color)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline.color).frame(height: 1) }
    }
}

/// A unified diff, monospaced, + and − lines by weight rather than color.
struct DiffSheet: View {
    let title: String
    let diff: String
    let done: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(title): disk → Tethera").font(TypeScale.ui(13, .semibold))
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            DiffText(diff: diff)
        }
        .frame(width: 720, height: 520)
    }
}

/// A diff in a plain, non-wrapping text view: fast for big diffs, selectable, and lines
/// marked by weight and a faint band rather than color.
struct DiffText: NSViewRepresentable {
    let diff: String
    @Environment(\.theme) private var theme

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        if let textView = scroll.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.textContainerInset = NSSize(width: 8, height: 10)
            textView.isHorizontallyResizable = true
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        return scroll
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 400, height: 300))
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        textView.backgroundColor = theme.bg.nsColor
        scroll.backgroundColor = theme.bg.nsColor
        let key = "\(diff.hashValue)|\(theme.isDark)"
        guard textView.identifier?.rawValue != key else { return }
        textView.identifier = NSUserInterfaceItemIdentifier(key)
        let font = PreferencesStore.shared.terminalFont
        let size = max(10, font.pointSize - 1)
        let regular = NSFont(descriptor: font.fontDescriptor, size: size) ?? font
        let bold = NSFontManager.shared.convert(regular, toHaveTrait: .boldFontMask)
        let output = NSMutableAttributedString()
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            let added = line.hasPrefix("+") && !line.hasPrefix("+++")
            let removed = line.hasPrefix("-") && !line.hasPrefix("---")
            let hunk = line.hasPrefix("@@")
            var attributes: [NSAttributedString.Key: Any] = [
                .font: added ? bold : regular,
                .foregroundColor: removed ? theme.text3.nsColor : (hunk ? theme.text2.nsColor : theme.text.nsColor),
            ]
            if added { attributes[.backgroundColor] = theme.raised.nsColor }
            if removed {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attributes[.strikethroughColor] = theme.text3.nsColor.withAlphaComponent(0.6)
            }
            output.append(NSAttributedString(string: String(line) + "\n", attributes: attributes))
        }
        textView.textStorage?.setAttributedString(output)
    }
}

/// The AppKit side: a line-number gutter beside a scroll view holding the text view. (An
/// NSRulerView inside the scroll view stops a hosted scroll view from drawing.)
struct EditorTextHost: NSViewRepresentable {
    @ObservedObject var document: EditorDocument
    let paneID: UUID
    let font: NSFont
    let theme: Theme
    let palette: TerminalPalette

    func makeCoordinator() -> Coordinator { Coordinator(document: document) }

    func makeNSView(context: Context) -> EditorContainer {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.borderType = .noBorder

        // TextKit 1, built by hand: line numbers and temporary attributes need the layout manager.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        layoutManager.addTextContainer(container)
        let textView = EditorTextView(frame: .zero, textContainer: container)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.document = document
        textView.paneID = paneID
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        scroll.documentView = textView
        textView.setWrapping(false)

        let gutter = LineNumberGutter(textView: textView)
        context.coordinator.ruler = gutter
        return EditorContainer(gutter: gutter, scroll: scroll)
    }

    /// Take the space offered; never ask for the text's size.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EditorContainer, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 400, height: 300))
    }

    func updateNSView(_ container: EditorContainer, context: Context) {
        let scroll = container.scroll
        guard let textView = scroll.documentView as? EditorTextView else { return }
        let coordinator = context.coordinator
        textView.isEditable = !document.isReadOnly
        // Restyling touches every character, so only when the font or theme actually changed.
        let style = "\(font.fontName)|\(font.pointSize)|\(theme.isDark)|\(palette.hashValue)"
        let restyle = style != coordinator.style
        if restyle {
            coordinator.style = style
            textView.font = font
            textView.typingAttributes = [.font: font, .foregroundColor: theme.text.nsColor]
            textView.backgroundColor = theme.bg.nsColor
            textView.insertionPointColor = theme.accent.nsColor
            textView.selectedTextAttributes = [.backgroundColor: theme.accent.nsColor.withAlphaComponent(theme.isDark ? 0.22 : 0.16)]
            scroll.backgroundColor = theme.bg.nsColor
            coordinator.colors = SyntaxHighlighter.colors(dark: theme.isDark, palette: palette, text: theme.text.nsColor, dim: theme.text3.nsColor)
            coordinator.ruler?.style(font: font, theme: theme)
        }
        if coordinator.revision != document.revision || coordinator.path != document.path {
            let sameFile = coordinator.path == document.path
            coordinator.revision = document.revision
            coordinator.path = document.path
            coordinator.highlighter = SyntaxHighlighter.forFile(document.path)
            let selection = textView.selectedRanges
            let origin = scroll.contentView.bounds.origin
            textView.string = document.text
            textView.textColor = theme.text.nsColor
            if sameFile {
                // A reload from disk keeps your place.
                let length = (document.text as NSString).length
                textView.selectedRanges = selection.map { value in
                    let range = value.rangeValue
                    return NSValue(range: NSRange(location: min(range.location, length), length: 0))
                }
                scroll.contentView.scroll(to: origin)
            }
            textView.undoManager?.removeAllActions()
            coordinator.rehighlight()
        } else if restyle {
            textView.textColor = theme.text.nsColor
            coordinator.rehighlight()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let document: EditorDocument
        weak var textView: EditorTextView?
        weak var ruler: LineNumberGutter?
        var highlighter: SyntaxHighlighter?
        var colors: [SyntaxHighlighter.Token: NSColor] = [:]
        var revision = -1
        var path = ""
        var style = ""
        private var pending: DispatchWorkItem?

        init(document: EditorDocument) { self.document = document }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            document.edited(textView.string)
            ruler?.invalidateLineStarts()
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.rehighlight() }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }

        func rehighlight() {
            guard let textView, let layoutManager = textView.layoutManager else { return }
            if let highlighter {
                highlighter.highlight(layoutManager, text: textView.string, colors: colors)
            }
            ruler?.needsDisplay = true
        }
    }
}

/// The editor's text view: ⌘S saves, ⌃G goes to a line, and focus follows the pane.
final class EditorTextView: NSTextView {
    weak var document: EditorDocument?
    var paneID: UUID?

    @objc func saveDocument(_ sender: Any?) {
        document?.save()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, let paneID { MainActor.assumeIsolated { Workspace.shared.focus(pane: paneID) } }
        return accepted
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .control, event.charactersIgnoringModifiers == "g" {
            goToLine()
            return
        }
        // Tab follows the file: a tab in tab-indented files (Makefiles, Go), else 4 or 2 spaces.
        if flags.isEmpty, event.keyCode == 48, isEditable {
            insertText(indentUnit, replacementRange: selectedRange())
            return
        }
        super.keyDown(with: event)
    }

    override func insertNewline(_ sender: Any?) {
        // Keep the current line's indentation.
        let text = string as NSString
        let lineRange = text.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        let line = text.substring(with: lineRange)
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        super.insertNewline(sender)
        if !indent.isEmpty { insertText(String(indent), replacementRange: selectedRange()) }
    }

    private var indentUnit: String {
        let sample = String(string.prefix(20_000))
        let tabs = sample.components(separatedBy: "\n\t").count
        let twos = sample.components(separatedBy: "\n  ").count, fours = sample.components(separatedBy: "\n    ").count
        if tabs > twos { return "\t" }
        return String(repeating: " ", count: twos > fours * 2 ? 2 : 4)
    }

    func setWrapping(_ wraps: Bool) {
        guard let container = textContainer else { return }
        container.widthTracksTextView = wraps
        container.containerSize = NSSize(width: wraps ? (enclosingScrollView?.contentSize.width ?? 600) : CGFloat.greatestFiniteMagnitude,
                                         height: CGFloat.greatestFiniteMagnitude)
        isHorizontallyResizable = !wraps
    }

    @objc func toggleWrap(_ sender: Any?) {
        setWrapping(!(textContainer?.widthTracksTextView ?? false))
    }

    func goToLine() {
        let alert = NSAlert()
        alert.messageText = "Go to Line"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "Line number"
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn, let line = Int(field.stringValue), line > 0 else { return }
        let text = string as NSString
        var location = 0
        for _ in 1..<line {
            let range = text.range(of: "\n", range: NSRange(location: location, length: text.length - location))
            guard range.location != NSNotFound else { break }
            location = range.location + 1
        }
        let target = NSRange(location: min(location, text.length), length: 0)
        setSelectedRange(target)
        scrollRangeToVisible(target)
        window?.makeFirstResponder(self)
    }
}

/// Holds the gutter and the scroll view side by side.
final class EditorContainer: NSView {
    let gutter: LineNumberGutter
    let scroll: NSScrollView

    init(gutter: LineNumberGutter, scroll: NSScrollView) {
        self.gutter = gutter
        self.scroll = scroll
        super.init(frame: .zero)
        clipsToBounds = true
        addSubview(gutter)
        addSubview(scroll)
        gutter.onWidthChange = { [weak self] in self?.needsLayout = true }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let width = gutter.width
        gutter.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        scroll.frame = NSRect(x: width, y: 0, width: max(0, bounds.width - width), height: bounds.height)
    }
}

/// Line numbers down the left edge, in the text's font, right-aligned. Follows the scroll view.
final class LineNumberGutter: NSView {
    private weak var textView: NSTextView?
    private var lineStarts: [Int] = [0]
    private var startsValid = false
    private var font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private var color = NSColor.secondaryLabelColor
    private var background = NSColor.textBackgroundColor
    private(set) var width: CGFloat = 44
    var onWidthChange: (() -> Void)?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: .zero)
        clipsToBounds = true
        textView.enclosingScrollView?.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification,
                                               object: textView.enclosingScrollView?.contentView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    func style(font: NSFont, theme: Theme) {
        let size = max(9, font.pointSize - 1.5)
        self.font = NSFont(descriptor: font.fontDescriptor, size: size) ?? font
        color = theme.text3.nsColor
        background = theme.bg.nsColor
        startsValid = false
        needsDisplay = true
    }

    func invalidateLineStarts() {
        startsValid = false
        needsDisplay = true
    }

    @objc private func scrolled() { needsDisplay = true }

    private func computeLineStarts() {
        guard let text = textView?.string as NSString? else { return }
        var starts = [0]
        var location = 0
        while location < text.length {
            let range = text.range(of: "\n", range: NSRange(location: location, length: text.length - location))
            guard range.location != NSNotFound else { break }
            starts.append(range.location + 1)
            location = range.location + 1
        }
        lineStarts = starts
        startsValid = true
        let digits = max(3, String(starts.count).count)
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: font]).width
        let newWidth = ceil(CGFloat(digits) * digitWidth + 22)
        if abs(newWidth - width) > 0.5 {
            width = newWidth
            onWidthChange?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Views don't clip their drawing by default (macOS 14+): stay inside our bounds.
        background.setFill()
        bounds.intersection(dirtyRect).fill()
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer,
              let clip = textView.enclosingScrollView?.contentView else { return }
        if !startsValid { computeLineStarts() }
        let visible = textView.visibleRect
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var line = lineIndex(for: characters.location)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let inset = textView.textContainerInset.height
        let offset = clip.bounds.origin.y
        let length = (textView.string as NSString).length
        while line < lineStarts.count, lineStarts[line] <= NSMaxRange(characters) {
            let fragment: NSRect
            if lineStarts[line] >= length && line > 0 {
                fragment = layoutManager.extraLineFragmentRect
            } else {
                let glyph = layoutManager.glyphIndexForCharacter(at: lineStarts[line])
                fragment = layoutManager.lineFragmentRect(forGlyphAt: min(glyph, max(0, layoutManager.numberOfGlyphs - 1)), effectiveRange: nil)
            }
            let label = "\(line + 1)" as NSString
            let size = label.size(withAttributes: attributes)
            let y = fragment.minY + inset - offset + (fragment.height - size.height) / 2
            label.draw(at: NSPoint(x: width - size.width - 12, y: y), withAttributes: attributes)
            line += 1
        }
    }

    private func lineIndex(for location: Int) -> Int {
        var low = 0, high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= location { low = mid } else { high = mid - 1 }
        }
        return low
    }
}
