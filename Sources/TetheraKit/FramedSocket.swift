import Foundation

/// A non-blocking Unix-domain socket that exchanges `Frame`s on a dispatch queue.
/// Used by the daemon for each client and by clients for their daemon connection.
public final class FramedSocket: @unchecked Sendable {
    public var onFrame: ((Frame) -> Void)?
    public var onClose: ((Error?) -> Void)?

    public let fd: Int32
    public let queue: DispatchQueue
    private var readSource: DispatchSourceRead?
    private var writeSource: DispatchSourceWrite?
    private var writeSourceActive = false
    private var decoder = FrameDecoder()
    private var outbox = Data()
    private var closed = false

    /// Bytes waiting to be written; the daemon drops clients that fall far behind.
    public var pendingBytes: Int { outbox.count }

    public init(fd: Int32, queue: DispatchQueue) {
        self.fd = fd
        self.queue = queue
        UnixSocket.setNonBlocking(fd)
    }

    deinit {
        // Dispatch traps if a suspended source is released, and the fd must outlive the sources.
        guard !closed else { return }
        if let writeSource {
            if !writeSourceActive { writeSource.resume() }
            writeSource.cancel()
        }
        if let readSource { readSource.cancel() } else { Darwin.close(fd) }
    }

    /// Starts reading. Call once, after setting the handlers.
    public func start() {
        let read = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        read.setEventHandler { [weak self] in self?.readAvailable() }
        // The descriptor may only be closed once dispatch has let go of it.
        let fd = self.fd
        read.setCancelHandler { Darwin.close(fd) }
        readSource = read
        let write = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: queue)
        write.setEventHandler { [weak self] in self?.flush() }
        writeSource = write
        read.resume()
    }

    public func send(_ frame: Frame) {
        queue.async { [self] in
            guard !closed else { return }
            outbox.append(frame.encoded())
            flush()
        }
    }

    public func send(_ message: ControlMessage) {
        send(.control(message))
    }

    /// Sends from code already running on `queue`, avoiding a hop.
    public func sendNow(_ frame: Frame) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !closed else { return }
        outbox.append(frame.encoded())
        flush()
    }

    public func close(error: Error? = nil) {
        queue.async { [self] in shutdown(error) }
    }

    // MARK: - IO

    private func readAvailable() {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count > 0 {
                do {
                    let frames = try decoder.append(Data(buffer[0..<count]))
                    for frame in frames {
                        guard !closed else { return }
                        onFrame?(frame)
                    }
                } catch {
                    shutdown(error)
                    return
                }
            } else if count == 0 {
                shutdown(nil)
                return
            } else {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                if errno == EINTR { continue }
                shutdown(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO))
                return
            }
        }
    }

    private func flush() {
        while !outbox.isEmpty {
            let written = outbox.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if written > 0 {
                outbox.removeSubrange(0..<written)
            } else if written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                break
            } else if written < 0 && errno == EINTR {
                continue
            } else {
                shutdown(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPIPE))
                return
            }
        }
        if outbox.isEmpty {
            outbox = Data()
            if writeSourceActive { writeSource?.suspend(); writeSourceActive = false }
        } else if !writeSourceActive {
            writeSource?.resume()
            writeSourceActive = true
        }
    }

    private func shutdown(_ error: Error?) {
        guard !closed else { return }
        closed = true
        if let writeSource {
            if !writeSourceActive { writeSource.resume() }
            writeSource.cancel()
        }
        if let readSource {
            readSource.cancel()
        } else {
            Darwin.close(fd)
        }
        outbox = Data()
        let handler = onClose
        onFrame = nil
        onClose = nil
        handler?(error)
    }
}

/// Unix-domain socket helpers.
public enum UnixSocket {
    public static func connect(path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError() }
        var address = try makeAddress(path)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else {
            let error = posixError()
            Darwin.close(fd)
            throw error
        }
        setNoSigPipe(fd)
        return fd
    }

    /// Binds and listens; the socket file is made owner-only.
    public static func listen(path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError() }
        unlink(path)
        var address = try makeAddress(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(fd, 64) == 0 else {
            let error = posixError()
            Darwin.close(fd)
            throw error
        }
        setNonBlocking(fd)
        fcntl(fd, F_SETFD, FD_CLOEXEC)
        return fd
    }

    /// The peer's uid, so the daemon only talks to its own user.
    public static func peerUID(_ fd: Int32) -> uid_t? {
        var uid: uid_t = 0
        var gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 ? uid : nil
    }

    public static func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }

    static func setNoSigPipe(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    private static func makeAddress(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { throw POSIXError(.ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return address
    }

    static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

/// Starts the daemon when no one is listening on the socket.
public enum DaemonLauncher {
    /// Connects to the running daemon, or spawns `executable daemon` detached and waits for it.
    public static func connect(executable: String, timeout: TimeInterval = 3) throws -> Int32 {
        if let fd = try? UnixSocket.connect(path: TetheraPaths.socket.path) { return fd }
        try spawn(executable: executable)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let fd = try? UnixSocket.connect(path: TetheraPaths.socket.path) { return fd }
            usleep(20_000)
        }
        throw POSIXError(.ETIMEDOUT)
    }

    /// Spawns the daemon in its own session with stdio on /dev/null and no inherited descriptors.
    public static func spawn(executable: String) throws {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF))
        var defaults = sigset_t()
        sigfillset(&defaults)
        posix_spawnattr_setsigdefault(&attributes, &defaults)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)

        let args = [executable, "daemon"]
        var argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        let env = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
        var envp: [UnsafeMutablePointer<CChar>?] = env.map { strdup($0) } + [nil]
        defer { envp.forEach { free($0) } }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, executable, &actions, &attributes, &argv, &envp)
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
    }
}
