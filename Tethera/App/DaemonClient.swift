import AppKit
import Foundation
import TetheraKit

/// Another Mac whose sessions show in the sidebar, reached over SSH.
struct RemoteHost: Codable, Equatable, Hashable, Identifiable {
    var id = UUID().uuidString
    var name: String
    /// What you'd type after `ssh`: a host from ~/.ssh/config, user@host, or a Tailscale name.
    var address: String
}

/// The app's connections to session daemons: this Mac's, plus one per remote Mac through
/// `ssh <host> tethera bridge`. Holds the merged session list and the pipe that carries each
/// session's output to its terminal view. Starts the local daemon when it isn't running.
@MainActor
final class DaemonClient: ObservableObject {
    static let shared = DaemonClient()

    enum Status: Equatable {
        case connecting
        case connected
        case failed(String)
    }

    /// This Mac's daemon.
    @Published private(set) var status: Status = .connecting
    /// Each remote Mac's connection, by host id.
    @Published private(set) var remoteStatus: [String: Status] = [:]
    /// Every session, this Mac's first, then each remote Mac's in settings order.
    @Published private(set) var sessions: [SessionInfo] = []
    /// Set once this Mac's first session list has arrived, so the window can restore its layout.
    @Published private(set) var hasLoaded = false

    /// Receives every session update with the previous value (for notifications).
    var onUpdate: ((SessionInfo, SessionInfo?) -> Void)?
    var onRemove: ((SessionInfo) -> Void)?
    /// True while the first session list after connecting is delivered: those sessions
    /// existed already, they didn't just start.
    private(set) var deliveringInitialList = false

    /// One daemon connection. The key is "" for this Mac, the host id for a remote one.
    @MainActor private final class Link {
        let key: String
        var host: RemoteHost?
        var socket: FramedSocket?
        var ssh: Process?
        var sessions: [SessionInfo] = []
        var pendingCreates: [(SessionInfo) -> Void] = []
        var reconnectAttempts = 0
        var hasLoaded = false
        /// Cleared when the host is removed, so it stops reconnecting.
        var wanted = true

        init(key: String, host: RemoteHost?) {
            self.key = key
            self.host = host
        }
    }

    private let ioQueue = DispatchQueue(label: "tethera.client", qos: .userInteractive)
    private var links: [String: Link] = ["": Link(key: "", host: nil)]
    private var sinks: [UUID: (Frame) -> Void] = [:]
    private var sinkSizes: [UUID: (Int, Int)] = [:]
    private var handoverAttempted = false

    private init() {}

    // MARK: - Connection

    /// The `tethera` helper: inside the app bundle, or next to the dev build.
    static var cliPath: String {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/tethera").path
        if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
        let sibling = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("tethera-cli").path
        return sibling ?? "tethera"
    }

    /// Run on the other Mac: the first `tethera` it has, in plain sh so any login shell works.
    nonisolated static func remoteCommand(_ arguments: String) -> String {
        #"exec /bin/sh -c 'for c in "$HOME/.local/bin/tethera" /opt/homebrew/bin/tethera /usr/local/bin/tethera /Applications/Tethera.app/Contents/Helpers/tethera; do if [ -x "$c" ]; then exec "$c" "# + arguments + #"; fi; done; echo "Tethera is not installed there." >&2; exit 127'"#
    }

    nonisolated static let sshOptions = ["-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10"]

    /// Checks that `ssh address` works and finds Tethera there; returns its version or why not.
    nonisolated static func check(_ address: String) async -> Result<String, CheckFailure> {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = sshOptions + [address, remoteCommand("version")]
            let output = Pipe(), errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            process.standardInput = FileHandle.nullDevice
            process.terminationHandler = { process in
                let out = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let err = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if process.terminationStatus == 0 {
                    continuation.resume(returning: .success(out.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else {
                    let line = err.split(whereSeparator: \.isNewline).last.map(String.init)
                    continuation.resume(returning: .failure(CheckFailure(message: describe(sshExit: process.terminationStatus, stderr: line))))
                }
            }
            do { try process.run() } catch {
                continuation.resume(returning: .failure(CheckFailure(message: "Couldn't run ssh (\(error.localizedDescription)).")))
            }
        }
    }

    struct CheckFailure: Error {
        let message: String
    }

    func connect() {
        connect(links[""]!)
        syncRemoteHosts(PreferencesStore.shared.value.remoteHosts)
    }

    /// Connects hosts that were added and drops the ones that were removed.
    func syncRemoteHosts(_ hosts: [RemoteHost]) {
        let wanted = Set(hosts.map(\.id))
        for (key, link) in links where !key.isEmpty && !wanted.contains(key) {
            link.wanted = false
            link.ssh?.terminate()
            link.socket?.close()
            links[key] = nil
            remoteStatus[key] = nil
            for session in link.sessions { onRemove?(session) }
            rebuild()
        }
        for host in hosts {
            if let link = links[host.id] {
                if link.host?.address != host.address {
                    link.host = host
                    link.ssh?.terminate()
                }
                link.host = host
            } else {
                let link = Link(key: host.id, host: host)
                links[host.id] = link
                connect(link)
            }
        }
        rebuild()
    }

    /// Reconnects a remote Mac now instead of waiting for the next retry.
    func retry(_ hostID: String) {
        guard let link = links[hostID], link.socket == nil else { return }
        link.reconnectAttempts = 0
        connect(link)
    }

    private func connect(_ link: Link) {
        setStatus(.connecting, for: link)
        if let host = link.host {
            connectRemote(link, host: host)
            return
        }
        let path = Self.cliPath
        ioQueue.async { [weak self] in
            let result = Result { try DaemonLauncher.connect(executable: path, timeout: 4) }
            DispatchQueue.main.async {
                switch result {
                case .success(let fd): self?.connected(link, fd: fd)
                case .failure(let error): self?.failed(link, "Couldn't start the session daemon (\(error.localizedDescription)).")
                }
            }
        }
    }

    /// `ssh host tethera bridge` with its stdin and stdout on one end of a socket pair; the
    /// daemon protocol runs over the other end exactly as it does over the local socket.
    private func connectRemote(_ link: Link, host: RemoteHost) {
        var fds: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else {
            failed(link, "Couldn't open a pipe for ssh.")
            return
        }
        var on: Int32 = 1
        for fd in fds { setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size)) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = Self.sshOptions + ["-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3",
                                               host.address, Self.remoteCommand("bridge")]
        #if DEBUG
        // Captures stand in a second daemon on this Mac for the other one.
        if host.address.hasPrefix("exec:") {
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", String(host.address.dropFirst(5))]
        }
        #endif
        let child = FileHandle(fileDescriptor: fds[1], closeOnDealloc: true)
        process.standardInput = child
        process.standardOutput = child
        let errors = Pipe()
        process.standardError = errors
        let errorText = LockedText()
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { errorText.append(String(decoding: data, as: UTF8.self)) }
        }
        process.terminationHandler = { [weak self] process in
            errors.fileHandleForReading.readabilityHandler = nil
            let message = errorText.lastLine
            let code = process.terminationStatus
            DispatchQueue.main.async {
                guard let self, link.wanted, link.ssh === process else { return }
                link.ssh = nil
                link.socket?.close()
                self.failed(link, Self.describe(sshExit: code, stderr: message))
            }
        }
        do {
            try process.run()
        } catch {
            Darwin.close(fds[0])
            failed(link, "Couldn't run ssh (\(error.localizedDescription)).")
            return
        }
        try? child.close()
        link.ssh = process
        connected(link, fd: fds[0])
    }

    /// The `tethera` to hand the daemon over to, when the daemon is older than this app and
    /// new enough to know how (1.0 or later). Only packaged apps: dev builds have no version.
    static func handoverTarget(daemon: String, app: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                               cli: String? = nil) -> String? {
        let cli = cli ?? cliPath
        guard let app, Updater.isNewer(app, than: daemon), !Updater.isNewer("1.0.0", than: daemon),
              FileManager.default.isExecutableFile(atPath: cli) else { return nil }
        return cli
    }

    private nonisolated static func describe(sshExit code: Int32, stderr: String?) -> String {
        if let stderr, !stderr.isEmpty { return stderr }
        switch code {
        case 255: return "Couldn't reach it over SSH."
        case 127: return "Tethera is not installed there."
        default: return "The connection ended."
        }
    }

    private func connected(_ link: Link, fd: Int32) {
        guard link.wanted else { Darwin.close(fd); return }
        let key = link.key
        let socket = FramedSocket(fd: fd, queue: ioQueue)
        socket.onFrame = { [weak self] frame in self?.receive(frame, from: key) }
        socket.onClose = { [weak self] _ in
            DispatchQueue.main.async { self?.disconnected(link, socket: socket) }
        }
        socket.start()
        link.socket = socket
        var hello = ControlMessage(.hello)
        hello.protocolVersion = tetheraProtocolVersion
        socket.send(hello)
        socket.send(ControlMessage(.subscribe))
    }

    private func disconnected(_ link: Link, socket: FramedSocket) {
        guard link.socket === socket else { return }
        link.socket = nil
        link.ssh?.terminate()
        // A remote Mac's sessions stay listed while it reconnects; typing waits for it.
        if status(of: link) == .connected { setStatus(.connecting, for: link) }
        scheduleReconnect(link)
    }

    private func failed(_ link: Link, _ message: String) {
        link.socket = nil
        setStatus(.failed(message), for: link)
        scheduleReconnect(link)
    }

    private func scheduleReconnect(_ link: Link) {
        guard link.wanted else { return }
        link.reconnectAttempts += 1
        // Remote Macs back off further: they may be asleep or off the network for a while.
        let limit = link.host == nil ? 5.0 : 60.0
        let delay = min(limit, (link.host == nil ? 0.3 : 2.0) * Double(link.reconnectAttempts))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, link.wanted, link.socket == nil, self.links[link.key] === link else { return }
            self.connect(link)
        }
    }

    private func status(of link: Link) -> Status {
        link.host == nil ? status : (remoteStatus[link.key] ?? .connecting)
    }

    private func setStatus(_ value: Status, for link: Link) {
        if link.host == nil {
            if status != value { status = value }
        } else if remoteStatus[link.key] != value {
            remoteStatus[link.key] = value
        }
    }

    /// Runs on the IO queue. Terminal bytes go straight to their sink; control messages hop to main.
    private nonisolated func receive(_ frame: Frame, from key: String) {
        switch frame {
        case .output(let session, _, _), .snapshot(let session, _, _):
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.sinks[session]?(frame) }
            }
        case .control:
            guard let message = frame.controlMessage else { return }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let link = self.links[key] else { return }
                    self.handle(message, from: link)
                }
            }
        case .input:
            break
        }
    }

    private func handle(_ message: ControlMessage, from link: Link) {
        switch message.type {
        case .welcome:
            if link.host == nil, !handoverAttempted, let daemon = message.message, let target = Self.handoverTarget(daemon: daemon) {
                // Once per launch: if the exec fails, the old daemon carries on and that's fine.
                handoverAttempted = true
                // An update replaced the app; move the running daemon to the new version. It
                // keeps every session, drops this connection, and answers again in a moment.
                var handover = ControlMessage(.handover)
                handover.message = target
                link.socket?.send(handover)
                NSLog("tethera: handing the \(daemon) daemon over to \(target)")
                return
            }
            if message.protocolVersion != tetheraProtocolVersion {
                setStatus(.failed(link.host == nil
                    ? "The running session daemon is a different version. Quit and End All Sessions (⌥⌘Q) to restart it."
                    : "Its Tethera is a different version. Update both Macs to the same release."), for: link)
            } else {
                setStatus(.connected, for: link)
                link.reconnectAttempts = 0
            }
        case .sessions:
            let previous = Dictionary(uniqueKeysWithValues: link.sessions.map { ($0.id, $0) })
            let incoming = (message.sessions ?? []).map { tagged($0, link) }.sorted { $0.order < $1.order }
            let kept = Set(incoming.map(\.id))
            for gone in link.sessions where !kept.contains(gone.id) { onRemove?(gone) }
            link.sessions = incoming
            rebuild()
            deliveringInitialList = !link.hasLoaded
            link.hasLoaded = true
            if link.host == nil { hasLoaded = true }
            for session in incoming { onUpdate?(session, previous[session.id]) }
            deliveringInitialList = false
            reattachSinks(link)
        case .created:
            guard let info = message.info else { return }
            let session = tagged(info, link)
            upsert(session, in: link)
            if !link.pendingCreates.isEmpty { link.pendingCreates.removeFirst()(session) }
        case .updated:
            guard let info = message.info else { return }
            upsert(tagged(info, link), in: link)
        case .removed:
            guard let id = message.session else { return }
            if let gone = link.sessions.first(where: { $0.id == id }) { onRemove?(gone) }
            link.sessions.removeAll { $0.id == id }
            rebuild()
        case .error:
            NSLog("tethera daemon\(link.host.map { " on \($0.name)" } ?? ""): \(message.message ?? "error")")
        default:
            break
        }
    }

    private func tagged(_ info: SessionInfo, _ link: Link) -> SessionInfo {
        var info = info
        info.host = link.host?.id
        return info
    }

    private func upsert(_ info: SessionInfo, in link: Link) {
        let previous = link.sessions.first { $0.id == info.id }
        if let index = link.sessions.firstIndex(where: { $0.id == info.id }) {
            link.sessions[index] = info
        } else {
            link.sessions.append(info)
            link.sessions.sort { $0.order < $1.order }
        }
        rebuild()
        onUpdate?(info, previous)
    }

    /// This Mac's sessions, then each remote Mac's in the order they were added. Two entries
    /// that reach the same daemon (this Mac added as a remote, one Mac under two names) would
    /// list a session twice; it stays with the first.
    private func rebuild() {
        var merged = links[""]?.sessions ?? []
        var seen = Set(merged.map(\.id))
        for host in PreferencesStore.shared.value.remoteHosts {
            for session in links[host.id]?.sessions ?? [] where seen.insert(session.id).inserted {
                merged.append(session)
            }
        }
        if merged != sessions { sessions = merged }
    }

    private func link(for session: UUID) -> Link? {
        let key = sessions.first { $0.id == session }?.host ?? ""
        return links[key]
    }

    func session(_ id: UUID?) -> SessionInfo? {
        guard let id else { return nil }
        return sessions.first { $0.id == id }
    }

    func host(_ id: String?) -> RemoteHost? {
        guard let id else { return nil }
        return links[id]?.host
    }

    // MARK: - Terminal plumbing

    /// Starts receiving a session's output. The daemon answers with a snapshot first.
    func attach(_ id: UUID, cols: Int, rows: Int, sink: @escaping (Frame) -> Void) {
        sinks[id] = sink
        sinkSizes[id] = (cols, rows)
        var message = ControlMessage(.attach, session: id)
        message.cols = cols
        message.rows = rows
        link(for: id)?.socket?.send(message)
    }

    func detach(_ id: UUID) {
        guard sinks.removeValue(forKey: id) != nil else { return }
        sinkSizes.removeValue(forKey: id)
        link(for: id)?.socket?.send(ControlMessage(.detach, session: id))
    }

    /// After a reconnect, ask again for every terminal that's showing.
    private func reattachSinks(_ link: Link) {
        for (id, size) in sinkSizes where link.sessions.contains(where: { $0.id == id }) {
            var message = ControlMessage(.attach, session: id)
            message.cols = size.0
            message.rows = size.1
            link.socket?.send(message)
        }
    }

    func send(_ id: UUID, _ bytes: Data) {
        link(for: id)?.socket?.send(.input(session: id, bytes: bytes))
    }

    func resize(_ id: UUID, cols: Int, rows: Int) {
        sinkSizes[id] = (cols, rows)
        var message = ControlMessage(.resize, session: id)
        message.cols = cols
        message.rows = rows
        link(for: id)?.socket?.send(message)
    }

    // MARK: - Session commands

    /// Starts a session on this Mac, or on the remote Mac with that id.
    func create(_ spec: SessionSpec, on host: String? = nil, then: ((SessionInfo) -> Void)? = nil) {
        guard let link = links[host ?? ""], let socket = link.socket else { return }
        link.pendingCreates.append(then ?? { _ in })
        var message = ControlMessage(.create)
        message.spec = spec
        socket.send(message)
    }

    func rename(_ id: UUID, to name: String) {
        var message = ControlMessage(.rename, session: id)
        message.name = name
        link(for: id)?.socket?.send(message)
    }

    func close(_ id: UUID) {
        link(for: id)?.socket?.send(ControlMessage(.close, session: id))
    }

    func interrupt(_ id: UUID) {
        var message = ControlMessage(.signal, session: id)
        message.signal = SIGINT
        link(for: id)?.socket?.send(message)
    }

    /// Each Mac keeps its own order; the sidebar only moves rows within one Mac's group.
    func reorder(_ ids: [UUID]) {
        for link in links.values {
            let mine = Set(link.sessions.map(\.id))
            let order = ids.filter { mine.contains($0) }
            guard !order.isEmpty else { continue }
            let byID = Dictionary(uniqueKeysWithValues: link.sessions.map { ($0.id, $0) })
            link.sessions = order.compactMap { byID[$0] } + link.sessions.filter { !order.contains($0.id) }
            var message = ControlMessage(.reorder)
            message.order = order
            link.socket?.send(message)
        }
        rebuild()
    }

    /// Ends every session on this Mac and stops its daemon ("Quit and End All Sessions").
    func shutdownDaemon() {
        links[""]?.socket?.send(ControlMessage(.shutdown))
    }
}

/// ssh's error output, collected off the main thread.
private final class LockedText: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func append(_ chunk: String) {
        lock.lock()
        text = String((text + chunk).suffix(2000))
        lock.unlock()
    }

    /// The last non-empty line, which is where ssh puts the reason.
    var lastLine: String? {
        lock.lock()
        defer { lock.unlock() }
        return text.split(whereSeparator: \.isNewline).last.map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}
