import Foundation

/// Where the app keeps its own state (preferences, layout, recent folders, browser tabs).
/// A custom `TETHERA_HOME` (tests, scripted captures, side-by-side builds) gets its own store,
/// so it never touches the layout or settings of the Tethera you use.
enum AppDefaults {
    static let store: UserDefaults = {
        if let home = ProcessInfo.processInfo.environment["TETHERA_HOME"], !home.isEmpty,
           let isolated = UserDefaults(suiteName: "com.tethera.isolated." + stableHash(home)) {
            return isolated
        }
        return .standard
    }()

    /// FNV-1a; `hashValue` changes from launch to launch.
    private static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 36)
    }
}
