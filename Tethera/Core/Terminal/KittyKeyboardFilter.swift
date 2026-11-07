import Foundation

/// Drops kitty keyboard-protocol sequences (`CSI ? u`, `CSI > flags u`, `CSI < n u`,
/// `CSI = flags ; mode u`) before they reach SwiftTerm.
///
/// SwiftTerm treats every `CSI … u` as "restore cursor", ignoring the private marker, so the
/// query Claude Code / Codex / OpenCode send at startup teleports the cursor to the last saved
/// position and their relative redraws land on the wrong rows. Without a reply, apps fall back
/// to legacy key encoding, which is what we want. Sequences may be split across reads.
struct KittyKeyboardFilter {
    private enum State {
        case ground
        case escape        // saw ESC
        case csi           // saw ESC [
        case kitty         // saw ESC [ and a private marker
    }

    private var state = State.ground
    private var pending: [UInt8] = []
    private static let maxPending = 32

    mutating func filter(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        // Fast path: nothing pending and no escape bytes in this chunk.
        if state == .ground, !bytes.contains(0x1b) {
            return Array(bytes)
        }
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count + pending.count)
        for byte in bytes {
            switch state {
            case .ground:
                if byte == 0x1b {
                    pending = [byte]
                    state = .escape
                } else {
                    out.append(byte)
                }
            case .escape:
                if byte == UInt8(ascii: "[") {
                    pending.append(byte)
                    state = .csi
                } else {
                    flush(into: &out, then: byte)
                }
            case .csi:
                if byte == UInt8(ascii: "?") || byte == UInt8(ascii: ">") || byte == UInt8(ascii: "<") || byte == UInt8(ascii: "=") {
                    pending.append(byte)
                    state = .kitty
                } else {
                    flush(into: &out, then: byte)
                }
            case .kitty:
                if byte == UInt8(ascii: "u") {
                    pending.removeAll()
                    state = .ground
                } else if (0x30...0x3b).contains(byte), pending.count < Self.maxPending {
                    pending.append(byte)  // digits, ':' and ';'
                } else {
                    flush(into: &out, then: byte)
                }
            }
        }
        return out
    }

    /// Emits the held-back prefix unchanged, then reprocesses `byte` from the ground state.
    private mutating func flush(into out: inout [UInt8], then byte: UInt8) {
        out.append(contentsOf: pending)
        pending.removeAll()
        state = .ground
        if byte == 0x1b {
            pending = [byte]
            state = .escape
        } else {
            out.append(byte)
        }
    }

    mutating func reset() {
        state = .ground
        pending.removeAll()
    }
}
