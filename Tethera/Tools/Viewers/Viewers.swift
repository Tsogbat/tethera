import AppKit
import AVKit
import PDFKit
import Quartz
import SwiftUI

// MARK: - Images

/// An image: fits the pane, ⌘-scroll or pinch to zoom, double-click for 1:1. Transparency shows
/// over a quiet checkerboard.
struct ImageViewer: NSViewRepresentable {
    let path: String
    @Environment(\.theme) private var theme

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.05
        scroll.maxMagnification = 16
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        let imageView = CheckeredImageView()
        scroll.documentView = imageView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        scroll.backgroundColor = theme.bg.nsColor
        guard let imageView = scroll.documentView as? CheckeredImageView else { return }
        imageView.dark = theme.isDark
        if imageView.path != path {
            imageView.path = path
            imageView.image = NSImage(contentsOfFile: path)
            DispatchQueue.main.async { imageView.fit(in: scroll) }
        }
    }
}

final class CheckeredImageView: NSView {
    var path = ""
    var dark = true
    var image: NSImage? {
        didSet {
            let size = image.map { rep in
                rep.representations.first.map { NSSize(width: $0.pixelsWide, height: $0.pixelsHigh) } ?? rep.size
            } ?? .zero
            setFrameSize(size)
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    func fit(in scroll: NSScrollView) {
        guard frame.width > 0, frame.height > 0 else { return }
        let available = scroll.contentSize
        let scale = min(1, min(available.width / frame.width, available.height / frame.height))
        scroll.magnification = max(scroll.minMagnification, scale)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 2, let scroll = enclosingScrollView else { return }
        if abs(scroll.magnification - 1) < 0.01 { fit(in: scroll) } else { scroll.magnification = 1 }
    }

    override func draw(_ dirtyRect: NSRect) {
        let light = NSColor(white: dark ? 0.2 : 0.95, alpha: 1), darker = NSColor(white: dark ? 0.16 : 0.88, alpha: 1)
        let tile: CGFloat = 10
        light.setFill()
        bounds.fill()
        darker.setFill()
        var y: CGFloat = 0
        while y < bounds.height {
            var x: CGFloat = (Int(y / tile) % 2 == 0) ? 0 : tile
            while x < bounds.width {
                NSRect(x: x, y: y, width: tile, height: tile).fill()
                x += tile * 2
            }
            y += tile
        }
        image?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
    }
}

// MARK: - PDF

struct PDFViewer: NSViewRepresentable {
    let path: String
    @Environment(\.theme) private var theme

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        view.backgroundColor = theme.bg.nsColor
        if view.document?.documentURL?.path != path {
            view.document = PDFDocument(url: URL(fileURLWithPath: path))
        }
    }
}

// MARK: - Video and audio

struct MediaViewer: NSViewRepresentable {
    let path: String

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        let url = URL(fileURLWithPath: path)
        if (view.player?.currentItem?.asset as? AVURLAsset)?.url != url {
            view.player = AVPlayer(url: url)
        }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}

// MARK: - Everything else

struct QuickLookViewer: NSViewRepresentable {
    let path: String

    func makeNSView(context: Context) -> QLPreviewView {
        QLPreviewView(frame: .zero, style: .normal)!
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        let url = URL(fileURLWithPath: path) as NSURL
        if (view.previewItem as? NSURL) != url { view.previewItem = url }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        // `close()` asserts if the preview never activated; letting go of the item is enough.
        view.previewItem = nil
    }
}

// MARK: - Markdown

/// Rendered Markdown: headings, lists, quotes and code in the app's type, selectable.
struct MarkdownViewer: NSViewRepresentable {
    let path: String
    /// Changes when the file reloads.
    let revision: Int
    @Environment(\.theme) private var theme

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        if let textView = scroll.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.textContainerInset = NSSize(width: 28, height: 24)
            textView.drawsBackground = true
        }
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        textView.backgroundColor = theme.bg.nsColor
        scroll.backgroundColor = theme.bg.nsColor
        let source = MarkdownRenderer.strippingHTML((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
        textView.textStorage?.setAttributedString(MarkdownRenderer.render(source, theme: theme,
                                                                          mono: PreferencesStore.shared.terminalFont))
    }
}

enum MarkdownRenderer {
    /// READMEs often wrap a logo or badges in HTML; keep the words, drop the tags.
    static func strippingHTML(_ source: String) -> String {
        var inFence = false
        var lines: [String] = []
        for line in source.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inFence.toggle() }
            guard !inFence else { lines.append(line); continue }
            var cleaned = line.replacingOccurrences(of: "<br\\s*/?>", with: "  ", options: [.regularExpression, .caseInsensitive])
            cleaned = cleaned.replacingOccurrences(of: "<!--.*?-->", with: "", options: .regularExpression)
            cleaned = cleaned.replacingOccurrences(of: "</?[A-Za-z][^>]*>", with: "", options: .regularExpression)
            // A line that was only tags disappears instead of leaving a blank paragraph.
            if cleaned.trimmingCharacters(in: .whitespaces).isEmpty && !line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            lines.append(cleaned.trimmingCharacters(in: .whitespaces).isEmpty ? cleaned : cleaned)
        }
        return lines.joined(separator: "\n")
    }

    static func render(_ source: String, theme: Theme, mono: NSFont) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: source, options: options) else {
            return NSAttributedString(string: source, attributes: [.font: mono, .foregroundColor: theme.text.nsColor])
        }
        let output = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: 14)
        let codeFont = NSFont(descriptor: mono.fontDescriptor, size: 12.5) ?? mono
        var lastBlock: Int?
        var lastRow: Int?
        let tableStyle = NSMutableParagraphStyle()
        tableStyle.tabStops = (1...8).map { NSTextTab(textAlignment: .left, location: CGFloat($0) * 190) }
        tableStyle.defaultTabInterval = 190
        tableStyle.paragraphSpacing = 4

        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            let intent = run.presentationIntent
            let components = intent?.components ?? []
            let blockID = components.first?.identity
            let row = components.first { if case .tableRow = $0.kind { return true }; if case .tableHeaderRow = $0.kind { return true }; return false }?.identity
            let isHeaderRow = components.contains { if case .tableHeaderRow = $0.kind { return true }; return false }

            // A new block starts a new paragraph, with a list marker or quote bar as needed;
            // table cells in the same row are separated by tabs instead.
            if blockID != lastBlock {
                let sameRow = row != nil && row == lastRow
                if output.length > 0 { output.append(NSAttributedString(string: sameRow ? "\t" : "\n")) }
                lastBlock = blockID
                lastRow = row
                for component in components.reversed() {
                    if case .listItem(let ordinal) = component.kind {
                        let ordered = components.contains { if case .orderedList = $0.kind { return true } else { return false } }
                        let marker = ordered ? "\(ordinal). " : "•  "
                        output.append(NSAttributedString(string: marker, attributes: [.font: body, .foregroundColor: theme.text2.nsColor]))
                    }
                }
            }

            var font = body
            var color = theme.text.nsColor
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = 10
            paragraph.lineSpacing = 3
            var background: NSColor?

            for component in components {
                switch component.kind {
                case .header(let level):
                    let sizes: [CGFloat] = [26, 21, 17, 15, 14, 13]
                    font = NSFont.systemFont(ofSize: sizes[min(level, 6) - 1], weight: level <= 2 ? .bold : .semibold)
                    paragraph.paragraphSpacingBefore = level <= 2 ? 14 : 8
                case .codeBlock:
                    font = codeFont
                    background = theme.surface.nsColor
                    paragraph.paragraphSpacing = 2
                    paragraph.headIndent = 12
                    paragraph.firstLineHeadIndent = 12
                case .blockQuote:
                    color = theme.text2.nsColor
                    paragraph.headIndent = 16
                    paragraph.firstLineHeadIndent = 16
                case .listItem:
                    paragraph.headIndent = 22
                    paragraph.paragraphSpacing = 4
                case .thematicBreak:
                    color = theme.text3.nsColor
                default:
                    break
                }
            }

            if let inline = run.inlinePresentationIntent {
                if inline.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                if inline.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                if inline.contains(.code) {
                    font = codeFont
                    background = theme.raised.nsColor
                }
            }

            if row != nil {
                font = isHeaderRow ? NSFont.systemFont(ofSize: 12.5, weight: .semibold) : NSFont.systemFont(ofSize: 12.5)
                if isHeaderRow { color = theme.text2.nsColor }
            }
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: row != nil ? tableStyle : paragraph]
            if let background { attributes[.backgroundColor] = background }
            if let link = run.link {
                attributes[.link] = link
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attributes[.underlineColor] = theme.text3.nsColor
            }
            output.append(NSAttributedString(string: text, attributes: attributes))
        }
        return output
    }
}
