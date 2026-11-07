import Foundation

/// Where the daemon keeps its socket and saved sessions.
///
/// `TETHERA_HOME` overrides the location (tests, side-by-side dev builds). The socket path must
/// stay under the 104-byte `sun_path` limit.
public enum TetheraPaths {
    public static var home: URL {
        if let override = ProcessInfo.processInfo.environment["TETHERA_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tethera", isDirectory: true)
    }

    public static var socket: URL { home.appendingPathComponent("d.sock") }
    public static var lock: URL { home.appendingPathComponent("d.lock") }
    public static var log: URL { home.appendingPathComponent("daemon.log") }
    public static var state: URL { home.appendingPathComponent("sessions.json") }
    public static var snapshots: URL { home.appendingPathComponent("snapshots", isDirectory: true) }
    public static var shellIntegration: URL { home.appendingPathComponent("shell", isDirectory: true) }

    /// Creates the directory with owner-only permissions.
    public static func prepare() throws {
        let fm = FileManager.default
        for dir in [home, snapshots, shellIntegration] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }
}
