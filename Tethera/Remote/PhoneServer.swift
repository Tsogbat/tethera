import AppKit
import CoreImage.CIFilterBuiltins
import Darwin
import Foundation
import Network
import TetheraKit

/// Where the phone dashboard listens.
enum PhoneReach: String, Codable, CaseIterable, Identifiable {
    /// Only on the Tailscale address: reachable from your tailnet, encrypted by WireGuard.
    case tailscale
    /// Every interface, for phones on the same Wi-Fi. Plain HTTP.
    case localNetwork

    var id: String { rawValue }
    var label: String { self == .tailscale ? "Tailscale" : "Local network" }
}

/// The phone dashboard: a page that lists your agents and pending approvals and lets you allow,
/// deny, or answer from your phone. Off until you turn it on in Settings → Remote. Everything
/// but the page itself needs the pairing token, which travels in the URL's fragment (never sent
/// to a server) and is kept by the page.
@MainActor
final class PhoneServer: ObservableObject {
    static let shared = PhoneServer()
    nonisolated static let defaultPort: UInt16 = 7340

    /// The address to open on the phone, token included, while the dashboard is on.
    @Published private(set) var pairingURL: URL?
    @Published private(set) var problem: String?

    private var listener: NWListener?
    private var running: (reach: PhoneReach, host: String?, port: UInt16)?
    /// One-time links for a push notification's Allow and Deny buttons, so the pairing token
    /// itself never goes through the push service.
    private var actionLinks: [String: (approval: UUID, answer: ApprovalCenter.Answer)] = [:]

    private init() {}

    // MARK: Lifecycle

    /// Starts, restarts, or stops to match the preferences.
    func apply(_ preferences: Preferences) {
        guard preferences.phoneEnabled, let token = preferences.phoneToken else {
            stop()
            return
        }
        let host = Self.bindHost(for: preferences.phoneReach)
        if preferences.phoneReach == .tailscale && host == nil {
            stop()
            problem = "Tailscale isn't connected on this Mac. Open Tailscale, or choose Local network."
            return
        }
        let port = UInt16(clamping: preferences.phonePort)
        if let running, running.reach == preferences.phoneReach, running.host == host, running.port == port, listener != nil {
            pairingURL = Self.url(host: Self.displayHost(reach: preferences.phoneReach, bound: host), port: port, token: token)
            return
        }
        stop()
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener: NWListener
            if let host {
                parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
                listener = try NWListener(using: parameters)
            } else {
                listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    if case .failed(let error) = state {
                        self.problem = "Couldn't listen on port \(port) (\(error.localizedDescription))."
                        self.stop(keepProblem: true)
                    }
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
            self.listener = listener
            running = (preferences.phoneReach, host, port)
            problem = nil
            pairingURL = Self.url(host: Self.displayHost(reach: preferences.phoneReach, bound: host), port: port, token: token)
        } catch {
            problem = "Couldn't start the dashboard (\(error.localizedDescription))."
        }
    }

    func stop(keepProblem: Bool = false) {
        listener?.cancel()
        listener = nil
        running = nil
        pairingURL = nil
        actionLinks.removeAll()
        if !keepProblem { problem = nil }
    }

    /// The base address push notifications link to, without the token.
    var baseURL: URL? {
        guard let pairingURL, var parts = URLComponents(url: pairingURL, resolvingAgainstBaseURL: false) else { return nil }
        parts.fragment = nil
        return parts.url
    }

    /// A link that answers one approval once, for a notification button.
    func actionLink(for approval: UUID, _ answer: ApprovalCenter.Answer) -> URL? {
        guard let baseURL else { return nil }
        let nonce = Self.randomToken(bytes: 18)
        actionLinks[nonce] = (approval, answer)
        return baseURL.appendingPathComponent("a").appendingPathComponent(nonce)
    }

    nonisolated static func randomToken(bytes: Int = 24) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func url(host: String, port: UInt16, token: String) -> URL? {
        URL(string: "http://\(host.contains(":") ? "[\(host)]" : host):\(port)/#t=\(token)")
    }

    // MARK: Addresses

    /// The address to listen on: the Tailscale address, or nil for every interface.
    /// `TETHERA_PHONE_HOST` overrides it (development: `127.0.0.1`).
    static func bindHost(for reach: PhoneReach) -> String? {
        if let host = ProcessInfo.processInfo.environment["TETHERA_PHONE_HOST"] { return host }
        return reach == .tailscale ? tailscaleAddress() : nil
    }

    private static func displayHost(reach: PhoneReach, bound: String?) -> String {
        if let bound { return bound }
        return ProcessInfo.processInfo.hostName
    }

    /// This Mac's Tailscale IPv4 address (Tailscale hands out 100.64.0.0/10).
    static func tailscaleAddress() -> String? {
        ipv4Addresses().first { address in
            let parts = address.split(separator: ".").compactMap { Int($0) }
            return parts.count == 4 && parts[0] == 100 && (64...127).contains(parts[1])
        }
    }

    private static func ipv4Addresses() -> [String] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var result: [String] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let address = pointer.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  (Int32(pointer.pointee.ifa_flags) & IFF_UP) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                result.append(String(cString: host))
            }
        }
        return result
    }

    /// The pairing URL as a QR code to scan with the phone's camera.
    static func qrCode(for url: URL, size: CGFloat) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = (size / output.extent.width).rounded(.down)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: max(1, scale), y: max(1, scale)))
        let representation = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }

    // MARK: HTTP

    struct Request {
        var method: String
        var path: String
        var headers: [String: String]
        var body: Data
    }

    struct Response {
        var status: Int
        var type: String
        var body: Data

        static func json(_ object: Any, status: Int = 200) -> Response {
            Response(status: status, type: "application/json", body: (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data())
        }

        static func text(_ text: String, status: Int) -> Response {
            Response(status: status, type: "text/plain; charset=utf-8", body: Data(text.utf8))
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        Self.read(connection, buffer: Data()) { [weak self] request in
            Task { @MainActor in
                let response = request.map { self?.route($0) ?? .text("Gone", status: 503) } ?? .text("Bad request", status: 400)
                Self.write(response, to: connection)
            }
        }
    }

    /// Reads one request: headers up to 16 KB, a body up to 64 KB.
    private nonisolated static func read(_ connection: NWConnection, buffer: Data, done: @escaping @Sendable (Request?) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, complete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = parse(buffer) {
                done(request)
            } else if complete || error != nil || buffer.count > 80_000 {
                done(nil)
            } else {
                read(connection, buffer: buffer, done: done)
            }
        }
    }

    /// A complete request, or nil while more bytes are needed.
    nonisolated static func parse(_ data: Data) -> Request? {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)), end.lowerBound < 16_384 else { return nil }
        let head = String(decoding: data[data.startIndex..<end.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let start = lines.removeFirst().split(separator: " ")
        guard start.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = min(Int(headers["content-length"] ?? "0") ?? 0, 65_536)
        let body = data[end.upperBound...]
        guard body.count >= length else { return nil }
        return Request(method: String(start[0]), path: String(start[1]), headers: headers, body: Data(body.prefix(length)))
    }

    private nonisolated static func write(_ response: Response, to connection: NWConnection) {
        let reason = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 409: "Conflict", 503: "Service Unavailable"][response.status] ?? "OK"
        let head = "HTTP/1.1 \(response.status) \(reason)\r\nContent-Type: \(response.type)\r\nContent-Length: \(response.body.count)\r\n"
            + "Cache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + response.body, completion: .contentProcessed { _ in connection.cancel() })
    }

    func route(_ request: Request) -> Response {
        let path = request.path.split(separator: "?").first.map(String.init) ?? "/"
        let parts = path.split(separator: "/").map(String.init)
        switch (request.method, parts.first) {
        case ("GET", nil):
            return Response(status: 200, type: "text/html; charset=utf-8", body: Data(PhoneDashboard.html.utf8))
        case ("GET", "manifest.webmanifest"):
            return Response(status: 200, type: "application/manifest+json", body: Data(PhoneDashboard.manifest.utf8))
        case ("GET", "icon.png"):
            return Response(status: 200, type: "image/png", body: PhoneDashboard.icon)
        case ("POST", "a") where parts.count == 2:
            guard let action = actionLinks.removeValue(forKey: parts[1]) else { return .text("That link was already used or has expired.", status: 404) }
            guard ApprovalCenter.shared.pending.contains(where: { $0.id == action.approval }) else { return .text("Already answered.", status: 409) }
            ApprovalCenter.shared.answer(action.approval, action.answer, from: "phone")
            return .text(action.answer == .allow ? "Allowed." : "Denied.", status: 200)
        default:
            break
        }
        guard parts.first == "api" else { return .text("Not found", status: 404) }
        guard authorized(request) else { return .text("Pair this phone again from Tethera's Settings → Remote.", status: 401) }
        switch (request.method, Array(parts.dropFirst())) {
        case ("GET", ["state"]):
            return .json(PhoneDashboard.state())
        case ("POST", let rest) where rest.count == 3 && rest[0] == "approvals":
            guard let id = UUID(uuidString: rest[1]), let answer = ApprovalCenter.Answer(rawValue: rest[2]), answer != .terminal,
                  ApprovalCenter.shared.pending.contains(where: { $0.id == id }) else { return .text("Already answered.", status: 409) }
            ApprovalCenter.shared.answer(id, answer, from: "phone")
            return .json(["ok": true])
        case ("POST", let rest) where rest.count == 3 && rest[0] == "sessions" && rest[2] == "reply":
            // Only an agent asking a question takes an answer: not a shell, and not a permission
            // prompt, which Allow and Deny answer.
            guard let id = UUID(uuidString: rest[1]), let session = DaemonClient.shared.session(id), Self.takesReplies(session),
                  let text = (try? JSONSerialization.jsonObject(with: request.body) as? [String: Any])?["text"] as? String,
                  !text.isEmpty, text.count <= 4000 else { return .text("That session isn't waiting for an answer.", status: 409) }
            DaemonClient.shared.send(id, Data((text.replacingOccurrences(of: "\n", with: " ") + "\r").utf8))
            return .json(["ok": true])
        default:
            return .text("Not found", status: 404)
        }
    }

    static func takesReplies(_ session: SessionInfo) -> Bool {
        session.agent?.state == .needsInput && session.agent?.reason != "permission"
    }

    private func authorized(_ request: Request) -> Bool {
        guard let token = PreferencesStore.shared.value.phoneToken,
              let header = request.headers["authorization"], header.hasPrefix("Bearer ") else { return false }
        let given = Array(header.dropFirst(7).utf8), expected = Array(token.utf8)
        guard given.count == expected.count else { return false }
        return zip(given, expected).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
