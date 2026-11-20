import Foundation
import TetheraKit

/// What a daemon hands to the next version of itself across `exec`. The process stays the
/// same, so the shells stay its children; the listening socket and every PTY stay open, and
/// each screen is replayed into a fresh emulator.
struct Handover: Codable {
    struct Live: Codable {
        var info: SessionInfo
        var fd: Int32
        var pid: Int32
        /// A VT snapshot of the screen, scrollback and modes.
        var screen: Data
        var seq: UInt64
    }

    /// The version handing over.
    var from: String
    var listenFD: Int32
    var lockFD: Int32
    var sessions: [Live]

    /// Only a `tethera` binary owned by this user (or root) may take over the daemon.
    static func isAcceptable(executable path: String) -> Bool {
        guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path),
              ["tethera", "tethera-cli"].contains((path as NSString).lastPathComponent),
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value else { return false }
        return owner == getuid() || owner == 0
    }

    static func setCloseOnExec(_ fd: Int32, _ on: Bool) {
        let flags = fcntl(fd, F_GETFD)
        guard flags >= 0 else { return }
        _ = fcntl(fd, F_SETFD, on ? flags | FD_CLOEXEC : flags & ~FD_CLOEXEC)
    }
}
