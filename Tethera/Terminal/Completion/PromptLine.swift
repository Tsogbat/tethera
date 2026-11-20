import Foundation

/// What's been typed at the current shell prompt, followed from the shell's prompt marks
/// (OSC 133;A when a fresh prompt appears, ;C when a command starts) and the keys sent to it.
/// Nil whenever it can't be known for sure: a command is running, or the line was edited
/// with keys this doesn't follow (arrows, Tab, history, pastes). Suggestions only show when
/// it's known.
struct PromptLine: Equatable {
    private(set) var text: String?
    /// The tail of the last output chunk, in case a mark was split across chunks.
    private var carry: [UInt8] = []

    /// Reads prompt marks from shell output.
    mutating func output(_ bytes: Data) {
        let marker: [UInt8] = [0x1B, 0x5D, 0x31, 0x33, 0x33, 0x3B]  // ESC ] 1 3 3 ;
        var scan = carry
        scan.append(contentsOf: bytes)
        var index = 0
        while index + marker.count < scan.count {
            if scan[index] == 0x1B, Array(scan[index..<index + marker.count]) == marker {
                switch scan[index + marker.count] {
                case UInt8(ascii: "A"): text = ""
                case UInt8(ascii: "C"): text = nil
                default: break
                }
                index += marker.count
            } else {
                index += 1
            }
        }
        carry = Array(scan.suffix(marker.count))
    }

    /// Follows keys sent to the shell; returns the command line when Return submits it.
    mutating func input(_ bytes: Data) -> String? {
        for scalar in String(decoding: bytes, as: UTF8.self).unicodeScalars {
            switch scalar.value {
            case 0x0D, 0x0A:
                let submitted = text
                text = nil
                return submitted
            case 0x7F, 0x08:
                if text != nil, !text!.isEmpty { text!.removeLast() }
            case 0x15, 0x03:  // ⌃U clears the line; ⌃C abandons it for a new prompt
                if text != nil { text = "" }
            case 0x17:  // ⌃W deletes the word before the cursor
                if var line = text {
                    while line.last == " " { line.removeLast() }
                    while let last = line.last, last != " " { line.removeLast() }
                    text = line
                }
            case 0..<0x20, 0x1B:
                text = nil
            default:
                text?.unicodeScalars.append(scalar)
            }
        }
        return nil
    }

    /// Forget everything: the screen was replaced (a reattach) and the line is unknown.
    mutating func reset() {
        text = nil
        carry = []
    }
}
