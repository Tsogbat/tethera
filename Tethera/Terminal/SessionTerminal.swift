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
    func focus()
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
        terminalView.onLayoutReady = { [weak self] in self?.attachIfNeeded() }
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
            feed(bytes)
        case .output(_, _, let bytes):
            feed(bytes)
            PreviewDetector.shared.scan(sessionID, bytes)
        default:
            break
        }
    }

    func feed(_ bytes: Data) {
        terminalView.feed(byteArray: ArraySlice(bytes))
    }

    func focus() {
        guard let window = terminalView.window, window.firstResponder !== terminalView else { return }
        window.makeFirstResponder(terminalView)
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
    }

    // MARK: TerminalViewDelegate

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        if isAttached {
            DaemonClient.shared.resize(sessionID, cols: newCols, rows: newRows)
        } else {
            attachIfNeeded()
        }
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        DaemonClient.shared.send(sessionID, Data(data))
    }

    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
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

    private init() {
        // SwiftTerm's becomeFirstResponder isn't overridable, so a click tells us which pane took focus.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            MainActor.assumeIsolated {
                for terminal in TerminalStore.shared.terminals.values where terminal.hostView.window === event.window {
                    let point = terminal.hostView.convert(event.locationInWindow, from: nil)
                    if terminal.hostView.bounds.contains(point) { terminal.onFocus?() }
                }
            }
            return event
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
