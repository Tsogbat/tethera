import AppKit
import Foundation
import TetheraKit

/// Listens on `AppChannel.socket` for the CLI: `tethera open` and `tethera mcp` (browser tools).
/// Requests are handled on the main actor; each connection is served in order.
@MainActor
final class AppServer {
    static let shared = AppServer()

    typealias Handler = @MainActor (AppChannel.Request) async -> AppChannel.Response

    private var listenFD: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private var connections: [Int32: Connection] = [:]
    private var handlers: [String: Handler] = [:]
    private var prefixHandlers: [(String, Handler)] = []

    func register(_ method: String, _ handler: @escaping Handler) { handlers[method] = handler }
    func register(prefix: String, _ handler: @escaping Handler) { prefixHandlers.append((prefix, handler)) }

    func start() {
        guard listenFD < 0 else { return }
        do {
            try TetheraPaths.prepare()
            listenFD = try UnixSocket.listen(path: AppChannel.socket.path)
        } catch {
            NSLog("Tethera: app channel unavailable: \(error)")
            return
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.accept() } }
        source.resume()
        listenSource = source
    }

    func stop() {
        listenSource?.cancel()
        listenSource = nil
        if listenFD >= 0 { close(listenFD) }
        listenFD = -1
        unlink(AppChannel.socket.path)
        connections.values.forEach { $0.close() }
        connections.removeAll()
    }

    private func accept() {
        while true {
            let fd = Darwin.accept(listenFD, nil, nil)
            guard fd >= 0 else { return }
            guard UnixSocket.peerUID(fd) == getuid() else {
                close(fd)
                continue
            }
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            let connection = Connection(fd: fd) { [weak self] request in
                await self?.handle(request) ?? AppChannel.Response(id: request.id, error: "closing")
            } onClose: { [weak self] fd in
                self?.connections.removeValue(forKey: fd)
            }
            connections[fd] = connection
        }
    }

    private func handle(_ request: AppChannel.Request) async -> AppChannel.Response {
        if let handler = handlers[request.method] ?? prefixHandlers.first(where: { request.method.hasPrefix($0.0) })?.1 {
            return await handler(request)
        }
        return AppChannel.Response(id: request.id, error: "unknown method \(request.method)")
    }

    /// One client: reads JSON lines, answers each in turn.
    final class Connection {
        private let fd: Int32
        private let source: DispatchSourceRead
        private var buffer = Data()
        private var queue: [AppChannel.Request] = []
        private var busy = false
        private let handle: @MainActor (AppChannel.Request) async -> AppChannel.Response
        private let onClose: @MainActor (Int32) -> Void

        init(fd: Int32, handle: @escaping @MainActor (AppChannel.Request) async -> AppChannel.Response,
             onClose: @escaping @MainActor (Int32) -> Void) {
            self.fd = fd
            self.handle = handle
            self.onClose = onClose
            UnixSocket.setNonBlocking(fd)
            source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.readAvailable() } }
            source.resume()
        }

        @MainActor
        private func readAvailable() {
            var chunk = [UInt8](repeating: 0, count: 65_536)
            let count = read(fd, &chunk, chunk.count)
            guard count > 0 else {
                if count < 0 && errno == EAGAIN { return }
                close()
                onClose(fd)
                return
            }
            buffer.append(contentsOf: chunk[0..<count])
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                if let request = try? JSONDecoder().decode(AppChannel.Request.self, from: line) { queue.append(request) }
            }
            drain()
        }

        @MainActor
        private func drain() {
            guard !busy, !queue.isEmpty else { return }
            busy = true
            let request = queue.removeFirst()
            Task { @MainActor in
                let response = await handle(request)
                write(response)
                busy = false
                drain()
            }
        }

        private func write(_ response: AppChannel.Response) {
            guard var data = try? JSONEncoder().encode(response) else { return }
            data.append(0x0A)
            var offset = 0
            // Responses can be large (screenshots); the socket is non-blocking, so wait for room.
            while offset < data.count {
                let written = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress! + offset, $0.count - offset) }
                if written > 0 {
                    offset += written
                } else if errno == EAGAIN {
                    var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                    _ = poll(&pfd, 1, 1_000)
                } else {
                    return
                }
            }
        }

        func close() {
            source.cancel()
            Darwin.close(fd)
        }
    }
}
