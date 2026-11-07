import SwiftUI

/// One terminal pane: the block list with a floating command bar, or a full-pane live
/// program (TUIs and agents).
struct TerminalPaneView: View {
    @EnvironmentObject private var settings: UserSettings
    @ObservedObject var viewModel: BlockTerminalViewModel
    let isActivePane: Bool

    @Namespace private var liveNamespace
    @State private var inputBarHeight: CGFloat = Layout.inputBarHeightEstimate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsFullPane: Bool {
        viewModel.presentation == .fullPane && viewModel.isRunning
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                if showsFullPane {
                    FullPaneTerminalView(viewModel: viewModel, liveNamespace: liveNamespace)
                        .transition(.opacity)
                } else {
                    BlockListView(viewModel: viewModel, live: viewModel.live, liveNamespace: liveNamespace,
                                  bottomInset: inputBarHeight + 22)
                        .transition(.opacity)

                    InputBarView(viewModel: viewModel, isActivePane: isActivePane)
                        .background(
                            GeometryReader { bar in
                                Color.clear
                                    .onAppear { inputBarHeight = bar.size.height }
                                    .onChange(of: bar.size.height) { _, height in inputBarHeight = height }
                            }
                        )
                        .padding(.horizontal, Layout.paneGutter - 4)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Motion.adaptive(Motion.snappy, reduceMotion: reduceMotion), value: showsFullPane)
            .onAppear { viewModel.updatePaneSize(proxy.size) }
            .onChange(of: proxy.size) { _, size in viewModel.updatePaneSize(size) }
        }
        .onChange(of: viewModel.focusTerminalToken) { _, _ in
            guard isActivePane else { return }
            DispatchQueue.main.async { viewModel.live.focus() }
        }
    }
}

// MARK: - Block list

struct BlockListView: View {
    @EnvironmentObject private var settings: UserSettings
    @ObservedObject var viewModel: BlockTerminalViewModel
    @ObservedObject var live: LiveTerminal
    let liveNamespace: Namespace.ID
    let bottomInset: CGFloat

    /// Follow new output until the user scrolls up; content growing below doesn't count.
    @State private var follows = true
    private static let bottomAnchor = "tethera.bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                blockStack
            }
            .scrollIndicators(.automatic)
            .modifier(FollowTracker(follows: $follows))
            .onChange(of: viewModel.scrollRequest) { _, request in
                if let request { handle(request, proxy: proxy) }
            }
            .onChange(of: live.contentRows) { _, _ in
                guard follows, viewModel.isRunning else { return }
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
            .onChange(of: viewModel.blocks.last?.outputVersion) { _, _ in
                guard follows else { return }
                DispatchQueue.main.async { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
            }
            .overlay(alignment: .bottom) {
                if !follows && !viewModel.blocks.isEmpty {
                    jumpButton(proxy: proxy)
                }
            }
            .animation(Motion.snappy, value: follows)
        }
    }

    private var blockStack: some View {
        LazyVStack(alignment: .leading, spacing: Layout.blockSpacing) {
            if viewModel.blocks.isEmpty {
                WelcomeView(viewModel: viewModel)
                    .padding(.top, 70)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
            ForEach(Array(viewModel.blocks.enumerated()), id: \.element.id) { index, block in
                VStack(spacing: 0) {
                    if index > 0 && block.kind == .command && viewModel.blocks[index - 1].kind == .command {
                        Rectangle()
                            .fill(settings.theme.hairline)
                            .frame(height: 0.5)
                            .padding(.horizontal, Layout.blockInsetH)
                    }
                    BlockView(block: block, viewModel: viewModel,
                              isSelected: viewModel.selectedBlockID == block.id,
                              liveNamespace: liveNamespace)
                }
                .id(block.id)
                .transition(.blockAppear)
            }
            // The anchor is the space under the floating input bar, so scrolling to it
            // leaves the last block above the bar instead of beneath it.
            Color.clear
                .frame(height: bottomInset)
                .id(Self.bottomAnchor)
        }
        .padding(.horizontal, Layout.paneGutter)
        .padding(.top, 10)
    }

    private func handle(_ request: ScrollRequest, proxy: ScrollViewProxy) {
        let toLatest = request.anchor == .bottom && viewModel.blocks.last?.id == request.id
        if toLatest { follows = true }
        // Wait one layout pass so a block that was just inserted has its height.
        DispatchQueue.main.async {
            withAnimation(Motion.smooth) {
                switch request.anchor {
                case .bottom:
                    if toLatest {
                        proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                    } else {
                        proxy.scrollTo(request.id, anchor: .bottom)
                    }
                case .center:
                    proxy.scrollTo(request.id, anchor: .center)
                }
            }
        }
    }

    private func jumpButton(proxy: ScrollViewProxy) -> some View {
        Button {
            follows = true
            withAnimation(Motion.smooth) { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down").font(.system(size: 10, weight: .bold))
                Text(viewModel.isRunning ? "Follow output" : "Jump to latest")
                    .font(Typography.ui(11.5, weight: .medium))
            }
            .foregroundStyle(settings.theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassCapsule(interactive: true)
        }
        .buttonStyle(.plain)
        .padding(.bottom, bottomInset - 8)
        .transition(.opacity.combined(with: .offset(y: 8)))
    }
}

/// Turns following off when the user scrolls up and back on when they reach the end
/// (macOS 15+; earlier systems always follow). Only gestures count: lazy rows re-measuring
/// also move the offset, and that must not stop following.
struct FollowTracker: ViewModifier {
    @Binding var follows: Bool
    @State private var userScrolling = false

    private struct Position: Equatable {
        var offset: CGFloat
        var atBottom: Bool
    }

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .onScrollPhaseChange { _, phase in
                    userScrolling = phase == .interacting || phase == .decelerating || phase == .tracking
                }
                .onScrollGeometryChange(for: Position.self) { geometry in
                    Position(offset: geometry.contentOffset.y,
                             atBottom: geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 40)
                } action: { old, new in
                    if new.atBottom {
                        if !follows { follows = true }
                    } else if userScrolling, new.offset < old.offset - 1, follows {
                        follows = false
                    }
                }
        } else {
            content
        }
    }
}

// MARK: - Full pane

struct FullPaneTerminalView: View {
    @EnvironmentObject private var settings: UserSettings
    @ObservedObject var viewModel: BlockTerminalViewModel
    let liveNamespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let agent = viewModel.runningAgent {
                    AgentBadge(agent: agent, size: 20)
                    Text(agent.displayName)
                        .font(Typography.ui(12.5, weight: .semibold))
                        .foregroundStyle(settings.theme.textPrimary)
                } else {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(settings.theme.accent)
                }
                Text(viewModel.runningBlock?.input ?? "")
                    .font(Typography.mono(settings.themeConfiguration.fontFamily, size: 12, weight: .medium))
                    .foregroundStyle(settings.theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let block = viewModel.runningBlock {
                    RunningClock(start: block.timestamp)
                        .font(Typography.mono(settings.themeConfiguration.fontFamily, size: 11))
                        .foregroundStyle(settings.theme.textTertiary)
                }
                Spacer(minLength: 12)
                KeyHint(keys: "⌃C", label: "interrupt")
                IconButton(systemName: "arrow.down.right.and.arrow.up.left", help: "Show inline with blocks") {
                    viewModel.togglePresentation()
                }
                PillButton(title: "Stop", systemImage: "stop.fill", tint: settings.theme.danger) { viewModel.stopRunning() }
            }
            .padding(.horizontal, Layout.paneGutter + Layout.blockInsetH - 6)
            .frame(height: Layout.fullPaneHeader)
            .background(
                Rectangle().fill(settings.theme.surface.opacity(0.6))
                    .overlay(alignment: .bottom) { Rectangle().fill(settings.theme.hairline).frame(height: 0.5) }
            )

            LiveTerminalHost(live: viewModel.live)
                .matchedGeometryEffect(id: "live", in: liveNamespace)
                .padding(.horizontal, Layout.paneGutter + Layout.blockInsetH)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture { viewModel.live.focus() }
        }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @EnvironmentObject private var settings: UserSettings
    @ObservedObject var viewModel: BlockTerminalViewModel
    @ObservedObject private var detector = AgentDetector.shared
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 22) {
            TetheraMark(size: 76)
                .shadow(color: Color(red: 0.48, green: 0.36, blue: 1).opacity(0.35), radius: 24, y: 10)
                .scaleEffect(appeared ? 1 : 0.92)
                .opacity(appeared ? 1 : 0)

            VStack(spacing: 6) {
                Text("Tethera")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(settings.theme.textPrimary)
                Text("Blocks for every command. AI from the CLIs you already use.")
                    .font(Typography.ui(13))
                    .foregroundStyle(settings.theme.textSecondary)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)

            VStack(alignment: .leading, spacing: 9) {
                WelcomeHint(keys: "↩", text: "Run a command")
                WelcomeHint(keys: "#", text: "Describe a command in plain English")
                WelcomeHint(keys: "?", text: "Ask \(settings.aiSettings.provider.displayName) about your session")
                WelcomeHint(keys: "⌘P", text: "Command palette")
                WelcomeHint(keys: "⌘D", text: "Split the pane")
            }
            .padding(16)
            .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)

            let installed = AgentCLI.allCases.filter { detector.status(for: $0)?.isInstalled ?? false && $0 != .ollama }
            if !installed.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(installed.enumerated()), id: \.element.id) { index, agent in
                        AgentLaunchButton(agent: agent) { viewModel.launchAgent(agent) }
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 8)
                            .animation(Motion.smooth.delay(0.18 + Double(index) * 0.04), value: appeared)
                    }
                }
                .glassContainer(spacing: 8)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(Motion.smooth.delay(0.05)) { appeared = true }
        }
    }
}

private struct WelcomeHint: View {
    @EnvironmentObject private var settings: UserSettings
    let keys: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(settings.theme.textPrimary)
                .frame(minWidth: 30, minHeight: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(settings.theme.surfaceRaised))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(settings.theme.hairline, lineWidth: 0.5))
            Text(text)
                .font(Typography.ui(12.5))
                .foregroundStyle(settings.theme.textSecondary)
        }
    }
}

struct AgentLaunchButton: View {
    @EnvironmentObject private var settings: UserSettings
    let agent: AgentCLI
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                AgentBadge(agent: agent, size: 20)
                Text(agent.displayName)
                    .font(Typography.ui(12, weight: .medium))
                    .foregroundStyle(settings.theme.textPrimary)
            }
            .padding(.leading, 5)
            .padding(.trailing, 12)
            .padding(.vertical, 5)
            .glassCapsule(tint: hovering ? agent.tint : nil, interactive: true)
            .scaleEffect(hovering ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(Motion.snappy) { hovering = inside } }
        .help("Open \(agent.displayName) in this tab")
    }
}

/// The app mark, drawn from the bundled icon.
struct TetheraMark: View {
    var size: CGFloat

    var body: some View {
        Group {
            if let image = BrandAssets.appIcon {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(LinearGradient(colors: BrandGradient.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .frame(width: size, height: size)
    }
}

enum BrandAssets {
    static let appIcon: NSImage? = {
        guard let url = Bundle.tethera.url(forResource: "AppIcon", withExtension: "png", subdirectory: "Brand") else { return nil }
        return NSImage(contentsOf: url)
    }()
}
