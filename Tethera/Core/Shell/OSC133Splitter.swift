import Foundation

/// Splits the raw PTY byte stream into semantic shell events (OSC 133 / OSC 7)
/// and contiguous byte runs tagged with the region they belong to.
///
/// Only the sequences Tethera understands are consumed; every other escape sequence
/// is passed through untouched so the terminal emulator still sees it.
struct OSC133Splitter {
    enum Region: Equatable {
        case startup   // before the first prompt (rc file noise)
        case prompt    // after 133;A — the shell is drawing its prompt / echoing input
        case input     // after 133;B — the command line was accepted
        case output    // after 133;C — command output
        case idle      // after 133;D
    }

    enum Event: Equatable {
        case bytes(Region, [UInt8])
        case promptStart
        case commandStart
        case outputStart
        case commandEnd(exitCode: Int32?)
        case workingDirectory(String)
        case bracketedPaste(Bool)
        case notification(String)
    }

    private enum State {
        case ground, escape, csi
        case oscCode, oscBody, oscBodyEscape
        case oscPass, oscPassEscape
    }

    private(set) var region: Region = .startup
    private var state: State = .ground
    private var run: [UInt8] = []
    private var events: [Event] = []
    private var oscCode: [UInt8] = []
    private var oscBody: [UInt8] = []
    private var csiParams: [UInt8] = []

    private static let maxOSCBody = 8192
    private static let consumedCodes: Set<Int> = [7, 9, 133, 777]
    private static let bracketedPasteParams = Array("?2004".utf8)

    mutating func feed<S: Sequence>(_ bytes: S) -> [Event] where S.Element == UInt8 {
        for byte in bytes {
            step(byte)
        }
        flushRun()
        let result = events
        events.removeAll(keepingCapacity: true)
        return result
    }

    private mutating func step(_ b: UInt8) {
        switch state {
        case .ground:
            if b == 0x1B {
                state = .escape
            } else {
                run.append(b)
            }

        case .escape:
            switch b {
            case 0x5D: // ]
                state = .oscCode
                oscCode.removeAll(keepingCapacity: true)
                oscBody.removeAll(keepingCapacity: true)
            case 0x5B: // [
                run.append(0x1B); run.append(b)
                csiParams.removeAll(keepingCapacity: true)
                state = .csi
            case 0x1B:
                run.append(0x1B) // lone ESC; the new one starts another sequence
            default:
                run.append(0x1B); run.append(b)
                state = .ground
            }

        case .csi:
            run.append(b)
            if b >= 0x40 && b <= 0x7E {
                if csiParams == Self.bracketedPasteParams && (b == 0x68 || b == 0x6C) {
                    emit(.bracketedPaste(b == 0x68))
                }
                state = .ground
            } else if csiParams.count < 16 {
                csiParams.append(b)
            }

        case .oscCode:
            if b >= 0x30 && b <= 0x39 && oscCode.count < 6 {
                oscCode.append(b)
            } else if b == 0x3B, let code = codeValue, Self.consumedCodes.contains(code) {
                state = .oscBody
            } else if b == 0x07, codeValue != nil {
                finishOSC()
            } else if b == 0x1B, codeValue != nil {
                state = .oscBodyEscape
            } else {
                // Not ours: replay what we swallowed and pass the rest through.
                run.append(0x1B); run.append(0x5D)
                run.append(contentsOf: oscCode)
                run.append(b)
                state = b == 0x07 ? .ground : (b == 0x1B ? .oscPassEscape : .oscPass)
            }

        case .oscBody:
            if b == 0x07 {
                finishOSC()
            } else if b == 0x1B {
                state = .oscBodyEscape
            } else if oscBody.count < Self.maxOSCBody {
                oscBody.append(b)
            }

        case .oscBodyEscape:
            finishOSC()
            if b != 0x5C { // not ST: the ESC started a new sequence
                state = .escape
                step(b)
            }

        case .oscPass:
            run.append(b)
            if b == 0x07 {
                state = .ground
            } else if b == 0x1B {
                state = .oscPassEscape
            }

        case .oscPassEscape:
            run.append(b)
            state = b == 0x5C ? .ground : .oscPass
        }
    }

    private var codeValue: Int? {
        guard !oscCode.isEmpty else { return nil }
        return Int(String(decoding: oscCode, as: UTF8.self))
    }

    private mutating func finishOSC() {
        state = .ground
        guard let code = codeValue else { return }
        let body = String(decoding: oscBody, as: UTF8.self)

        switch code {
        case 133:
            guard let marker = body.first else { return }
            switch marker {
            case "A":
                transition(to: .prompt, event: .promptStart)
            case "B":
                transition(to: .input, event: .commandStart)
            case "C":
                transition(to: .output, event: .outputStart)
            case "D":
                let parts = body.split(separator: ";", omittingEmptySubsequences: false)
                let exit = parts.count > 1 ? Int32(parts[1].trimmingCharacters(in: .whitespaces)) : nil
                transition(to: .idle, event: .commandEnd(exitCode: exit))
            default:
                break
            }
        case 7:
            if let path = Self.parseFileURL(body) {
                emit(.workingDirectory(path))
            }
        case 9:
            // iTerm2-style notification. "9;4;…" is ConEmu progress, not a message.
            if !body.hasPrefix("4;"), !body.isEmpty {
                emit(.notification(body))
            }
        case 777:
            // rxvt: notify;title;body
            let parts = body.split(separator: ";", maxSplits: 2).map(String.init)
            if parts.first == "notify" {
                emit(.notification(parts.dropFirst().joined(separator: ": ")))
            }
        default:
            break
        }
    }

    private mutating func transition(to newRegion: Region, event: Event) {
        flushRun()
        region = newRegion
        events.append(event)
    }

    private mutating func emit(_ event: Event) {
        flushRun()
        events.append(event)
    }

    private mutating func flushRun() {
        guard !run.isEmpty else { return }
        events.append(.bytes(region, run))
        run.removeAll(keepingCapacity: true)
    }

    /// `file://host/path` → `/path` (percent-decoded). Hostnames are ignored.
    static func parseFileURL(_ string: String) -> String? {
        guard string.hasPrefix("file://") else { return nil }
        let rest = string.dropFirst("file://".count)
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        let rawPath = String(rest[slash...])
        let path = rawPath.removingPercentEncoding ?? rawPath
        return path.isEmpty ? nil : path
    }
}
