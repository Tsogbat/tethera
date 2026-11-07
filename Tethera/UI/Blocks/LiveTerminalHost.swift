import SwiftUI
import AppKit

/// Hosts the tab's live emulator view. The emulator is owned by the view model, so it
/// survives SwiftUI re-creating this host (lazy lists, inline ↔ full-pane changes).
struct LiveTerminalHost: NSViewRepresentable {
    let live: LiveTerminal

    func makeNSView(context: Context) -> LiveTerminalContainer {
        let container = LiveTerminalContainer()
        container.attach(live.view)
        return container
    }

    func updateNSView(_ container: LiveTerminalContainer, context: Context) {
        container.attach(live.view)
    }
}

/// Clips the emulator to the rows in use and pins it to the top-left.
final class LiveTerminalContainer: NSView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(_ view: NSView) {
        if view.superview !== self {
            view.removeFromSuperview()
            addSubview(view)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        for subview in subviews {
            subview.setFrameOrigin(.zero)
        }
    }
}

/// Renders captured block output with the theme's ANSI palette.
struct StyledOutputView: View {
    @EnvironmentObject private var settings: UserSettings
    let block: TerminalBlock
    var lineLimit: Int?

    var body: some View {
        let attributed = OutputRenderCache.shared.attributed(for: block, palette: settings.theme.palette, lastLines: lineLimit)
        Text(attributed)
            .font(Typography.mono(settings.themeConfiguration.fontFamily, size: CGFloat(settings.themeConfiguration.fontSize)))
            .foregroundStyle(settings.theme.textPrimary.opacity(0.92))
            .lineSpacing(CGFloat(max(0, settings.themeConfiguration.lineSpacing - 1)) * CGFloat(settings.themeConfiguration.fontSize) * 0.6)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Building attributed strings for thousands of lines is expensive; do it once per version.
@MainActor
final class OutputRenderCache {
    static let shared = OutputRenderCache()

    private struct Key: Hashable {
        let id: UUID
        let version: Int
        let palette: TerminalPalette
        let lastLines: Int?
    }

    private var storage: [Key: AttributedString] = [:]
    private var order: [Key] = []
    private let capacity = 400

    func attributed(for block: TerminalBlock, palette: TerminalPalette, lastLines: Int?) -> AttributedString {
        let key = Key(id: block.id, version: block.outputVersion, palette: palette, lastLines: lastLines)
        if let cached = storage[key] { return cached }
        let styled = block.styledOutput ?? StyledText(plain: block.output)
        var range: Range<Int>?
        if let lastLines, styled.lineCount > lastLines {
            range = (styled.lineCount - lastLines)..<styled.lineCount
        }
        let value = styled.attributedString(palette: palette, lineRange: range)
        storage[key] = value
        order.append(key)
        if order.count > capacity {
            let evicted = order.removeFirst()
            storage.removeValue(forKey: evicted)
        }
        return value
    }
}
