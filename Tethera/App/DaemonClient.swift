import AppKit
import Foundation
import TetheraKit

/// The app's connection to the session daemon: the live session list, and the pipe that carries
/// each session's output to its terminal view. Starts the daemon when it isn't running.
@MainActor
final class DaemonClient: ObservableObject {
    static let shared = DaemonClient()

    enum Status: Equatable {
        case connecting
        case connected
        case failed(String)
    }

    @Published private(set) var status: Status = .connecting
    @Published private(set) var sessions: [SessionInfo] = []
    /// Set once the first session list has arrived, so the window knows it can restore its layout.
    @Published private(set) var hasLoaded = false

    /// Receives every session update with the previous value (for notifications).
    var onUpdate: ((SessionInfo, SessionInfo?) -> Void)?

    private let ioQueue = DispatchQueue(label: "tethera.client", qos: .userInteractive)
    private var socket: FramedSocket?
    private var sinks: [UUID: (Frame) -> Void] = [:]
    private var pendingCreates: [(SessionInfo) -> Void] = []
    private var reconnectAttempts = 0

    private init() {}

    // MARK: - Connection

    /// The `tethera` helper: inside the app bundle, or next to the dev build.
    static var cliPath: String {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/tethera").path
        if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
        let sibling = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("tethera-cli").path
        return sibling ?? "tethera"
    }

    func connect() {
        status = .connecting
        let path = Self.cliPath
        ioQueue.async { [weak self] in
            let result = Result { try DaemonLauncher.connect(executable: path, timeout: 4) }
            DispatchQueue.main.async { self?.connected(result) }
        }
    }

    private func connected(_ result: Result<Int32, Error>) {
        switch result {
        case .failure(let error):
            status = .failed("Couldn't start the session daemon (\(error.localizedDescription)).")
            scheduleReconnect()
        case .success(let fd):
            let socket = FramedSocket(fd: fd, queue: ioQueue)
            socket.onFrame = { [weak self] frame in self?.receive(frame) }
            socket.onClose = { [weak self] _ in
                DispatchQueue.main.async { self?.disconnected() }
            }
            socket.start()
            self.socket = socket
            var hello = ControlMessage(.hello)
            hello.protocolVersion = tetheraProtocolVersion
            socket.send(hello)
            socket.send(ControlMessage(.subscribe))
        }
    }

    private func disconnected() {
        socket = nil
        status = .connecting
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectAttempts += 1
        let delay = min(5.0, 0.3 * Double(reconnectAttempts))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.socket == nil else { return }
            self.connect()
        }
    }

    /// Runs on the IO queue. Terminal bytes go straight to their sink; control messages hop to main.
    private nonisolated func receive(_ frame: Frame) {
        switch frame {
        case .output(let session, _, _), .snapshot(let session, _, _):
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.sinks[session]?(frame) }
            }
        case .control:
            guard let message = frame.controlMessage else { return }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.handle(message) }
            }
        case .input:
            break
        }
    }

    private func handle(_ message: ControlMessage) {
        switch message.type {
        case .welcome:
            if message.protocolVersion != tetheraProtocolVersion {
                status = .failed("The running session daemon is a different version. Quit and End All Sessions (⌥⌘Q) to restart it.")
            } else {
                status = .connected
                reconnectAttempts = 0
            }
        case .sessions:
            let previous = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
            sessions = (message.sessions ?? []).sorted { $0.order < $1.order }
            hasLoaded = true
            for session in sessions { onUpdate?(session, previous[session.id]) }
            reattachSinks()
        case .created:
            guard let info = message.info else { return }
            upsert(info)
            if !pendingCreates.isEmpty { pendingCreates.removeFirst()(info) }
        case .updated:
            guard let info = message.info else { return }
            upsert(info)
        case .removed:
            guard let id = message.session else { return }
            sessions.removeAll { $0.id == id }
        case .error:
            NSLog("tethera daemon: \(message.message ?? "error")")
        default:
            break
        }
    }

    private func upsert(_ info: SessionInfo) {
        let previous = sessions.first { $0.id == info.id }
        if let index = sessions.firstIndex(where: { $0.id == info.id }) {
            sessions[index] = info
        } else {
            sessions.append(info)
            sessions.sort { $0.order < $1.order }
        }
        onUpdate?(info, previous)
    }

    func session(_ id: UUID?) -> SessionInfo? {
        guard let id else { return nil }
        return sessions.first { $0.id == id }
    }

    // MARK: - Terminal plumbing

    private var sinkSizes: [UUID: (Int, Int)] = [:]

    /// Starts receiving a session's output. The daemon answers with a snapshot first.
    func attach(_ id: UUID, cols: Int, rows: Int, sink: @escaping (Frame) -> Void) {
        sinks[id] = sink
        sinkSizes[id] = (cols, rows)
        var message = ControlMessage(.attach, session: id)
        message.cols = cols
        message.rows = rows
        socket?.send(message)
    }

    func detach(_ id: UUID) {
        guard sinks.removeValue(forKey: id) != nil else { return }
        sinkSizes.removeValue(forKey: id)
        socket?.send(ControlMessage(.detach, session: id))
    }

    /// After a reconnect, ask again for every terminal that's showing.
    private func reattachSinks() {
        for (id, size) in sinkSizes where sessions.contains(where: { $0.id == id }) {
            var message = ControlMessage(.attach, session: id)
            message.cols = size.0
            message.rows = size.1
            socket?.send(message)
        }
    }

    func send(_ id: UUID, _ bytes: Data) {
        socket?.send(.input(session: id, bytes: bytes))
    }

    func resize(_ id: UUID, cols: Int, rows: Int) {
        sinkSizes[id] = (cols, rows)
        var message = ControlMessage(.resize, session: id)
        message.cols = cols
        message.rows = rows
        socket?.send(message)
    }

    // MARK: - Session commands

    func create(_ spec: SessionSpec, then: ((SessionInfo) -> Void)? = nil) {
        pendingCreates.append(then ?? { _ in })
        var message = ControlMessage(.create)
        message.spec = spec
        socket?.send(message)
    }

    func rename(_ id: UUID, to name: String) {
        var message = ControlMessage(.rename, session: id)
        message.name = name
        socket?.send(message)
    }

    func close(_ id: UUID) {
        socket?.send(ControlMessage(.close, session: id))
    }

    func interrupt(_ id: UUID) {
        var message = ControlMessage(.signal, session: id)
        message.signal = SIGINT
        socket?.send(message)
    }

    func reorder(_ ids: [UUID]) {
        let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        sessions = ids.compactMap { byID[$0] }
        var message = ControlMessage(.reorder)
        message.order = ids
        socket?.send(message)
    }

    /// Ends every session and stops the daemon ("Quit and End All Sessions").
    func shutdownDaemon() {
        socket?.send(ControlMessage(.shutdown))
    }
}
