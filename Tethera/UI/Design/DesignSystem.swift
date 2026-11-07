import SwiftUI
import AppKit

// MARK: - Semantic colors

/// Semantic colors derived from the active theme. Views use these instead of ad-hoc opacities.
struct DesignTheme: Equatable {
    let isDark: Bool
    let palette: TerminalPalette
    let background: Color
    let backgroundNS: NSColor
    let surface: Color
    let surfaceRaised: Color
    let hairline: Color
    let border: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let accent: Color
    let accentNS: NSColor
    let accentSoft: Color
    let success: Color
    let danger: Color
    let warning: Color
    let selection: Color

    init(_ config: ThemeConfiguration) {
        let palette = config.effectivePalette
        let fg = palette.foreground
        let bg = palette.background
        self.isDark = config.isDarkMode
        self.palette = palette
        self.background = bg.color
        self.backgroundNS = bg.nsColor
        self.surface = Self.mix(bg, fg, 0.035).color
        self.surfaceRaised = Self.mix(bg, fg, 0.07).color
        self.hairline = fg.color.opacity(config.isDarkMode ? 0.07 : 0.09)
        self.border = fg.color.opacity(config.isDarkMode ? 0.12 : 0.14)
        self.textPrimary = fg.color.opacity(0.95)
        self.textSecondary = fg.color.opacity(0.6)
        self.textTertiary = fg.color.opacity(0.38)
        self.accent = config.accentColor.color
        self.accentNS = config.accentColor.nsColor
        self.accentSoft = config.accentColor.color.opacity(config.isDarkMode ? 0.16 : 0.12)
        self.success = Self.mix(palette.green, fg, 0.12).color
        self.danger = Self.mix(palette.red, fg, 0.08).color
        self.warning = palette.yellow.color
        self.selection = config.accentColor.color.opacity(config.isDarkMode ? 0.09 : 0.08)
    }

    static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        func lerp(_ x: UInt8, _ y: UInt8) -> UInt8 {
            UInt8(clamping: Int((Double(x) + (Double(y) - Double(x)) * t).rounded()))
        }
        return RGB(lerp(a.r, b.r), lerp(a.g, b.g), lerp(a.b, b.b))
    }
}

// MARK: - Layout

enum Layout {
    static let paneGutter: CGFloat = 18
    static let blockInsetH: CGFloat = 14
    static let blockInsetV: CGFloat = 11
    static let blockSpacing: CGFloat = 2
    static let inputBarHeightEstimate: CGFloat = 92
    static let fullPaneHeader: CGFloat = 40
    static let trafficLightInset: CGFloat = 78
    static let tabBarHeight: CGFloat = 40
}

// MARK: - Typography

enum Typography {
    static func mono(_ family: String, size: CGFloat, weight: NSFont.Weight = .regular) -> Font {
        Font(TerminalFont.nsFont(family: family, size: size, weight: weight))
    }

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

enum TerminalFont {
    private static let postScriptNames: [String: (regular: String, medium: String, bold: String)] = [
        "JetBrains Mono": ("JetBrainsMono-Regular", "JetBrainsMono-Medium", "JetBrainsMono-Bold"),
        "Menlo": ("Menlo-Regular", "Menlo-Regular", "Menlo-Bold"),
        "Monaco": ("Monaco", "Monaco", "Monaco"),
        "Source Code Pro": ("SourceCodePro-Regular", "SourceCodePro-Medium", "SourceCodePro-Bold"),
        "Fira Code": ("FiraCode-Regular", "FiraCode-Medium", "FiraCode-Bold"),
    ]

    static func nsFont(family: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if family == "SF Mono" {
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
        if let names = postScriptNames[family] {
            let name = weight >= .bold ? names.bold : (weight >= .medium ? names.medium : names.regular)
            if let font = NSFont(name: name, size: size) { return font }
        }
        if let font = NSFontManager.shared.font(withFamily: family, traits: weight >= .bold ? .boldFontMask : [], weight: 5, size: size) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
}

// MARK: - Motion

enum Motion {
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.86)
    static let smooth = Animation.spring(response: 0.42, dampingFraction: 0.9)
    static let bouncy = Animation.spring(response: 0.36, dampingFraction: 0.7)
    static let quick = Animation.easeOut(duration: 0.14)
    static let fade = Animation.easeInOut(duration: 0.22)

    /// Picks a cross-fade when the user asked for reduced motion.
    static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : animation
    }
}

extension AnyTransition {
    /// Blocks rise into place.
    static var blockAppear: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(y: 10)).combined(with: .scale(scale: 0.985, anchor: .top)),
                    removal: .opacity)
    }

    static var popover: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .bottomLeading)),
                    removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .bottomLeading)))
    }

    static var overlay: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.97)),
                    removal: .opacity.combined(with: .scale(scale: 0.985)))
    }
}

// MARK: - Liquid Glass

/// Liquid Glass on macOS 26, a tuned material elsewhere.
struct GlassSurface<S: InsettableShape>: ViewModifier {
    @EnvironmentObject private var settings: UserSettings
    let shape: S
    var tint: Color?
    var interactive: Bool
    var elevated: Bool

    func body(content: Content) -> some View {
        let theme = settings.theme
        if #available(macOS 26.0, *) {
            content
                .glassEffect(glass(tint: tint), in: shape)
                .shadow(color: .black.opacity(elevated ? (theme.isDark ? 0.35 : 0.12) : 0), radius: elevated ? 18 : 0, y: elevated ? 8 : 0)
        } else {
            content
                .background {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        shape.fill(theme.background.opacity(theme.isDark ? 0.35 : 0.25))
                        if let tint { shape.fill(tint.opacity(0.08)) }
                    }
                }
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(theme.isDark ? 0.16 : 0.5), Color.white.opacity(theme.isDark ? 0.04 : 0.15)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.75)
                }
                .shadow(color: .black.opacity(elevated ? (theme.isDark ? 0.4 : 0.12) : 0), radius: elevated ? 18 : 0, y: elevated ? 8 : 0)
        }
    }

    @available(macOS 26.0, *)
    private func glass(tint: Color?) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint.opacity(0.18)) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

extension View {
    func glassSurface<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false, elevated: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, interactive: interactive, elevated: elevated))
    }

    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        glassSurface(Capsule(), tint: tint, interactive: interactive)
    }

    /// Groups glass shapes so they blend and morph together (macOS 26).
    @ViewBuilder
    func glassContainer(spacing: CGFloat = 8) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }

    func pointerCursor(_ cursor: NSCursor = .pointingHand) -> some View {
        onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Window background

/// Behind-window blur tinted with the theme background — the window's glass.
struct WindowBackdrop: NSViewRepresentable {
    var tint: NSColor
    var opacity: Double

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .underWindowBackground
        view.state = .followsWindowActiveState
        view.wantsLayer = true
        let overlay = CALayer()
        overlay.name = "tint"
        view.layer?.addSublayer(overlay)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        guard let overlay = view.layer?.sublayers?.first(where: { $0.name == "tint" }) else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        overlay.frame = view.bounds
        overlay.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        overlay.backgroundColor = tint.withAlphaComponent(opacity).cgColor
        CATransaction.commit()
    }
}

// MARK: - Small components

/// Pill used for metadata (cwd, branch, provider).
struct MetaChip: View {
    @EnvironmentObject private var settings: UserSettings
    let icon: String?
    let text: String
    var tint: Color? = nil
    var monospaced = true

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint ?? settings.theme.textSecondary)
            }
            Text(text)
                .font(monospaced ? Typography.mono(settings.themeConfiguration.fontFamily, size: 11, weight: .medium) : Typography.ui(11, weight: .medium))
                .foregroundStyle(settings.theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(settings.theme.surfaceRaised.opacity(0.7)))
        .overlay(Capsule().strokeBorder(settings.theme.hairline, lineWidth: 0.5))
    }
}

/// Small square icon button with hover feedback.
struct IconButton: View {
    @EnvironmentObject private var settings: UserSettings
    let systemName: String
    let help: String
    var tint: Color? = nil
    var size: CGFloat = 26
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(hovering ? (tint ?? settings.theme.textPrimary) : settings.theme.textSecondary)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hovering ? settings.theme.surfaceRaised : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }
}

/// Text button used in block toolbars and AI rows.
struct PillButton: View {
    @EnvironmentObject private var settings: UserSettings
    let title: String
    var systemImage: String? = nil
    var prominent = false
    var tint: Color? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let accent = tint ?? settings.theme.accent
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 10.5, weight: .semibold))
                }
                Text(title).font(Typography.ui(11.5, weight: .medium))
            }
            .foregroundStyle(prominent ? Color.white : (hovering ? settings.theme.textPrimary : settings.theme.textSecondary))
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(
                Capsule().fill(prominent ? accent.opacity(hovering ? 1 : 0.88) : (hovering ? settings.theme.surfaceRaised : settings.theme.surface))
            )
            .overlay(Capsule().strokeBorder(prominent ? .clear : settings.theme.hairline, lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }
}

/// Keyboard shortcut hint ("⌘K").
struct KeyHint: View {
    @EnvironmentObject private var settings: UserSettings
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text(keys)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(settings.theme.textSecondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(settings.theme.surfaceRaised))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(settings.theme.hairline, lineWidth: 0.5))
            Text(label)
                .font(Typography.ui(10.5))
                .foregroundStyle(settings.theme.textTertiary)
        }
    }
}

/// A gently pulsing dot (running / attention state).
struct PulsingDot: View {
    let color: Color
    var size: CGFloat = 7
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(color.opacity(0.45))
                    .scaleEffect(pulse ? 2.3 : 1)
                    .opacity(pulse ? 0 : 0.8)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) { pulse = true }
            }
    }
}

/// Indeterminate shimmer used on running block rails and AI "thinking" borders.
struct ShimmerBar: View {
    let color: Color
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle().fill(color.opacity(0.25))
                if !reduceMotion {
                    LinearGradient(colors: [.clear, color, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: max(24, proxy.size.height * 0.6))
                        .offset(y: phase * proxy.size.height)
                }
            }
            .clipped()
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
        }
    }
}

/// Rotating angular gradient stroke — the AI "thinking" outline.
struct ThinkingBorder<S: InsettableShape>: View {
    let shape: S
    var colors: [Color]
    var lineWidth: CGFloat = 1.2
    @State private var angle: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        shape
            .strokeBorder(
                AngularGradient(colors: colors + [colors.first ?? .clear], center: .center, angle: .degrees(angle)),
                lineWidth: lineWidth
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) { angle = 360 }
            }
    }
}

/// The ✦ glyph that marks AI features, with a soft twinkle while active.
struct SparkleIcon: View {
    var active = false
    var size: CGFloat = 12
    var color: Color
    @State private var twinkle = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .scaleEffect(active && twinkle ? 1.18 : 1)
            .rotationEffect(.degrees(active && twinkle ? 18 : 0))
            .opacity(active && twinkle ? 0.75 : 1)
            .onAppear(perform: start)
            .onChange(of: active) { _, _ in start() }
    }

    private func start() {
        guard active, !reduceMotion else { twinkle = false; return }
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { twinkle = true }
    }
}

/// The AI accent gradient (cyan → violet), shared with the app icon.
enum BrandGradient {
    static let colors: [Color] = [Color(red: 0.43, green: 0.90, blue: 1.0), Color(red: 0.48, green: 0.36, blue: 1.0)]
    static var linear: LinearGradient {
        LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
}
