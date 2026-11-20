import Foundation

/// What agents print to answer a permission request Tethera decided.
public enum ApprovalDecision {
    /// Claude Code's `PermissionRequest` hook output for "allow" or "deny"; nil for anything
    /// else, which leaves the question to Claude's own dialog.
    public static func claude(_ answer: String, message: String = "Denied from Tethera.") -> String? {
        let decision: [String: Any]
        switch answer {
        case "allow": decision = ["behavior": "allow"]
        case "deny": decision = ["behavior": "deny", "message": message]
        default: return nil
        }
        let output: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        return (try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) }
    }
}
