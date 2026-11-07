import AppKit
import SwiftUI
import WebKit

/// A browser tab in a pane: back, forward, reload, an address field, and a quiet marker while
/// an agent is driving it.
struct BrowserPane: View {
    let tabID: UUID
    let paneID: UUID
    @ObservedObject private var store = BrowserStore.shared

    var body: some View {
        if let tab = store.tab(tabID) {
            BrowserTabView(tab: tab, paneID: paneID)
        } else {
            Color.clear
        }
    }
}

private struct BrowserTabView: View {
    @ObservedObject var tab: BrowserTab
    let paneID: UUID
    @ObservedObject private var workspace = Workspace.shared
    @Environment(\.theme) private var theme
    @State private var address = ""
    @FocusState private var addressFocused: Bool

    private var isFocused: Bool { workspace.focusedPane == paneID }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                IconButton(systemName: "chevron.left", help: "Back") { tab.webView.goBack() }
                    .disabled(!tab.canGoBack)
                    .opacity(tab.canGoBack ? 1 : 0.35)
                IconButton(systemName: "chevron.right", help: "Forward") { tab.webView.goForward() }
                    .disabled(!tab.canGoForward)
                    .opacity(tab.canGoForward ? 1 : 0.35)
                IconButton(systemName: tab.isLoading ? "xmark" : "arrow.clockwise", help: tab.isLoading ? "Stop" : "Reload") {
                    if tab.isLoading { tab.webView.stopLoading() } else { tab.webView.reload() }
                }
                TextField("Search or enter address", text: $address)
                    .textFieldStyle(.plain)
                    .font(TypeScale.ui(12))
                    .foregroundStyle(theme.text.color)
                    .focused($addressFocused)
                    .onSubmit {
                        if let url = BrowserTab.resolve(address) { tab.load(url) }
                        addressFocused = false
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: Metrics.controlRadius).fill(theme.bg.color))
                    .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius).strokeBorder(theme.hairline.color))
                    .padding(.horizontal, 4)
                if tab.agentDriving {
                    HStack(spacing: 5) {
                        WorkingSpinner(color: theme.text2.color)
                        Text("agent").font(TypeScale.ui(11, .semibold)).foregroundStyle(theme.accent.color)
                    }
                    .help("An agent is using this tab")
                }
                if tab.isPreview {
                    Text("preview").font(TypeScale.ui(11)).foregroundStyle(theme.text3.color)
                }
                IconButton(systemName: "safari", help: "Open in your browser") {
                    if let url = tab.url { NSWorkspace.shared.open(url) }
                }
                IconButton(systemName: "xmark", help: "Close tab (⌘W)") {
                    workspace.focus(pane: paneID)
                    workspace.closeFocusedPane()
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(theme.surface.color)
            .overlay(alignment: .top) {
                Rectangle().fill(isFocused && workspace.panes.count > 1 ? theme.accent.color.opacity(0.6) : .clear).frame(height: 1)
            }
            .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline.color).frame(height: 1) }
            WebViewHost(tab: tab, paneID: paneID)
        }
        .onAppear {
            address = tab.url?.absoluteString ?? ""
            if tab.url == nil { addressFocused = true }
        }
        .onChange(of: tab.url) { _, url in
            if !addressFocused { address = url?.absoluteString ?? "" }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusAddressBar)) { note in
            if (note.object as? UUID) == paneID { addressFocused = true }
        }
    }
}

extension Notification.Name {
    static let focusAddressBar = Notification.Name("tethera.focusAddressBar")
}

private struct WebViewHost: NSViewRepresentable {
    let tab: BrowserTab
    let paneID: UUID

    func makeNSView(context: Context) -> TerminalSlot { TerminalSlot() }

    func updateNSView(_ slot: TerminalSlot, context: Context) {
        slot.show(tab.webView)
    }
}
