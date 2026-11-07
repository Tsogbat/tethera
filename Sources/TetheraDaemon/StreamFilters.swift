import Foundation

/// Removes terminal *queries* from output before it goes to clients.
///
/// The daemon's emulator is the terminal of record and answers every query itself (device
/// attributes, cursor position, mode reports, colors, the OSC 7501 probe…). Clients only render;
/// if they saw the queries too, each would answer and the program would read duplicate replies
/// as typed input. Everything else passes through untouched, including sequences split across reads.
struct QueryFilter {
    private enum State {
        case ground
        case escape
        case csi
        case osc
        case oscEscape
        case dcsHead
        case dcsBody
        case dcsEscape
        case passString      // a long OSC/DCS we already emitted; pass bytes until its terminator
        case passStringEscape
    }

    private var state = State.ground
    private var pending: [UInt8] = []
    private static let maxPending = 4_096

    mutating func filter(_ input: [UInt8]) -> [UInt8] {
        if state == .ground, !input.contains(0x1b) { return input }
        var out: [UInt8] = []
        out.reserveCapacity(input.count)
        for byte in input {
            switch state {
            case .ground:
                if byte == 0x1b { pending = [byte]; state = .escape } else { out.append(byte) }
            case .escape:
                pending.append(byte)
                switch byte {
                case UInt8(ascii: "["): state = .csi
                case UInt8(ascii: "]"): state = .osc
                case UInt8(ascii: "P"): state = .dcsHead
                case 0x1b: pending = [byte] // ESC ESC: emit the first, restart
                    out.append(0x1b)
                default: flush(into: &out)
                }
            case .csi:
                pending.append(byte)
                if (0x40...0x7e).contains(byte) {
                    if Self.isQueryCSI(pending) { pending.removeAll() } else { out.append(contentsOf: pending); pending.removeAll() }
                    state = .ground
                } else if !(0x20...0x3f).contains(byte) || pending.count > 64 {
                    flush(into: &out)
                }
            case .osc:
                if byte == 0x07 { finishOSC(into: &out, terminator: [0x07]) }
                else if byte == 0x1b { state = .oscEscape }
                else { pending.append(byte); overflowString(into: &out) }
            case .oscEscape:
                if byte == UInt8(ascii: "\\") { finishOSC(into: &out, terminator: [0x1b, 0x5c]) }
                else { pending.append(0x1b); pending.append(byte); state = .osc; overflowString(into: &out) }
            case .dcsHead:
                pending.append(byte)
                // DECRQSS (`DCS $ q`) and XTGETTCAP (`DCS + q`) are queries; anything else (sixel…) passes.
                if pending.count == 4 {
                    let head = Array(pending[2...3])
                    if head == Array("$q".utf8) || head == Array("+q".utf8) { state = .dcsBody } else { passThrough(into: &out) }
                }
            case .dcsBody:
                if byte == 0x1b { state = .dcsEscape } else { pending.append(byte); if pending.count > 512 { passThrough(into: &out) } }
            case .dcsEscape:
                if byte == UInt8(ascii: "\\") { pending.removeAll(); state = .ground }
                else { pending.append(0x1b); pending.append(byte); state = .dcsBody }
            case .passString:
                out.append(byte)
                if byte == 0x07 { state = .ground } else if byte == 0x1b { state = .passStringEscape }
            case .passStringEscape:
                out.append(byte)
                state = byte == UInt8(ascii: "\\") ? .ground : .passString
            }
        }
        return out
    }

    private mutating func flush(into out: inout [UInt8]) {
        out.append(contentsOf: pending)
        pending.removeAll()
        state = .ground
    }

    private mutating func finishOSC(into out: inout [UInt8], terminator: [UInt8]) {
        if !Self.isQueryOSC(body: pending.dropFirst(2)) {
            out.append(contentsOf: pending)
            out.append(contentsOf: terminator)
        }
        pending.removeAll()
        state = .ground
    }

    /// Long strings (titles, clipboard payloads) are never queries: stop buffering.
    private mutating func overflowString(into out: inout [UInt8]) {
        if pending.count > Self.maxPending { passThrough(into: &out) }
    }

    private mutating func passThrough(into out: inout [UInt8]) {
        out.append(contentsOf: pending)
        pending.removeAll()
        state = .passString
    }

    /// `pending` holds `ESC [ params intermediates final`.
    static func isQueryCSI(_ sequence: [UInt8]) -> Bool {
        guard sequence.count >= 3, let final = sequence.last else { return false }
        let body = sequence[2..<(sequence.count - 1)]
        let prefix = body.first.flatMap { (0x3c...0x3f).contains($0) ? $0 : nil }
        let intermediates = body.filter { (0x20...0x2f).contains($0) }
        let params = String(decoding: body.filter { (0x30...0x3b).contains($0) }, as: UTF8.self)
        switch final {
        case UInt8(ascii: "c"):           // DA1, DA2 (>), DA3 (=)
            return intermediates.isEmpty
        case UInt8(ascii: "n"):           // DSR / DECDSR reports
            return intermediates.isEmpty
        case UInt8(ascii: "p"):           // DECRQM: CSI Ps $ p / CSI ? Ps $ p
            return intermediates == [UInt8(ascii: "$")]
        case UInt8(ascii: "q"):           // XTVERSION: CSI > q (DECSCUSR has a space intermediate)
            return prefix == UInt8(ascii: ">") && intermediates.isEmpty
        case UInt8(ascii: "u"):           // kitty keyboard query: CSI ? u
            return prefix == UInt8(ascii: "?") && intermediates.isEmpty && params.isEmpty
        case UInt8(ascii: "t"):           // XTWINOPS reports (11, 13–21); 22/23 and resizes pass
            guard prefix == nil, let first = params.split(separator: ";").first.flatMap({ Int($0) }) else { return false }
            return [11, 13, 14, 15, 16, 18, 19, 20, 21].contains(first)
        case UInt8(ascii: "x"):           // DECREQTPARM
            return intermediates.isEmpty && prefix == nil
        default:
            return false
        }
    }

    /// Color, clipboard and program-status queries end their last field with `?`.
    static func isQueryOSC(body: ArraySlice<UInt8>) -> Bool {
        let text = String(decoding: body, as: UTF8.self)
        let fields = text.split(separator: ";", omittingEmptySubsequences: false)
        guard let code = fields.first.flatMap({ Int($0) }) else { return false }
        if code == 7501 { return fields.count >= 2 && fields[1].hasPrefix("?") }
        let queryable: Set<Int> = [4, 5, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 52]
        return queryable.contains(code) && fields.last == "?"
    }
}

/// Spots OSC 133 prompt marks in output: prompt shown, command running, exit code.
struct PromptScanner {
    enum Event: Equatable {
        case promptStart
        case commandStart
        case commandEnd(exitCode: Int32?)
    }

    private enum State { case ground, escape, osc, oscEscape }
    private var state = State.ground
    private var body: [UInt8] = []

    mutating func scan(_ input: [UInt8]) -> [Event] {
        var events: [Event] = []
        for byte in input {
            switch state {
            case .ground:
                if byte == 0x1b { state = .escape }
            case .escape:
                if byte == UInt8(ascii: "]") { body.removeAll(keepingCapacity: true); state = .osc } else { state = byte == 0x1b ? .escape : .ground }
            case .osc:
                if byte == 0x07 { finish(&events) }
                else if byte == 0x1b { state = .oscEscape }
                else if body.count < 64 { body.append(byte) }
                else { state = .ground } // too long to be a prompt mark
            case .oscEscape:
                if byte == UInt8(ascii: "\\") { finish(&events) } else { state = .ground }
            }
        }
        return events
    }

    private mutating func finish(_ events: inout [Event]) {
        state = .ground
        let text = String(decoding: body, as: UTF8.self)
        guard text.hasPrefix("133;") else { return }
        let parts = text.dropFirst(4).split(separator: ";")
        switch parts.first {
        case "A": events.append(.promptStart)
        case "C": events.append(.commandStart)
        case "D": events.append(.commandEnd(exitCode: parts.count > 1 ? Int32(parts[1]) : nil))
        default: break
        }
    }
}
