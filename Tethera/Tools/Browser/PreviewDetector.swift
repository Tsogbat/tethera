import Foundation

/// Spots dev servers in a session's output (`Local: http://localhost:5173/`), so the title bar
/// can offer "Preview :5173" and open it in a browser pane beside the session.
@MainActor
final class PreviewDetector: ObservableObject {
    static let shared = PreviewDetector()

    @Published private(set) var urls: [UUID: URL] = [:]

    private static let markers = ["localhost:", "127.0.0.1:", "0.0.0.0:", "[::1]:"].map { Data($0.utf8) }
    private static let pattern = try! NSRegularExpression(
        pattern: #"https?://(?:localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\]):(\d{2,5})(/[^\s\u001b"'<>)]*)?"#)

    /// Called with every output chunk; cheap unless the chunk mentions a local address.
    func scan(_ session: UUID, _ bytes: Data) {
        guard Self.markers.contains(where: { bytes.range(of: $0) != nil }) else { return }
        // Servers color the URL and its port separately; read it without the colors.
        let text = String(decoding: bytes, as: UTF8.self)
            .replacingOccurrences(of: "\u{1b}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = Self.pattern.matches(in: text, range: range).last,
              let whole = Range(match.range, in: text) else { return }
        // 0.0.0.0 isn't browsable; it means "every interface", so localhost works.
        let address = String(text[whole]).replacingOccurrences(of: "0.0.0.0", with: "localhost")
        guard let url = URL(string: address), urls[session] != url else { return }
        urls[session] = url
    }

    /// When the shell is back in front, the server is gone.
    func sessionsChanged(_ sessions: [UUIDAndRunning]) {
        for entry in sessions where !entry.running && urls[entry.id] != nil {
            urls[entry.id] = nil
        }
        let live = Set(sessions.map(\.id))
        for id in urls.keys where !live.contains(id) { urls[id] = nil }
    }

    struct UUIDAndRunning {
        let id: UUID
        let running: Bool
    }

    /// Opens (or focuses) the preview for a session, beside it.
    func open(for session: UUID) {
        guard let url = urls[session] else { return }
        let store = BrowserStore.shared
        if let existing = store.tabs.values.first(where: { $0.isPreview && $0.url?.port == url.port }),
           Workspace.shared.panes.contains(where: { $0.content == .browser(existing.id) }) {
            Workspace.shared.open(.browser(existing.id), besideSession: session)
            existing.webView.reload()
            return
        }
        let tab = store.newTab(url: url, preview: true)
        store.assign(tab, to: session)
        Workspace.shared.open(.browser(tab.id), besideSession: session)
    }
}
