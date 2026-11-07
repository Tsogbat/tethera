import SwiftUI
import AppKit

/// Keys the editor hands to its owner before default text handling.
enum EditorKey {
    case submit
    case submitAlternate   // ⌘↩
    case tab
    case shiftTab
    case up
    case down
    case acceptGhost
    case escape
    case historySearch     // ⌃R
    case interrupt         // ⌃C
    case clearScreen       // ⌃L
}

/// NSTextView-backed command editor: multi-line, ghost text drawn exactly after the caret,
/// and terminal-style key routing.
struct CommandEditor: NSViewRepresentable {
    @Binding var text: String
    var ghost: String
    var placeholder: String
    var font: NSFont
    var textColor: NSColor
    var ghostColor: NSColor
    var caretColor: NSColor
    var focusToken: Int
    var insertion: InputInsertion?
    var onKey: (EditorKey) -> Bool
    var onHeightChange: (CGFloat) -> Void
    var onCaretX: (CGFloat) -> Void = { _ in }
    var onFocusChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = EditorTextView(frame: .zero)
        textView.coordinator = context.coordinator
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        context.coordinator.textView = textView
        apply(to: textView)
        textView.string = text
        DispatchQueue.main.async { context.coordinator.reportMetrics() }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.parent = self
        apply(to: textView)

        if let insertion, insertion.id != context.coordinator.lastInsertionID {
            context.coordinator.lastInsertionID = insertion.id
            textView.string = insertion.text
            if insertion.selectAll {
                textView.setSelectedRange(NSRange(location: 0, length: (insertion.text as NSString).length))
            } else {
                textView.setSelectedRange(NSRange(location: (insertion.text as NSString).length, length: 0))
            }
            textView.undoManager?.removeAllActions()
            DispatchQueue.main.async {
                if text != insertion.text { text = insertion.text }
            }
        } else if textView.string != text && !textView.hasMarkedText() {
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }

        if focusToken != context.coordinator.lastFocusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                guard let window = textView.window else { return }
                if window.firstResponder !== textView {
                    window.makeFirstResponder(textView)
                }
            }
        }
        textView.needsDisplay = true
        context.coordinator.reportMetrics()
    }

    private func apply(to textView: EditorTextView) {
        if textView.font != font {
            textView.font = font
            textView.typingAttributes = [.font: font, .foregroundColor: textColor]
        }
        textView.textColor = textColor
        textView.insertionPointColor = caretColor
        textView.ghostText = ghost
        textView.placeholder = placeholder
        textView.ghostColor = ghostColor
        textView.typingAttributes[.foregroundColor] = textColor
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CommandEditor
        weak var textView: EditorTextView?
        var lastInsertionID: UUID?
        var lastFocusToken = Int.min
        private var lastHeight: CGFloat = 0

        init(parent: CommandEditor) {
            self.parent = parent
            self.lastFocusToken = parent.focusToken - 1
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            reportMetrics()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            textView?.needsDisplay = true
            reportMetrics()
        }

        func handle(_ key: EditorKey) -> Bool {
            parent.onKey(key)
        }

        func focusChanged(_ focused: Bool) {
            parent.onFocusChange(focused)
        }

        func reportMetrics() {
            guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container).height
            let lineHeight = layoutManager.defaultLineHeight(for: textView.font ?? .systemFont(ofSize: 13))
            let height = min(max(used, lineHeight), lineHeight * 8) + textView.textContainerInset.height * 2
            if abs(height - lastHeight) > 0.5 {
                lastHeight = height
                let report = parent.onHeightChange
                DispatchQueue.main.async { report(height) }
            }
            let caretX = textView.wordStartX()
            let reportX = parent.onCaretX
            DispatchQueue.main.async { reportX(caretX) }
        }
    }
}

final class EditorTextView: NSTextView {
    weak var coordinator: CommandEditor.Coordinator?
    var ghostText: String = "" { didSet { if ghostText != oldValue { needsDisplay = true } } }
    var placeholder: String = "" { didSet { if placeholder != oldValue { needsDisplay = true } } }
    var ghostColor: NSColor = .tertiaryLabelColor

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { coordinator?.focusChanged(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { coordinator?.focusChanged(false) }
        return accepted
    }

    private var caretAtEnd: Bool {
        let range = selectedRange()
        return range.length == 0 && range.location == (string as NSString).length
    }

    private var caretOnFirstLine: Bool {
        let prefix = (string as NSString).substring(to: min(selectedRange().location, (string as NSString).length))
        return !prefix.contains("\n")
    }

    private var caretOnLastLine: Bool {
        let location = min(selectedRange().location + selectedRange().length, (string as NSString).length)
        let suffix = (string as NSString).substring(from: location)
        return !suffix.contains("\n")
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let handled: Bool
        switch event.keyCode {
        case 36, 76: // return, keypad enter
            if flags.contains(.shift) || flags.contains(.option) {
                insertNewlineIgnoringFieldEditor(nil)
                return
            }
            handled = coordinator?.handle(flags.contains(.command) ? .submitAlternate : .submit) ?? false
        case 48:
            handled = coordinator?.handle(flags.contains(.shift) ? .shiftTab : .tab) ?? false
        case 126 where flags.isDisjoint(with: [.command, .option, .shift]):
            handled = caretOnFirstLine ? (coordinator?.handle(.up) ?? false) : false
        case 125 where flags.isDisjoint(with: [.command, .option, .shift]):
            handled = caretOnLastLine ? (coordinator?.handle(.down) ?? false) : false
        case 124 where flags.isDisjoint(with: [.command, .option, .shift, .control]):
            handled = caretAtEnd && !ghostText.isEmpty ? (coordinator?.handle(.acceptGhost) ?? false) : false
        case 119: // End
            handled = caretAtEnd && !ghostText.isEmpty ? (coordinator?.handle(.acceptGhost) ?? false) : false
        case 53:
            handled = coordinator?.handle(.escape) ?? false
        case 15 where flags == .control: // ⌃R
            handled = coordinator?.handle(.historySearch) ?? false
        case 8 where flags == .control: // ⌃C
            handled = coordinator?.handle(.interrupt) ?? false
        case 37 where flags == .control: // ⌃L
            handled = coordinator?.handle(.clearScreen) ?? false
        case 14 where flags == .control: // ⌃E accepts ghost at end of line
            handled = caretAtEnd && !ghostText.isEmpty ? (coordinator?.handle(.acceptGhost) ?? false) : false
        default:
            handled = false
        }
        if !handled {
            super.keyDown(with: event)
        }
    }

    override func paste(_ sender: Any?) {
        // Plain text only; trailing newlines from copied commands would otherwise linger.
        if let string = NSPasteboard.general.string(forType: .string) {
            insertText(string.trimmingCharacters(in: .newlines), replacementRange: selectedRange())
        } else {
            super.paste(sender)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let font, let layoutManager, let textContainer else { return }
        let origin = textContainerOrigin
        let length = (string as NSString).length

        if length == 0 && !placeholder.isEmpty && ghostText.isEmpty {
            (placeholder as NSString).draw(at: NSPoint(x: origin.x, y: origin.y),
                                           withAttributes: [.font: font, .foregroundColor: ghostColor])
            return
        }
        guard !ghostText.isEmpty, caretAtEnd, !string.hasSuffix("\n"), !hasMarkedText() else { return }

        var point = NSPoint(x: origin.x, y: origin.y)
        if length > 0 {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: length - 1, length: 1), actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: max(0, glyphRange.location), effectiveRange: nil)
            point = NSPoint(x: origin.x + rect.maxX, y: origin.y + lineRect.minY)
        }
        let firstLine = ghostText.components(separatedBy: "\n").first ?? ghostText
        (firstLine as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: ghostColor])
    }

    /// X position (in this view) where the word under the caret begins — anchors the completion menu.
    func wordStartX() -> CGFloat {
        guard let layoutManager, let textContainer else { return 0 }
        let nsString = string as NSString
        let caret = min(selectedRange().location, nsString.length)
        var start = caret
        while start > 0 {
            let character = nsString.character(at: start - 1)
            if character == 32 || character == 10 || character == 9 { break }
            start -= 1
        }
        guard start > 0 else { return textContainerOrigin.x }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: start - 1, length: 1), actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        return textContainerOrigin.x + rect.maxX
    }
}
