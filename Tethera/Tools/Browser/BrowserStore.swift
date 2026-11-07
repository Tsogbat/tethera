import AppKit
import Combine
import SwiftUI
import WebKit

/// Browser tabs. Each tab is shown in a pane; agents drive the same tabs through `tethera mcp`.
@MainActor
final class BrowserStore: ObservableObject {
    static let shared = BrowserStore()
    private static let key = "tethera.browserTabs"

    @Published private(set) var tabs: [UUID: BrowserTab] = [:]
    /// The tab each session's agent last used, so its next call lands in the same tab.
    private var tabForSession: [UUID: UUID] = [:]
    /// Logins and cookies last until Tethera quits; nothing is written to disk.
    let dataStore = WKWebsiteDataStore.nonPersistent()

    var tabIDs: Set<UUID> { Set(tabs.keys) }

    private init() {
        // Tabs open at quit come back (their pages reload when shown).
        let saved = AppDefaults.store.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        for (id, url) in saved {
            guard let id = UUID(uuidString: id) else { continue }
            tabs[id] = BrowserTab(id: id, url: URL(string: url), store: self)
        }
    }

    func tab(_ id: UUID) -> BrowserTab? { tabs[id] }

    @discardableResult
    func newTab(url: URL? = nil, preview: Bool = false) -> BrowserTab {
        let tab = BrowserTab(id: UUID(), url: url, store: self)
        tab.isPreview = preview
        tabs[tab.id] = tab
        save()
        return tab
    }

    func close(_ id: UUID) {
        tabs.removeValue(forKey: id)?.tearDown()
        tabForSession = tabForSession.filter { $0.value != id }
        save()
    }

    /// The tab an agent in `session` should act on: its last one if it's still open, otherwise
    /// a new tab opened beside the session.
    func tabForAgent(session: UUID?, create: Bool = true) -> BrowserTab? {
        if let session, let id = tabForSession[session], let tab = tabs[id] { return tab }
        if session == nil, let any = tabs.values.first { return any }
        guard create else { return nil }
        let tab = newTab()
        if let session { tabForSession[session] = tab.id }
        Workspace.shared.open(.browser(tab.id), besideSession: session)
        return tab
    }

    func assign(_ tab: BrowserTab, to session: UUID?) {
        if let session { tabForSession[session] = tab.id }
    }

    func save() {
        var saved: [String: String] = [:]
        for (id, tab) in tabs { saved[id.uuidString] = tab.url?.absoluteString ?? "about:blank" }
        AppDefaults.store.set(saved, forKey: Self.key)
    }
}

/// One tab: a WKWebView and what the header shows about it.
@MainActor
final class BrowserTab: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let id: UUID
    @Published var url: URL?
    @Published var title = ""
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    /// An agent is running a browser tool in this tab right now.
    @Published var agentDriving = false
    /// Opened for a dev server: reloads when files change unless the page hot-reloads itself.
    var isPreview = false

    private weak var store: BrowserStore?
    private var webViewStorage: WKWebView?
    private var loadWaiters: [CheckedContinuation<Void, Never>] = []
    private var observations: [NSKeyValueObservation] = []

    init(id: UUID, url: URL?, store: BrowserStore) {
        self.id = id
        self.url = url
        self.store = store
    }

    /// Created on first use, so restored tabs cost nothing until they're shown.
    var webView: WKWebView {
        if let webViewStorage { return webViewStorage }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store?.dataStore ?? .nonPersistent()
        configuration.preferences.isElementFullscreenEnabled = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        view.allowsMagnification = true
        view.isInspectable = true
        observations = [
            view.observe(\.title) { [weak self] view, _ in MainActor.assumeIsolated { self?.title = view.title ?? "" } },
            view.observe(\.url) { [weak self] view, _ in MainActor.assumeIsolated { self?.urlChanged(view.url) } },
            view.observe(\.isLoading) { [weak self] view, _ in MainActor.assumeIsolated { self?.isLoading = view.isLoading } },
            view.observe(\.canGoBack) { [weak self] view, _ in MainActor.assumeIsolated { self?.canGoBack = view.canGoBack } },
            view.observe(\.canGoForward) { [weak self] view, _ in MainActor.assumeIsolated { self?.canGoForward = view.canGoForward } },
        ]
        webViewStorage = view
        if let url, url.absoluteString != "about:blank" { view.load(URLRequest(url: url)) }
        return view
    }

    private func urlChanged(_ new: URL?) {
        guard let new else { return }
        url = new
        store?.save()
    }

    /// Accepts "example.com", "localhost:3000" or a search.
    static func resolve(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https", "file", "about"].contains(scheme) { return url }
        let local = trimmed.hasPrefix("localhost") || trimmed.hasPrefix("127.") || trimmed.hasPrefix("0.0.0.0") || trimmed.hasPrefix("[::1]")
        if local { return URL(string: "http://" + trimmed) }
        if !trimmed.contains(" "), trimmed.contains("."), let url = URL(string: "https://" + trimmed) { return url }
        var components = URLComponents(string: "https://duckduckgo.com/")!
        components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components.url
    }

    func load(_ url: URL) {
        self.url = url
        webView.load(URLRequest(url: url))
        store?.save()
    }

    /// Navigates and waits for the page to finish (or 20 s).
    func loadAndWait(_ url: URL) async {
        load(url)
        await waitForLoad(timeout: 20)
    }

    func waitForLoad(timeout: TimeInterval) async {
        guard webView.isLoading else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            loadWaiters.append(continuation)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in self?.finishWaiters() }
        }
    }

    private func finishWaiters() {
        let waiters = loadWaiters
        loadWaiters = []
        waiters.forEach { $0.resume() }
    }

    func tearDown() {
        finishWaiters()
        webViewStorage?.stopLoading()
        webViewStorage?.navigationDelegate = nil
        webViewStorage?.removeFromSuperview()
        webViewStorage = nil
        observations = []
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishWaiters()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishWaiters()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishWaiters()
        let message = (error as NSError).localizedDescription
        let page = "<html><body style='font:14px -apple-system;color:#9A9792;background:#0E0E0F;display:grid;place-items:center;height:90vh'><div>\(message)</div></body></html>"
        webView.loadHTMLString(page, baseURL: nil)
    }

    /// Links that open a new window load in this tab instead.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                             for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                             decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = DownloadSaver.shared
    }
}

/// Saves browser downloads to ~/Downloads.
final class DownloadSaver: NSObject, WKDownloadDelegate {
    static let shared = DownloadSaver()

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var target = downloads.appendingPathComponent(suggestedFilename)
        var counter = 2
        while FileManager.default.fileExists(atPath: target.path) {
            let base = (suggestedFilename as NSString).deletingPathExtension, ext = (suggestedFilename as NSString).pathExtension
            target = downloads.appendingPathComponent(ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)")
            counter += 1
        }
        return target
    }
}
