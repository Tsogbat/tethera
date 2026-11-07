import Foundation

/// One message on the daemon socket.
///
/// Layout: `[u32 big-endian length][u8 kind][payload]`, where length counts the kind byte and
/// the payload. Terminal bytes travel as binary frames so large output never goes through JSON.
public enum Frame: Equatable, Sendable {
    /// A JSON-encoded `ControlMessage`.
    case control(Data)
    /// Program output for a session, numbered so a client can tell what it has seen.
    case output(session: UUID, seq: UInt64, bytes: Data)
    /// The VT snapshot sent on attach; output frames after it continue from `seq`.
    case snapshot(session: UUID, seq: UInt64, bytes: Data)
    /// Keyboard input or paste for a session.
    case input(session: UUID, bytes: Data)

    enum Kind: UInt8 {
        case control = 1
        case output = 2
        case snapshot = 3
        case input = 4
    }

    public static let maxFrameSize = 64 * 1024 * 1024

    public func encoded() -> Data {
        var payload = Data()
        let kind: Kind
        switch self {
        case .control(let json):
            kind = .control
            payload = json
        case .output(let session, let seq, let bytes):
            kind = .output
            payload.append(session.wireBytes)
            payload.append(seq.bigEndianData)
            payload.append(bytes)
        case .snapshot(let session, let seq, let bytes):
            kind = .snapshot
            payload.append(session.wireBytes)
            payload.append(seq.bigEndianData)
            payload.append(bytes)
        case .input(let session, let bytes):
            kind = .input
            payload.append(session.wireBytes)
            payload.append(bytes)
        }
        var data = Data(capacity: payload.count + 5)
        data.append(UInt32(payload.count + 1).bigEndianData)
        data.append(kind.rawValue)
        data.append(payload)
        return data
    }

    public static func control(_ message: ControlMessage) -> Frame {
        .control((try? ControlMessage.encoder.encode(message)) ?? Data("{}".utf8))
    }

    /// The decoded control message, if this is a control frame.
    public var controlMessage: ControlMessage? {
        guard case .control(let json) = self else { return nil }
        return try? ControlMessage.decoder.decode(ControlMessage.self, from: json)
    }
}

public enum WireError: Error, Equatable {
    case frameTooLarge(Int)
    case malformed
}

/// Turns a byte stream into frames, keeping partial frames between reads.
public struct FrameDecoder: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) throws -> [Frame] {
        buffer.append(data)
        var frames: [Frame] = []
        while buffer.count >= 4 {
            let start = buffer.startIndex
            let length = Int(UInt32(bigEndianBytes: buffer[start..<start + 4]))
            guard length >= 1, length <= Frame.maxFrameSize else { throw WireError.frameTooLarge(length) }
            guard buffer.count >= 4 + length else { break }
            let body = buffer[(start + 4)..<(start + 4 + length)]
            frames.append(try Self.decode(body))
            buffer.removeSubrange(start..<(start + 4 + length))
        }
        if buffer.isEmpty { buffer = Data() } // drop the grown backing store
        return frames
    }

    private static func decode(_ body: Data) throws -> Frame {
        let start = body.startIndex
        guard let kind = Frame.Kind(rawValue: body[start]) else { throw WireError.malformed }
        let payload = body[(start + 1)...]
        switch kind {
        case .control:
            return .control(Data(payload))
        case .output, .snapshot:
            guard payload.count >= 24 else { throw WireError.malformed }
            let p = payload.startIndex
            let session = UUID(wireBytes: payload[p..<p + 16])
            let seq = UInt64(bigEndianBytes: payload[(p + 16)..<(p + 24)])
            let bytes = Data(payload[(p + 24)...])
            return kind == .output ? .output(session: session, seq: seq, bytes: bytes)
                                   : .snapshot(session: session, seq: seq, bytes: bytes)
        case .input:
            guard payload.count >= 16 else { throw WireError.malformed }
            let p = payload.startIndex
            return .input(session: UUID(wireBytes: payload[p..<p + 16]), bytes: Data(payload[(p + 16)...]))
        }
    }
}

// MARK: - Byte helpers

extension UUID {
    var wireBytes: Data {
        withUnsafeBytes(of: uuid) { Data($0) }
    }

    init(wireBytes: Data) {
        var raw: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &raw) { $0.copyBytes(from: wireBytes.prefix(16)) }
        self.init(uuid: raw)
    }
}

extension FixedWidthInteger {
    var bigEndianData: Data {
        withUnsafeBytes(of: bigEndian) { Data($0) }
    }

    init(bigEndianBytes bytes: Data) {
        var value: Self = 0
        for byte in bytes { value = (value << 8) | Self(byte) }
        self = value
    }
}
