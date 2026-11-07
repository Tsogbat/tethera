import AppKit
import Foundation

/// A text file open in the editor. Watches the file, because agents edit files while you
/// look at them: a clean buffer reloads by itself; a dirty one asks.
@MainActor
final class EditorDocument: ObservableObject {
    enum Conflict: Equatable {
        case changedOnDisk
        case deleted
    }

    @Published private(set) var path = ""
    @Published private(set) var isDirty = false
    @Published private(set) var isReadOnly = false
    @Published private(set) var conflict: Conflict?
    @Published private(set) var error: String?
    /// Bumps whenever the text is replaced from disk, so views reload.
    @Published private(set) var revision = 0

    private(set) var text = ""
    private var savedText = ""
    private var watcher: DispatchSourceFileSystemObject?
    private var ignoreEventsUntil = Date.distantPast

    func load(_ path: String) {
        guard path != self.path else { return }
        self.path = path
        reloadFromDisk()
        watch()
    }

    /// The editor calls this on every edit.
    func edited(_ newText: String) {
        text = newText
        let dirty = newText != savedText
        if dirty != isDirty { isDirty = dirty }
    }

    func reloadFromDisk() {
        error = nil
        conflict = nil
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        isReadOnly = size > FileKind.editableLimit || !FileManager.default.isWritableFile(atPath: path)
        guard let data = FileManager.default.contents(atPath: path) else {
            error = "Couldn't read \((path as NSString).lastPathComponent)."
            return
        }
        let loaded = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        text = loaded
        savedText = loaded
        isDirty = false
        revision += 1
    }

    /// Writes atomically and keeps the file's permissions.
    @discardableResult
    func save() -> Bool {
        guard !isReadOnly else { return false }
        let url = URL(fileURLWithPath: path)
        let permissions = (try? FileManager.default.attributesOfItem(atPath: path))?[.posixPermissions]
        do {
            ignoreEventsUntil = Date().addingTimeInterval(0.6)
            try Data(text.utf8).write(to: url, options: .atomic)
            if let permissions { try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: path) }
            savedText = text
            isDirty = false
            conflict = nil
            watch()
            return true
        } catch {
            self.error = "Couldn't save: \(error.localizedDescription)"
            return false
        }
    }

    /// Keep what's in the editor; the next save overwrites the disk.
    func keepMine() {
        conflict = nil
    }

    /// A unified diff from the file on disk to the buffer.
    func diffAgainstDisk() -> String {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("tethera-buffer-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }
        try? Data(text.utf8).write(to: temp)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/diff")
        process.arguments = ["-u", "--label", "on disk", "--label", "in Tethera", path, temp.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: output, as: UTF8.self)
    }

    // MARK: Watching

    private func watch() {
        watcher?.cancel()
        watcher = nil
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.fileChanged(source.data) }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private func fileChanged(_ event: DispatchSource.FileSystemEvent) {
        // Most tools save by writing a new file and renaming it over the old one, so the watched
        // inode is gone: wait a beat, then follow the path again.
        if event.contains(.delete) || event.contains(.rename) {
            watcher?.cancel()
            watcher = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self else { return }
                if FileManager.default.fileExists(atPath: self.path) {
                    self.watch()
                    self.diskChanged()
                } else {
                    self.conflict = .deleted
                }
            }
            return
        }
        diskChanged()
    }

    private func diskChanged() {
        guard Date() > ignoreEventsUntil else { return }
        guard let data = FileManager.default.contents(atPath: path) else { return }
        let onDisk = String(decoding: data, as: UTF8.self)
        guard onDisk != savedText else { return }
        if isDirty {
            if onDisk == text {
                savedText = onDisk
                isDirty = false
            } else {
                conflict = .changedOnDisk
            }
        } else {
            reloadFromDisk()
        }
    }

    deinit {
        watcher?.cancel()
    }
}
