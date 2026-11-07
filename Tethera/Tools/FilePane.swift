import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// How a file opens: text in the editor, the rest in a viewer.
enum FileKind: Equatable {
    case text, markdown, image, pdf, media, other

    /// Files bigger than this open read-only.
    static let editableLimit = 5 * 1024 * 1024

    static func of(_ path: String) -> FileKind {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        if ["md", "markdown", "mdx"].contains(ext) { return .markdown }
        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .pdf) { return .pdf }
            if type.conforms(to: .image) && ext != "svg" { return .image }
            if type.conforms(to: .audiovisualContent) { return .media }
            if type.conforms(to: .text) || type.conforms(to: .sourceCode) || type.conforms(to: .json) || type.conforms(to: .xml) { return .text }
        }
        // Dotfiles, Makefiles, unknown extensions: text if it looks like text.
        return looksLikeText(path) ? .text : .other
    }

    /// No NUL bytes and valid UTF-8 in the first 8 KB.
    static func looksLikeText(_ path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 8_192)) ?? Data()
        if head.isEmpty { return true }
        if head.contains(0) { return false }
        // A multi-byte character may be cut at the end; trim up to 3 bytes before judging.
        for trim in 0...3 where head.count > trim {
            if String(data: head.dropLast(trim), encoding: .utf8) != nil { return true }
        }
        return false
    }
}

/// A file pane: a slim header (name, folder, state, actions) and the editor or viewer.
struct FilePane: View {
    let path: String
    let paneID: UUID
    @ObservedObject private var workspace = Workspace.shared
    @Environment(\.theme) private var theme
    @State private var kind: FileKind
    @State private var showSource = false
    @StateObject private var document = EditorDocument()

    init(path: String, paneID: UUID) {
        self.path = path
        self.paneID = paneID
        // Decided up front: a viewer created for the wrong kind and torn down at once is wasteful
        // (and Quick Look objects to it).
        _kind = State(initialValue: FileKind.of(path))
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(paneID: paneID, icon: icon, title: (path as NSString).lastPathComponent,
                       detail: HomeView.abbreviate((path as NSString).deletingLastPathComponent),
                       dirty: document.isDirty) {
                if kind == .markdown {
                    IconButton(systemName: showSource ? "doc.richtext" : "chevron.left.forwardslash.chevron.right",
                               help: showSource ? "Show rendered" : "Edit source") { showSource.toggle() }
                }
                IconButton(systemName: "arrow.up.forward.app", help: "Open with default app") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                }
                IconButton(systemName: "folder", help: "Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }
            content
        }
        .onAppear { open(path) }
        .onChange(of: path) { _, new in open(new) }
    }

    private func open(_ path: String) {
        kind = FileKind.of(path)
        if kind == .text || kind == .markdown { document.load(path) }
    }

    private var icon: String {
        switch kind {
        case .text: return "doc.text"
        case .markdown: return "doc.richtext"
        case .image: return "photo"
        case .pdf: return "doc.viewfinder"
        case .media: return "play.rectangle"
        case .other: return "doc"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .text: EditorPane(document: document, paneID: paneID)
        case .markdown:
            if showSource { EditorPane(document: document, paneID: paneID) } else { MarkdownViewer(path: path, revision: document.revision) }
        case .image: ImageViewer(path: path)
        case .pdf: PDFViewer(path: path)
        case .media: MediaViewer(path: path)
        case .other: QuickLookViewer(path: path)
        }
    }
}

/// The header every tool pane shares: what it is, plus its own actions and close.
struct ToolHeader<Actions: View>: View {
    let paneID: UUID
    let icon: String
    let title: String
    var detail: String?
    var dirty = false
    @ViewBuilder var actions: Actions
    @ObservedObject private var workspace = Workspace.shared
    @Environment(\.theme) private var theme

    private var isFocused: Bool { workspace.focusedPane == paneID }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.text2.color)
            Text(title)
                .font(TypeScale.ui(12, .semibold))
                .foregroundStyle(theme.text.color)
                .lineLimit(1)
            if dirty {
                Circle().fill(theme.text2.color).frame(width: 6, height: 6).help("Unsaved changes")
            }
            if let detail {
                Text(detail)
                    .font(TypeScale.ui(11))
                    .foregroundStyle(theme.text3.color)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 8)
            actions
            IconButton(systemName: "xmark", help: "Close (⌘W)") {
                workspace.focus(pane: paneID)
                workspace.closeFocusedPane()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(theme.surface.color)
        .overlay(alignment: .top) {
            Rectangle().fill(isFocused && workspace.panes.count > 1 ? theme.accent.color.opacity(0.6) : .clear).frame(height: 1)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline.color).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { workspace.focus(pane: paneID) }
    }
}
