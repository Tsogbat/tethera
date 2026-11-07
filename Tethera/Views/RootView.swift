import SwiftUI
import TetheraKit

/// The window: sessions on the left, terminals in the middle, the inspector on the right.
struct RootView: View {
    @ObservedObject private var store = PreferencesStore.shared
    @ObservedObject private var client = DaemonClient.shared
    @ObservedObject private var workspace = Workspace.shared
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let theme = store.theme
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: store.value.sidebarWidth)
            Rectangle().fill(theme.hairline.color).frame(width: 1)
            VStack(spacing: 0) {
                TitleBar()
                PaneArea()
                StatusBar()
            }
            if store.value.showInspector {
                Rectangle().fill(theme.hairline.color).frame(width: 1)
                InspectorView()
                    .transition(.move(edge: .trailing))
            }
        }
        .background(theme.bg.color)
        .ignoresSafeArea()
        .environment(\.theme, theme)
        .preferredColorScheme(store.value.appearance == .system ? nil : (store.isDark ? .dark : .light))
        .overlay(alignment: .top) {
            if workspace.showPalette {
                ZStack(alignment: .top) {
                    Color.black.opacity(theme.isDark ? 0.35 : 0.12)
                        .ignoresSafeArea()
                        .onTapGesture { workspace.showPalette = false }
                    CommandPalette()
                        .environment(\.theme, theme)
                        .padding(.top, 90)
                }
            }
        }
        .overlay {
            if workspace.showOverview {
                ZStack {
                    Color.black.opacity(theme.isDark ? 0.4 : 0.15)
                        .ignoresSafeArea()
                        .onTapGesture { workspace.showOverview = false }
                    AgentsOverview()
                        .environment(\.theme, theme)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.hairline.color))
                        .shadow(color: .black.opacity(theme.isDark ? 0.5 : 0.15), radius: 24, y: 12)
                        .padding(60)
                }
                .onExitCommand { workspace.showOverview = false }
            }
        }
        .animation(.easeOut(duration: 0.16), value: store.value.showInspector)
        .onChange(of: client.sessions) { _, sessions in
            workspace.sessionsChanged()
            PreviewDetector.shared.sessionsChanged(sessions.map { .init(id: $0.id, running: $0.isCommandRunning) })
        }
        .onChange(of: client.hasLoaded) { _, _ in workspace.sessionsChanged() }
        .onChange(of: store.value) { _, _ in TerminalStore.shared.applyPreferences() }
        .onChange(of: systemScheme) { _, _ in TerminalStore.shared.applyPreferences() }
        .onChange(of: workspace.focusedPane) { _, _ in workspace.focusTerminalSoon() }
        .onAppear { SettingsOpener.action = { openSettings() } }
    }
}

/// Opens the Settings window from places that aren't views (palette, debug scripts).
@MainActor
enum SettingsOpener {
    static var action: (() -> Void)?

    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        action?()
    }
}
