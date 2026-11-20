import AppKit
import SwiftUI

/// The rest of a suggested command, drawn dimmed right after the cursor.
final class GhostTextView: NSView {
    var text = "" { didSet { needsDisplay = true } }
    var font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular) { didSet { needsDisplay = true } }
    var color: NSColor = .secondaryLabelColor { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        // Centered in the cell, as the terminal's own text is.
        let height = font.ascender - font.descender + font.leading
        (text as NSString).draw(at: NSPoint(x: 0, y: (bounds.height - height) / 2), withAttributes: attributes)
    }
}

/// The ⌃Space list: candidates for the word being typed, drawn over the terminal just below
/// the cursor (above it near the bottom). Keys reach it through the terminal's key handling.
@MainActor
final class CompletionPopup {
    private var host: NSHostingView<AnyView>?
    private(set) var items: [CompletionEngine.Candidate] = []
    private(set) var word = ""
    private(set) var selection = 0
    private let model = Model()

    @MainActor
    final class Model: ObservableObject {
        @Published var items: [CompletionEngine.Candidate] = []
        @Published var selection = 0
    }

    var isVisible: Bool { host?.isHidden == false && !items.isEmpty }
    var selected: CompletionEngine.Candidate? { items.indices.contains(selection) ? items[selection] : nil }

    func show(_ items: [CompletionEngine.Candidate], word: String, at caret: NSRect, in view: NSView, theme: Theme, font: NSFont) {
        guard !items.isEmpty else { return hide() }
        self.items = items
        self.word = word
        selection = 0
        model.items = items
        model.selection = 0
        let host = self.host ?? NSHostingView(rootView: AnyView(CompletionList(model: model, font: font).environment(\.theme, theme)))
        if host.superview !== view {
            host.removeFromSuperview()
            view.addSubview(host)
        }
        self.host = host
        let size = NSSize(width: min(380, view.bounds.width - 16), height: CGFloat(min(items.count, 9)) * 26 + 10)
        // The container isn't flipped: y grows upward, so "below the caret" is a smaller y.
        var origin = NSPoint(x: min(max(8, caret.minX - 8), view.bounds.width - size.width - 8), y: caret.minY - size.height - 2)
        if origin.y < 4 { origin.y = caret.maxY + 2 }
        host.frame = NSRect(origin: origin, size: size)
        host.isHidden = false
    }

    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        selection = (selection + delta + items.count) % items.count
        model.selection = selection
    }

    func hide() {
        host?.isHidden = true
        items = []
    }
}

private struct CompletionList: View {
    @ObservedObject var model: CompletionPopup.Model
    let font: NSFont
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(model.items.enumerated()), id: \.offset) { index, item in
                        let selected = index == model.selection
                        HStack(spacing: 10) {
                            Image(systemName: icon(item.kind))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(selected ? theme.bg.color.opacity(0.8) : theme.text3.color)
                                .frame(width: 14)
                            Text(item.text)
                                .font(Font(font).weight(.medium))
                                .foregroundStyle(selected ? theme.bg.color : theme.text.color)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if let detail = item.detail {
                                Text(detail)
                                    .font(TypeScale.ui(11))
                                    .foregroundStyle(selected ? theme.bg.color.opacity(0.75) : theme.text3.color)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 5).fill(selected ? theme.text.color : .clear))
                        .id(index)
                    }
                }
                .padding(5)
            }
            .onChange(of: model.selection) { _, index in proxy.scrollTo(index) }
        }
        .background(RoundedRectangle(cornerRadius: 9).fill(theme.raised.color))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.hairline.color))
    }

    private func icon(_ kind: CompletionEngine.Candidate.Kind) -> String {
        switch kind {
        case .command: return "terminal"
        case .subcommand: return "arrow.turn.down.right"
        case .flag: return "flag"
        case .path: return "doc"
        case .folder: return "folder"
        case .branch: return "arrow.triangle.branch"
        case .script: return "play"
        case .history: return "clock.arrow.circlepath"
        }
    }
}
