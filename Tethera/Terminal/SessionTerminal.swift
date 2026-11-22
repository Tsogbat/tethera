import AppKit
import SwiftTerm
import TetheraKit

/// What the app needs from a terminal renderer. SwiftTerm implements it today; another engine
/// (libghostty) can slot in without touching the rest of the app.
@MainActor
protocol TerminalSurface: AnyObject {
    var hostView: NSView { get }
    var gridSize: (cols: Int, rows: Int) { get }
    func feed(_ bytes: Data)
    @discardableResult func focus() -> Bool
    func apply(_ preferences: Preferences, palette: TerminalPalette, theme: Theme, font: NSFont)
}

/// One session's terminal: a view fed by the daemon. The daemon is the terminal of record, so
/// this view only renders and forwards keys; it never answers the program's queries itself.
@MainActor
final class SessionTerminal: NSObject, TerminalSurface, TerminalViewDelegate {
    let sessionID: UUID
    private let terminalView: SurfaceView
    private let container: PaddedContainer
    private(set) var isAttached = false
    private var appliedKey: String?
    /// Called when the user clicks or tabs into this terminal.
    var onFocus: (() -> Void)?
    /// What's typed at the prompt, for suggestions.
    private var line = PromptLine()
    private let ghost = GhostTextView()
    private var ghostText: String?
    private let popup = CompletionPopup()
    private var suggestionUpdateScheduled = false
    /// A headless copy of the screen, for where the cursor is (SwiftTerm's Metal renderer
    /// draws the cursor itself and doesn't say where).
    private var mirror: Terminal?
    private var scrolledBack = false

    var hostView: NSView { container }

    var gridSize: (cols: Int, rows: Int) {
        let dimensions = terminalView.terminalDimensions
        return (dimensions.cols, dimensions.rows)
    }

    init(sessionID: UUID) {
        self.sessionID = sessionID
        terminalView = SurfaceView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        container = PaddedContainer(content: terminalView)
        super.init()
        terminalView.terminalDelegate = self
        terminalView.scrollerStyle = .overlay
        terminalView.allowMouseReporting = true
        terminalView.glyphFallbackProvider = SymbolFallback.shared
        terminalView.onLayoutReady = { [weak self] in
            guard let self else { return }
            self.attachIfNeeded()
            TerminalStore.shared.landed(self)
        }
        // Over the terminal, in the container: SwiftTerm's Metal layer doesn't draw subviews.
        ghost.isHidden = true
        container.addSubview(ghost)
        let preferences = PreferencesStore.shared
        apply(preferences.value, palette: preferences.terminalPalette, theme: preferences.theme, font: preferences.terminalFont)
    }

    // MARK: Attach

    /// Attaches once the view has its real size, so the daemon's snapshot fits on the first try.
    func attachIfNeeded() {
        guard !isAttached, terminalView.window != nil, terminalView.bounds.width > 40 else { return }
        isAttached = true
        let size = gridSize
        DaemonClient.shared.attach(sessionID, cols: size.cols, rows: size.rows) { [weak self] frame in
            self?.receive(frame)
        }
    }

    func detach() {
        guard isAttached else { return }
        isAttached = false
        DaemonClient.shared.detach(sessionID)
    }

    private func receive(_ frame: Frame) {
        switch frame {
        case .snapshot(_, _, let bytes):
            // A snapshot redraws everything, so the cursor-tracking copy starts over from it.
            mirror = nil
            if PreferencesStore.shared.value.suggestCommands {
                let size = gridSize
                mirror = Terminal(delegate: MirrorDelegate.shared, options: TerminalOptions(cols: max(size.cols, 10), rows: max(size.rows, 2), scrollback: 200))
            }
            feed(bytes)
            line.reset()
            hideSuggestions()
        case .output(_, _, let bytes):
            feed(bytes)
            PreviewDetector.shared.scan(sessionID, bytes)
            line.output(bytes)
            scheduleSuggestionUpdate()
        default:
            break
        }
    }

    func feed(_ bytes: Data) {
        terminalView.feed(byteArray: ArraySlice(bytes))
        // Only kept in step from a snapshot on; turning suggestions on starts it at the next attach.
        if PreferencesStore.shared.value.suggestCommands { mirror?.feed(byteArray: Array(bytes)) } else { mirror = nil }
    }

    /// Gives this terminal the keyboard; false while its view isn't in a window yet.
    @discardableResult
    func focus() -> Bool {
        guard let window = terminalView.window else { return false }
        if window.firstResponder !== terminalView { window.makeFirstResponder(terminalView) }
        return window.firstResponder === terminalView
    }

    var hasFocus: Bool {
        terminalView.window?.firstResponder === terminalView
    }

    // MARK: Appearance

    func apply(_ preferences: Preferences, palette: TerminalPalette, theme: Theme, font: NSFont) {
        let key = "\(font.fontName)|\(font.pointSize)|\(palette.hashValue)|\(preferences.cursor)|\(preferences.cursorBlink)|\(preferences.optionAsMeta)|\(preferences.useMetal)|\(theme.isDark)"
        guard key != appliedKey else { return }
        appliedKey = key
        if terminalView.font.fontName != font.fontName || terminalView.font.pointSize != font.pointSize {
            terminalView.font = font
        }
        terminalView.installColors(palette.ansi.map { SwiftTerm.Color(red: UInt16($0.r) * 257, green: UInt16($0.g) * 257, blue: UInt16($0.b) * 257) })
        terminalView.nativeForegroundColor = palette.foreground.nsColor
        terminalView.nativeBackgroundColor = palette.background.nsColor
        terminalView.caretColor = theme.accent.nsColor
        terminalView.selectedTextBackgroundColor = theme.accent.nsColor.withAlphaComponent(theme.isDark ? 0.28 : 0.22)
        terminalView.optionAsMetaKey = preferences.optionAsMeta
        terminalView.setCursorStyle(preferences.cursor.style(blink: preferences.cursorBlink))
        if preferences.useMetal != terminalView.isUsingMetalRenderer {
            try? terminalView.setUseMetal(preferences.useMetal)
        }
        container.background = palette.background.nsColor
        ghost.font = font
        ghost.color = palette.foreground.nsColor.withAlphaComponent(0.38)
    }

    // MARK: Suggestions

    func owns(_ view: NSView) -> Bool { view === terminalView }

    private var suggestionsAllowed: Bool {
        guard PreferencesStore.shared.value.suggestCommands, let session = DaemonClient.shared.session(sessionID) else { return false }
        return session.host == nil && session.agent == nil
    }

    private func scheduleSuggestionUpdate() {
        guard !suggestionUpdateScheduled else { return }
        suggestionUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.suggestionUpdateScheduled = false
            self.updateGhost()
        }
    }

    /// Shows the rest of the newest history entry that starts with what's typed.
    private func updateGhost() {
        guard suggestionsAllowed, !popup.isVisible, let typed = line.text, let rest = CompletionEngine.shared.ghost(for: typed) else {
            ghostText = nil
            ghost.isHidden = true
            return
        }
        guard let caret = caretRect() else {
            ghostText = nil
            ghost.isHidden = true
            return
        }
        ghostText = rest
        ghost.text = rest
        let width = min(CGFloat(rest.count) * caret.width + 2, max(0, container.bounds.width - caret.minX))
        ghost.frame = NSRect(x: caret.minX, y: caret.minY, width: width, height: caret.height)
        ghost.isHidden = false
    }

    /// The cursor's cell in the container, when it sits at the end of what's typed on the
    /// visible screen; nil otherwise (scrolled back, or text after the cursor).
    private func caretRect() -> NSRect? {
        guard let mirror, !scrolledBack, !mirror.isCurrentBufferAlternate else { return nil }
        let (x, y) = mirror.getCursorLocation()
        guard let line = mirror.getLine(row: y),
              line.translateToString(trimRight: true, startCol: min(x, mirror.cols)).isEmpty else { return nil }
        let font = terminalView.font
        var characters: [UniChar] = [0x57]
        var glyphs: [CGGlyph] = [0]
        let width = CTFontGetGlyphsForCharacters(font, &characters, &glyphs, 1)
            ? font.advancement(forGlyph: NSGlyph(glyphs[0])).width : font.maximumAdvancement.width
        let height = ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
        let cell = NSRect(x: CGFloat(x) * width, y: terminalView.bounds.height - CGFloat(y + 1) * height, width: width, height: height)
        return container.convert(cell, from: terminalView)
    }

    func dismissPopup() {
        if popup.isVisible { popup.hide() }
    }

    private func hideSuggestions() {
        ghostText = nil
        ghost.isHidden = true
        popup.hide()
    }

    /// Keys for suggestions: → or End take the ghost text; ⌃Space lists candidates, which ↑ ↓
    /// choose, Return or Tab insert and Escape closes. Returns true when the key was used.
    func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if popup.isVisible {
            switch event.keyCode {
            case 125: popup.move(1); return true
            case 126: popup.move(-1); return true
            case 36, 48, 76: insertSelected(); return true
            case 53: popup.hide(); updateGhost(); return true
            default: popup.hide()
            }
        }
        if event.keyCode == 49, modifiers == .control, suggestionsAllowed, let typed = line.text {
            let session = DaemonClient.shared.session(sessionID)
            let (word, items) = CompletionEngine.shared.candidates(for: typed, cwd: session?.localFolder)
            ghost.isHidden = true
            let preferences = PreferencesStore.shared
            guard let caret = caretRect() else { NSSound.beep(); return true }
            popup.show(items, word: word, at: caret, in: container, theme: preferences.theme, font: preferences.terminalFont)
            if !popup.isVisible { NSSound.beep() }
            return true
        }
        if let rest = ghostText, !rest.isEmpty, modifiers.isEmpty, event.keyCode == 124 || event.keyCode == 119 {
            type(rest)
            return true
        }
        return false
    }

    private func insertSelected() {
        guard let item = popup.selected else { return popup.hide() }
        let rest = String(item.text.dropFirst(popup.word.count)) + (item.kind == .folder ? "" : " ")
        popup.hide()
        type(rest)
    }

    /// Text typed into the session, followed for suggestions like keys are (debug scripts).
    func input(_ text: String) {
        let bytes = Data(text.utf8)
        DaemonClient.shared.send(sessionID, bytes)
        if let command = line.input(bytes) { CompletionEngine.shared.remember(command) }
    }

    /// Sends text as if typed.
    private func type(_ text: String) {
        let data = Data(text.utf8)
        DaemonClient.shared.send(sessionID, data)
        _ = line.input(data)
        ghostText = nil
        ghost.isHidden = true
    }

    // MARK: TerminalViewDelegate

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        mirror?.resize(cols: newCols, rows: newRows)
        if isAttached {
            DaemonClient.shared.resize(sessionID, cols: newCols, rows: newRows)
        } else {
            attachIfNeeded()
        }
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let bytes = Data(data)
        DaemonClient.shared.send(sessionID, bytes)
        if let command = line.input(bytes) { CompletionEngine.shared.remember(command) }
        if ghostText != nil { ghost.isHidden = true }
    }

    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {
        // 0 also means "no scrollback yet", which isn't scrolled back.
        scrolledBack = position < 0.999 && source.canScroll
        if scrolledBack { hideSuggestions() }
    }
    func bell(source: TerminalView) {}
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    /// ⌘-click: local servers and files open in Tethera beside the session; other links in
    /// your default browser.
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), let scheme = url.scheme?.lowercased(), ["http", "https", "file", "mailto"].contains(scheme) else { return }
        let session = sessionID
        MainActor.assumeIsolated {
            if scheme == "file" {
                Workspace.shared.open(path: url.path, besideSession: session)
            } else if ["localhost", "127.0.0.1", "0.0.0.0", "::1"].contains(url.host ?? "") {
                let tab = BrowserStore.shared.newTab(url: url)
                BrowserStore.shared.assign(tab, to: session)
                Workspace.shared.open(.browser(tab.id), besideSession: session)
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        guard let text = String(data: content, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// The cursor-tracking copy of a session's screen answers nothing; the daemon does that.
private final class MirrorDelegate: TerminalDelegate {
    static let shared = MirrorDelegate()
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}

/// SwiftTerm's view, telling us when layout has given it a real size.
final class SurfaceView: TerminalView {
    var onLayoutReady: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { DispatchQueue.main.async { [weak self] in self?.onLayoutReady?() } }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if newSize.width > 40 { onLayoutReady?() }
    }
}

/// Insets the terminal by a little padding, filled with the terminal's own background.
final class PaddedContainer: NSView {
    private let content: NSView
    var background: NSColor = .black {
        didSet { layer?.backgroundColor = background.cgColor }
    }

    init(content: NSView) {
        self.content = content
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(content)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        let padding = Metrics.terminalPadding
        content.frame = bounds.insetBy(dx: padding, dy: padding / 2)
    }
}

/// Keeps a terminal per session so switching is instant, attached while it's on screen and for
/// a few recently used sessions; the rest detach and reattach from a snapshot when shown.
@MainActor
final class TerminalStore {
    static let shared = TerminalStore()
    private var terminals: [UUID: SessionTerminal] = [:]
    private var recent: [UUID] = []
    private let keepAttached = 6
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    /// A focus request whose terminal isn't in the window yet: SwiftUI moves a terminal into its
    /// pane on its next update, which can land after the request. Kept briefly, then dropped.
    private var pendingFocus: (id: UUID, until: Date)?

    private init() {
        // SwiftTerm's becomeFirstResponder isn't overridable, so a click tells us which pane took focus.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            MainActor.assumeIsolated {
                for terminal in TerminalStore.shared.terminals.values where terminal.hostView.window === event.window {
                    terminal.dismissPopup()
                    let point = terminal.hostView.convert(event.locationInWindow, from: nil)
                    if terminal.hostView.bounds.contains(point) { terminal.onFocus?() }
                }
                // The sidebar is a List, whose table view takes the keyboard when a click lands
                // between or below its rows; once the click is handled, the terminal gets it back.
                if event.locationInWindow.x < PreferencesStore.shared.value.sidebarWidth {
                    DispatchQueue.main.async {
                        if event.window?.firstResponder is NSTableView { Workspace.shared.focusTerminalSoon() }
                    }
                }
            }
            return event
        }
        // Suggestion keys reach the focused terminal before SwiftTerm sees them.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let used = MainActor.assumeIsolated {
                guard let responder = event.window?.firstResponder as? NSView,
                      let terminal = TerminalStore.shared.terminals.values.first(where: { $0.owns(responder) }) else { return false }
                return terminal.handleKey(event)
            }
            return used ? nil : event
        }
    }

    func terminal(for id: UUID) -> SessionTerminal {
        if let existing = terminals[id] {
            touch(id)
            return existing
        }
        let terminal = SessionTerminal(sessionID: id)
        terminals[id] = terminal
        touch(id)
        return terminal
    }

    func existing(_ id: UUID) -> SessionTerminal? {
        terminals[id]
    }

    /// Focuses a session's terminal now if it's on screen, or as soon as it gets there.
    func requestFocus(_ id: UUID) {
        if let terminal = terminals[id], terminal.focus() {
            pendingFocus = nil
        } else {
            pendingFocus = (id, Date().addingTimeInterval(1.5))
        }
    }

    /// A terminal's view reached a window with a real size: it takes a focus request waiting for it.
    func landed(_ terminal: SessionTerminal) {
        guard let pending = pendingFocus, pending.id == terminal.sessionID else { return }
        guard pending.until > Date(), Workspace.shared.renaming == nil else { pendingFocus = nil; return }
        if terminal.focus() { pendingFocus = nil }
    }

    private func touch(_ id: UUID) {
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
        for stale in recent.dropFirst(keepAttached) {
            guard let terminal = terminals[stale], terminal.hostView.window == nil else { continue }
            terminal.detach()
            terminals.removeValue(forKey: stale)
        }
        recent = Array(recent.prefix(keepAttached + 4))
    }

    /// Drops terminals whose session ended.
    func prune(keeping ids: Set<UUID>) {
        for (id, terminal) in terminals where !ids.contains(id) {
            terminal.detach()
            terminals.removeValue(forKey: id)
        }
        recent.removeAll { !ids.contains($0) }
    }

    func applyPreferences() {
        let store = PreferencesStore.shared
        for terminal in terminals.values {
            terminal.apply(store.value, palette: store.terminalPalette, theme: store.theme, font: store.terminalFont)
        }
    }
}
