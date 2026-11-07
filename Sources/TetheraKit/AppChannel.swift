import Foundation

/// A small channel from the command line straight to the running app, for things only the app
/// can do: opening files in panes and driving its browser. The daemon isn't involved, so it
/// works with a daemon started by an older version.
///
/// One JSON object per line, over `~/Library/Application Support/Tethera/app.sock` (mode 0600,
/// peers checked with `getpeereid` like the daemon socket).
public enum AppChannel {
    public static var socket: URL { TetheraPaths.home.appendingPathComponent("app.sock") }

    public struct Request: Codable, Sendable {
        public var id: Int
        /// `open`, or a browser tool name such as `browser_navigate`.
        public var method: String
        /// The session the request came from (`TETHERA_SESSION_ID`), so results open beside it.
        public var session: String?
        /// The method's arguments as a JSON object.
        public var params: String

        public init(id: Int, method: String, session: String?, params: String) {
            self.id = id
            self.method = method
            self.session = session
            self.params = params
        }
    }

    public struct Response: Codable, Sendable {
        public var id: Int
        public var text: String?
        /// A PNG, base64-encoded, for screenshots.
        public var image: String?
        public var error: String?

        public init(id: Int, text: String? = nil, image: String? = nil, error: String? = nil) {
            self.id = id
            self.text = text
            self.image = image
            self.error = error
        }
    }

    public enum Failure: Error, LocalizedError {
        case notRunning
        case closed

        public var errorDescription: String? {
            switch self {
            case .notRunning: return "Tethera isn't running. Open it and try again."
            case .closed: return "Tethera closed the connection."
            }
        }
    }

    /// A blocking connection for the CLI and `tethera mcp`.
    public final class Connection {
        private let fd: Int32
        private var buffer = Data()
        private var nextID = 1

        public init() throws {
            do {
                fd = try UnixSocket.connect(path: AppChannel.socket.path)
            } catch {
                throw Failure.notRunning
            }
        }

        deinit { close(fd) }

        public func call(_ method: String, params: [String: Any] = [:], session: String? = nil) throws -> Response {
            let id = nextID
            nextID += 1
            let json = (try? JSONSerialization.data(withJSONObject: params)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            var line = try JSONEncoder().encode(Request(id: id, method: method, session: session, params: json))
            line.append(0x0A)
            let written = line.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            guard written == line.count else { throw Failure.closed }
            while true {
                if let newline = buffer.firstIndex(of: 0x0A) {
                    let body = buffer[buffer.startIndex..<newline]
                    buffer.removeSubrange(buffer.startIndex...newline)
                    if let response = try? JSONDecoder().decode(Response.self, from: body), response.id == id { return response }
                    continue
                }
                var chunk = [UInt8](repeating: 0, count: 65_536)
                let count = read(fd, &chunk, chunk.count)
                guard count > 0 else { throw Failure.closed }
                buffer.append(contentsOf: chunk[0..<count])
            }
        }
    }
}
