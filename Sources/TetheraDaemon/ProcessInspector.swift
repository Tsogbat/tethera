import Darwin
import Foundation

/// Reads what is running in the foreground of a PTY.
enum ProcessInspector {
    struct Foreground: Equatable {
        let pid: pid_t
        let executable: String
        let arguments: [String]

        var name: String { (executable as NSString).lastPathComponent }
    }

    /// The leader of the terminal's foreground process group.
    static func foreground(masterFD: Int32) -> Foreground? {
        let group = tcgetpgrp(masterFD)
        guard group > 0 else { return nil }
        let arguments = Self.arguments(of: group) ?? []
        guard let executable = path(of: group) ?? arguments.first else { return nil }
        return Foreground(pid: group, executable: executable, arguments: Array(arguments.dropFirst()))
    }

    static func path(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    /// argv via `KERN_PROCARGS2`: argc, the exec path, padding, then argc NUL-terminated strings.
    static func arguments(of pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size && buffer[index] != 0 { index += 1 }   // exec path
        while index < size && buffer[index] == 0 { index += 1 }   // padding
        var arguments: [String] = []
        while arguments.count < argc && index < size {
            let start = index
            while index < size && buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }
}
