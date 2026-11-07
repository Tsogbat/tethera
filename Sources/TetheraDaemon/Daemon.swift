import Foundation
import TetheraKit

/// The per-user session daemon. Owns every PTY so sessions outlive the app, and speaks the
/// framed protocol on a 0600 Unix socket. All state lives on one serial queue.
public final class Daemon {
    public let version: String
    private let queue = DispatchQueue(label: "tethera.daemon")
    private var sessions: [UUID: SessionHost] = [:]
    private var clients: [ObjectIdentifier: Client] = [:]
    private var listenFD: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private var timers: [DispatchSourceTimer] = []
    private var idleSince: Date?
    private var onStop: (() -> Void)?

    private final class Client {
        let socket: FramedSocket
        var subscribed = false
        var attached: Set<UUID> = []
        init(socket: FramedSocket) { self.socket = socket }
    }

    public init(version: String) {
        self.version = version
    }

    // MARK: - Process entry

    /// Runs the daemon as this process and never returns. Exits quietly if one is already running.
    public static func runForever(version: String) -> Never {
        do {
            try TetheraPaths.prepare()
        } catch {
            log("cannot create \(TetheraPaths.home.path): \(error)")
            exit(1)
        }
        let lock = open(TetheraPaths.lock.path, O_CREAT | O_RDWR, 0o600)
        guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            log("another daemon holds the lock; exiting")
            exit(0)
        }
        _ = setsid()
        signal(SIGHUP, SIG_IGN)
        signal(SIGPIPE, SIG_IGN)

        let daemon = Daemon(version: version)
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                log("signal \(sig): saving and exiting")
                daemon.queue.sync { daemon.saveAll(force: true) }
                exit(0)
            }
            source.resume()
            daemon.signalSources.append(source)
        }
        daemon.onStop = { exit(0) }
        do {
            try daemon.start()
        } catch {
            log("failed to start: \(error)")
            exit(1)
        }
        log("daemon \(version) listening on \(TetheraPaths.socket.path) (pid \(getpid()))")
        dispatchMain()
    }

    private var signalSources: [DispatchSourceSignal] = []

    /// Binds the socket, restores saved sessions and starts the timers.
    public func start() throws {
        try TetheraPaths.prepare()
        listenFD = try UnixSocket.listen(path: TetheraPaths.socket.path)
        let source = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptClients() }
        let fd = listenFD
        source.setCancelHandler { Darwin.close(fd) }
        listenSource = source
        queue.sync { restoreSaved() }
        source.resume()

        addTimer(every: 1) { [weak self] in self?.tick() }
        addTimer(every: 5) { [weak self] in self?.saveAll(force: false) }
    }

    /// Stops listening and ends every session (used by tests and `shutdown`).
    public func stop(endSessions: Bool) {
        queue.sync {
            if endSessions {
                sessions.values.forEach { $0.terminate() }
                sessions.removeAll()
                try? FileManager.default.removeItem(at: TetheraPaths.state)
            } else {
                saveAll(force: true)
            }
            timers.forEach { $0.cancel() }
            timers.removeAll()
            listenSource?.cancel()
            listenSource = nil
            unlink(TetheraPaths.socket.path)
            clients.values.forEach { $0.socket.close() }
            clients.removeAll()
        }
    }

    private func addTimer(every seconds: Double, _ handler: @escaping () -> Void) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + seconds, repeating: seconds, leeway: .milliseconds(100))
        timer.setEventHandler(handler: handler)
        timer.resume()
        timers.append(timer)
    }

    // MARK: - Clients

    private func acceptClients() {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }
            guard UnixSocket.peerUID(fd) == getuid() else {
                Darwin.close(fd)
                continue
            }
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            let socket = FramedSocket(fd: fd, queue: queue)
            let client = Client(socket: socket)
            let key = ObjectIdentifier(socket)
            clients[key] = client
            socket.onFrame = { [weak self, weak client] frame in
                guard let self, let client else { return }
                self.handle(frame, from: client)
            }
            socket.onClose = { [weak self] _ in self?.disconnect(key) }
            socket.start()
            idleSince = nil
        }
    }

    private func disconnect(_ key: ObjectIdentifier) {
        guard let client = clients.removeValue(forKey: key) else { return }
        for id in client.attached { sessions[id]?.detach(client.socket) }
    }

    private func handle(_ frame: Frame, from client: Client) {
        switch frame {
        case .input(let session, let bytes):
            sessions[session]?.write(bytes)
        case .control:
            guard let message = frame.controlMessage else {
                reply(client, error: "malformed message")
                return
            }
            handle(message, from: client)
        case .output, .snapshot:
            break
        }
    }

    private func handle(_ message: ControlMessage, from client: Client) {
        switch message.type {
        case .hello:
            var welcome = ControlMessage(.welcome)
            welcome.protocolVersion = tetheraProtocolVersion
            welcome.pid = getpid()
            welcome.message = version
            client.socket.sendNow(.control(welcome))

        case .list:
            client.socket.sendNow(.control(sessionsMessage()))

        case .subscribe:
            client.subscribed = true
            client.socket.sendNow(.control(sessionsMessage()))

        case .create:
            guard let spec = message.spec else { return reply(client, error: "create needs a spec") }
            do {
                let host = try createSession(spec)
                var created = ControlMessage(.created, session: host.id)
                created.info = host.info
                client.socket.sendNow(.control(created))
            } catch {
                reply(client, error: "couldn't start a shell: \(error.localizedDescription)")
            }

        case .attach:
            guard let id = message.session, let host = sessions[id] else { return reply(client, error: "no such session") }
            do {
                try host.attach(client.socket, cols: message.cols ?? host.info.cols, rows: message.rows ?? host.info.rows)
                client.attached.insert(id)
            } catch {
                reply(client, error: "couldn't restart the session: \(error.localizedDescription)")
            }

        case .detach:
            guard let id = message.session else { return }
            sessions[id]?.detach(client.socket)
            client.attached.remove(id)

        case .resize:
            guard let id = message.session, let cols = message.cols, let rows = message.rows else { return }
            sessions[id]?.resize(cols: cols, rows: rows)

        case .signal:
            guard let id = message.session, let signal = message.signal else { return }
            sessions[id]?.signalForeground(signal)

        case .rename:
            guard let id = message.session, let name = message.name else { return }
            sessions[id]?.rename(name)

        case .reorder:
            for (index, id) in (message.order ?? []).enumerated() { sessions[id]?.setOrder(index) }

        case .close:
            guard let id = message.session, let host = sessions[id] else { return }
            if host.info.isAlive {
                host.terminate()  // removed when the process exits
            } else {
                remove(host)
            }

        case .hook:
            // Agent hook payloads are mapped in the agent-awareness layer.
            guard let id = message.session, let agent = message.agent, let payload = message.payload else { return }
            sessions[id]?.applyHook(agent: agent, payload: payload, sentAt: message.sentAt)

        case .shutdown:
            log("shutdown requested")
            sessions.values.forEach { $0.terminate() }
            sessions.removeAll()
            try? FileManager.default.removeItem(at: TetheraPaths.state)
            client.socket.sendNow(.control(ControlMessage(.removed)))
            queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.onStop?() }

        case .welcome, .sessions, .created, .attached, .updated, .removed, .exited, .error:
            break
        }
    }

    private func reply(_ client: Client, error text: String) {
        var message = ControlMessage(.error)
        message.message = text
        client.socket.sendNow(.control(message))
    }

    private func sessionsMessage() -> ControlMessage {
        var message = ControlMessage(.sessions)
        message.sessions = sessions.values.map(\.info).sorted { $0.order < $1.order }
        return message
    }

    private func broadcast(_ message: ControlMessage) {
        let frame = Frame.control(message)
        for client in clients.values where client.subscribed {
            client.socket.sendNow(frame)
        }
    }

    // MARK: - Sessions

    private func createSession(_ spec: SessionSpec) throws -> SessionHost {
        let cwd = spec.cwd.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil } ?? NSHomeDirectory()
        let order = (sessions.values.map(\.info.order).max() ?? -1) + 1
        var info = SessionInfo(name: uniqueName(spec.name ?? defaultName(for: cwd), excluding: nil), cwd: cwd,
                               shell: spec.shell ?? ShellLaunch.loginShell, cols: spec.cols, rows: spec.rows, order: order)
        info.customName = spec.name
        let host = SessionHost(info: info, queue: queue, version: version)
        wire(host)
        try host.start(shell: spec.shell, initialInput: spec.initialInput)
        sessions[host.id] = host
        var update = ControlMessage(.updated, session: host.id)
        update.info = host.info
        broadcast(update)
        return host
    }

    private func wire(_ host: SessionHost) {
        host.onChange = { [weak self] host in
            guard let self, self.sessions[host.id] != nil else { return }
            var update = ControlMessage(.updated, session: host.id)
            update.info = host.info
            self.broadcast(update)
        }
        host.onExit = { [weak self] host in self?.remove(host) }
        host.nameForFolder = { [weak self] cwd, id in
            guard let self else { return (cwd as NSString).lastPathComponent }
            return self.uniqueName(self.defaultName(for: cwd), excluding: id)
        }
    }

    private func remove(_ host: SessionHost) {
        guard sessions.removeValue(forKey: host.id) != nil else { return }
        try? FileManager.default.removeItem(at: snapshotURL(host.id))
        for client in clients.values where client.attached.contains(host.id) { client.attached.remove(host.id) }
        broadcast(ControlMessage(.removed, session: host.id))
        saveAll(force: true)
    }

    private func defaultName(for cwd: String) -> String {
        cwd == NSHomeDirectory() ? "~" : (cwd as NSString).lastPathComponent
    }

    private func uniqueName(_ base: String, excluding id: UUID?) -> String {
        let names = Set(sessions.values.filter { $0.id != id }.map(\.info.name))
        guard names.contains(base) else { return base }
        var index = 2
        while names.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }

    private func tick() {
        sessions.values.forEach { $0.tick() }
        // Nothing to keep alive: exit after a while so a stray daemon doesn't linger.
        if sessions.isEmpty && clients.isEmpty {
            if let since = idleSince {
                if Date().timeIntervalSince(since) > 600 { onStop?() }
            } else {
                idleSince = Date()
            }
        } else {
            idleSince = nil
        }
    }

    // MARK: - Persistence

    private func snapshotURL(_ id: UUID) -> URL {
        TetheraPaths.snapshots.appendingPathComponent("\(id.uuidString).vt")
    }

    /// Saves the session list and the history of sessions that changed, for cold restore.
    private func saveAll(force: Bool) {
        let infos = sessions.values.map(\.info).sorted { $0.order < $1.order }
        for host in sessions.values where host.info.isAlive && (force || host.isDirty) {
            try? host.snapshot(includeAlternate: false).write(to: snapshotURL(host.id), options: .atomic)
            host.markSaved()
        }
        if let data = try? JSONEncoder().encode(infos) {
            try? data.write(to: TetheraPaths.state, options: .atomic)
        }
    }

    private func restoreSaved() {
        guard let data = try? Data(contentsOf: TetheraPaths.state),
              let infos = try? JSONDecoder().decode([SessionInfo].self, from: data) else { return }
        for info in infos where sessions[info.id] == nil {
            let history = try? Data(contentsOf: snapshotURL(info.id))
            let host = SessionHost(restored: info, history: history, queue: queue, version: version)
            wire(host)
            sessions[info.id] = host
        }
        if !infos.isEmpty { log("restored \(infos.count) session(s) cold") }
    }
}

func log(_ message: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    if let handle = try? FileHandle(forWritingTo: TetheraPaths.log) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? Data(line.utf8).write(to: TetheraPaths.log)
    }
}
