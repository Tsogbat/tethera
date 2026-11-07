import AppKit
import SwiftUI
import TetheraKit

/// How a session's state reads in the UI: words first, brightness second, and a hue
/// only for errors.
enum Tone {
    case plain, dim, attention, strong, danger

    func color(_ theme: Theme) -> Color {
        switch self {
        case .plain: return theme.text2.color
        case .dim: return theme.text3.color
        case .attention: return theme.accent.color
        case .strong: return theme.text.color
        case .danger: return theme.danger.color
        }
    }

    /// Attention reads by weight as well as brightness, since there is no accent hue.
    var weight: Font.Weight { self == .attention ? .semibold : .regular }
}

extension SessionInfo {
    /// The folder, with the home directory shortened to ~.
    var displayPath: String {
        let home = NSHomeDirectory()
        if cwd == home { return "~" }
        if cwd.hasPrefix(home + "/") { return "~" + cwd.dropFirst(home.count) }
        return cwd
    }

    var folderName: String {
        cwd == NSHomeDirectory() ? "~" : (cwd as NSString).lastPathComponent
    }

    var needsYou: Bool { agent?.state == .needsInput }
    var isWorking: Bool { agent?.state == .working }

    /// The second line in the sidebar.
    var subtitle: (text: String, tone: Tone) {
        if !isAlive { return ("restored · \(displayPath)", .dim) }
        if let agent {
            switch agent.state {
            case .needsInput:
                let why = agent.reason.map { $0 == "permission" ? "needs permission" : "needs you · \($0)" } ?? "needs you"
                return ("\(agent.kind.displayName) · \(why)", .attention)
            case .working: return ("\(agent.kind.displayName) · working", .plain)
            case .done: return ("\(agent.kind.displayName) · done", agent.unseen ? .strong : .dim)
            case .error: return ("\(agent.kind.displayName) · error", .danger)
            case .idle: return ("\(agent.kind.displayName) · waiting", agent.unseen ? .attention : .dim)
            }
        }
        if let foreground, isCommandRunning, foreground != (shell as NSString).lastPathComponent {
            return (foreground, .plain)
        }
        if let code = lastExitCode, code != 0 { return ("\(displayPath) · exit \(code)", .dim) }
        return (displayPath, .dim)
    }
}

extension AgentState {
    var label: String {
        switch self {
        case .idle: return "Waiting"
        case .working: return "Working"
        case .needsInput: return "Needs you"
        case .done: return "Done"
        case .error: return "Error"
        }
    }
}

enum Elapsed {
    /// "41s", "12m", "3h", "2d".
    static func short(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3_600)h" }
        return "\(seconds / 86_400)d"
    }
}

/// Git state for the folders on screen, refreshed in the background.
@MainActor
final class GitMonitor: ObservableObject {
    static let shared = GitMonitor()
    @Published private(set) var statuses: [String: GitStatus] = [:]
    private var inFlight: Set<String> = []
    private var lastRefresh: [String: Date] = [:]
    private var timer: Timer?

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshVisible() }
        }
    }

    func status(for cwd: String?) -> GitStatus? {
        guard let cwd else { return nil }
        if lastRefresh[cwd] == nil { refresh(cwd) }
        return statuses[cwd]
    }

    func refresh(_ cwd: String) {
        guard !inFlight.contains(cwd) else { return }
        inFlight.insert(cwd)
        lastRefresh[cwd] = Date()
        Task {
            let status = await GitService.status(for: cwd)
            inFlight.remove(cwd)
            if statuses[cwd] != status { statuses[cwd] = status }
        }
    }

    private func refreshVisible() {
        let workspace = Workspace.shared
        let visible = Set(workspace.panes.compactMap { DaemonClient.shared.session($0.session)?.cwd })
        visible.forEach(refresh)
    }
}

/// Lets the window be dragged from an otherwise empty strip.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// A quiet icon button: no background until hovered.
struct IconButton: View {
    let systemName: String
    let help: String
    var active = false
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(active ? theme.text.color : (hovering ? theme.text.color : theme.text2.color))
                .frame(width: 24, height: 22)
                .background(RoundedRectangle(cornerRadius: Metrics.controlRadius).fill(hovering || active ? theme.raised.color : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Small uppercase section label.
struct SectionLabel: View {
    let text: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text.uppercased())
            .font(TypeScale.label)
            .tracking(0.6)
            .foregroundStyle(theme.text3.color)
    }
}
