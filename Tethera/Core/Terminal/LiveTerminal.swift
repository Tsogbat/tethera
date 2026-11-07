import AppKit
import SwiftTerm

/// SwiftTerm view with hooks Tethera needs (alternate screen, bell) and no legacy scroller.
final class TetheraTerminalView: TerminalView {
    var onBufferActivated: (() -> Void)?
    var onBell: (() -> Void)?
    /// When true, wheel events scroll the surrounding block list instead of the emulator.
    var forwardsScrollWheel = true

    override func bufferActivated(source: Terminal) {
        super.bufferActivated(source: source)
        onBufferActivated?()
    }

    override func bell(source: Terminal) {
        onBell?()
    }

    var scrollerWidth: CGFloat {
        subviews.first(where: { $0 is NSScroller })?.frame.width ?? 0
    }

    func hideScroller() {
        for case let scroller as NSScroller in subviews {
            scroller.isHidden = true
        }
    }
}

/// One emulator per tab. Command output is fed here while it runs, then captured
/// into a `StyledText` snapshot when the command finishes.
final class LiveTerminal: ObservableObject {
    let view: TetheraTerminalView

    @Published private(set) var contentRows = 1
    @Published private(set) var isAlternateScreen = false

    var onInput: ((ArraySlice<UInt8>) -> Void)?
    var onResize: ((_ columns: Int, _ rows: Int) -> Void)?
    var onBell: (() -> Void)?
    var onTitle: ((String) -> Void)?

    var columns: Int { terminal.cols }
    var rows: Int { terminal.rows }
    private(set) var cellSize = CGSize(width: 8, height: 17)
    private(set) var terminalHeight: CGFloat = 520
    private var scrollback = 10_000
    private var kittyFilter = KittyKeyboardFilter()
    private let bridge = Bridge()

    init() {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view = TetheraTerminalView(frame: NSRect(x: 0, y: 0, width: 900, height: 520), font: font)
        bridge.owner = self
        view.terminalDelegate = bridge
        view.hideScroller()
        view.optionAsMetaKey = true
        view.nativeBackgroundColor = .clear
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.getTerminal().options.scrollback = scrollback
        view.onBufferActivated = { [weak self] in self?.refreshMetrics() }
        view.onBell = { [weak self] in self?.onBell?() }
        updateCellSize(font)
        LiveTerminalScrollRouter.install()
    }

    var terminal: Terminal { view.getTerminal() }

    // MARK: Appearance

    func applyAppearance(font: NSFont, palette: TerminalPalette, caret: NSColor,
                         cursorStyle: CursorStyle, optionAsMeta: Bool, scrollbackLines: Int) {
        scrollback = scrollbackLines
        if view.font.fontName != font.fontName || view.font.pointSize != font.pointSize {
            view.font = font
            updateCellSize(font)
        }
        terminal.options.scrollback = scrollback
        view.installColors(palette.ansi.map { SwiftTerm.Color(red: UInt16($0.r) * 257, green: UInt16($0.g) * 257, blue: UInt16($0.b) * 257) })
        view.nativeForegroundColor = palette.foreground.nsColor
        view.nativeBackgroundColor = .clear
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.caretColor = caret
        view.optionAsMetaKey = optionAsMeta
        terminal.setCursorStyle(cursorStyle)
        view.hideScroller()
    }

    private func updateCellSize(_ font: NSFont) {
        let height = ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
        let width = ("W" as NSString).size(withAttributes: [.font: font]).width
        cellSize = CGSize(width: max(1, width), height: max(1, height))
    }

    // MARK: Geometry

    /// Sizes the emulator to the pane. Rows always span the full pane so programs see a
    /// real screen; inline blocks simply clip to the rows in use.
    func setGeometry(width: CGFloat, height: CGFloat) {
        terminalHeight = max(cellSize.height * 4, height)
        let size = NSSize(width: max(cellSize.width * 20, width) + view.scrollerWidth, height: terminalHeight)
        if abs(view.frame.width - size.width) > 0.5 || abs(view.frame.height - size.height) > 0.5 {
            view.frame = NSRect(origin: view.frame.origin, size: size)
            view.hideScroller()
        }
    }

    var inlineHeight: CGFloat {
        min(CGFloat(contentRows) * cellSize.height, terminalHeight)
    }

    // MARK: Output

    func beginRun() {
        kittyFilter.reset()
        view.feed(text: "\u{1b}c")  // RIS: fresh screen + scrollback for the new block
        terminal.options.scrollback = scrollback
        view.forwardsScrollWheel = true
        refreshMetrics()
    }

    func feed(_ bytes: ArraySlice<UInt8>) {
        let filtered = kittyFilter.filter(bytes)
        guard !filtered.isEmpty else { return }
        view.feed(byteArray: filtered[...])
        refreshMetrics()
    }

    func snapshot(maxLines: Int = 5_000) -> StyledText {
        StyledText.capture(from: terminal, maxLines: maxLines)
    }

    func focus() {
        guard let window = view.window else { return }
        if window.firstResponder !== view {
            window.makeFirstResponder(view)
        }
    }

    var hasFocus: Bool {
        view.window?.firstResponder === view
    }

    private func refreshMetrics() {
        let rowsInUse = StyledText.usedRows(in: terminal)
        if rowsInUse != contentRows { contentRows = rowsInUse }
        let alternate = terminal.isCurrentBufferAlternate
        if alternate != isAlternateScreen { isAlternateScreen = alternate }
    }

    // MARK: Delegate bridge

    private final class Bridge: TerminalViewDelegate {
        weak var owner: LiveTerminal?

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            guard let owner else { return }
            owner.onResize?(newCols, newRows)
            owner.refreshMetrics()
        }

        func setTerminalTitle(source: TerminalView, title: String) {
            owner?.onTitle?(title)
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            owner?.onInput?(data)
        }

        func scrolled(source: TerminalView, position: Double) {}

        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            if let url = URL(string: link) {
                NSWorkspace.shared.open(url)
            }
        }

        func bell(source: TerminalView) {
            owner?.onBell?()
        }

        func clipboardCopy(source: TerminalView, content: Data) {
            if let string = String(data: content, encoding: .utf8) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(string, forType: .string)
            }
        }

        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}

/// SwiftTerm doesn't let subclasses override `scrollWheel`, so inline blocks hand wheel
/// events to the enclosing block list through a local event monitor.
enum LiveTerminalScrollRouter {
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard let window = event.window,
                  let hit = window.contentView?.hitTest(event.locationInWindow) else { return event }
            var view: NSView? = hit
            while let current = view, !(current is TetheraTerminalView) {
                view = current.superview
            }
            guard let terminalView = view as? TetheraTerminalView else { return event }
            let terminal = terminalView.getTerminal()
            let wantsWheel = !terminalView.forwardsScrollWheel || terminal.isCurrentBufferAlternate
            if wantsWheel { return event }
            if let scrollView = terminalView.enclosingScrollView {
                scrollView.scrollWheel(with: event)
                return nil
            }
            return event
        }
    }
}
