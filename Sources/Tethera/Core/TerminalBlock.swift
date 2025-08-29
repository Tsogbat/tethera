import Foundation
import SwiftUI

struct TerminalBlock: Identifiable {
    let id = UUID()
    var input: String
    var output: String
    var timestamp: Date
    var workingDirectory: String?
    var success: Bool?
}

extension TerminalBlock {
    static var example: TerminalBlock {
        TerminalBlock(input: "ls -l", output: "total 0\ndrwxr-xr-x  2 user  staff  64 Aug 22 10:00 Documents", timestamp: Date(), workingDirectory: "/Users/user", success: true)
    }
}
