import Foundation

/// Tethera's own Claude Code status line: a format with placeholders, rendered from the JSON
/// Claude Code pipes to the status line command.
///
///     {model} · {context} · {cost} · {branch}
///
/// Placeholders with no value are dropped along with the separator before them.
public enum StatusLineFormat {
    public struct Segment: Identifiable, Hashable, Sendable {
        public let key: String
        public let label: String
        public let sample: String
        public var id: String { key }
    }

    public static let segments: [Segment] = [
        Segment(key: "model", label: "Model", sample: "Opus 5.5"),
        Segment(key: "context", label: "Context used", sample: "42%"),
        Segment(key: "cost", label: "Session cost", sample: "$0.31"),
        Segment(key: "branch", label: "Git branch", sample: "main"),
        Segment(key: "folder", label: "Folder", sample: "api"),
        Segment(key: "time", label: "Time", sample: "14:05"),
    ]

    public static let defaultFormat = "{model} · {context} · {cost} · {branch}"

    /// The values Claude Code's status line JSON provides (and the branch, looked up from the
    /// folder when `branch` is given).
    public static func values(from json: [String: Any], branch: String? = nil, now: Date = Date()) -> [String: String] {
        var values: [String: String] = [:]
        if let model = (json["model"] as? [String: Any])?["display_name"] as? String { values["model"] = model }
        if let used = ((json["context_window"] as? [String: Any])?["used_percentage"] as? NSNumber)?.doubleValue {
            values["context"] = "\(Int(used.rounded()))%"
        }
        if let cost = ((json["cost"] as? [String: Any])?["total_cost_usd"] as? NSNumber)?.doubleValue {
            values["cost"] = String(format: "$%.2f", cost)
        }
        let folder = (json["workspace"] as? [String: Any])?["current_dir"] as? String ?? json["cwd"] as? String
        if let folder { values["folder"] = (folder as NSString).lastPathComponent }
        if let branch, !branch.isEmpty { values["branch"] = branch }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        values["time"] = formatter.string(from: now)
        return values
    }

    /// Renders a format. A placeholder without a value disappears together with the text that
    /// joins it to the segment before it, so "{model} · {cost}" without a cost is just the model.
    public static func render(_ format: String, values: [String: String]) -> String {
        var output = ""
        var literal = ""
        var seenPlaceholder = false
        var hasValue = false
        var index = format.startIndex
        while index < format.endIndex {
            if format[index] == "{", let close = format[index...].firstIndex(of: "}") {
                let key = String(format[format.index(after: index)..<close])
                if let value = values[key], !value.isEmpty {
                    // Text before the first placeholder is a prefix and always shows; text after a
                    // segment joins it to this one.
                    if hasValue || !seenPlaceholder { output += literal }
                    output += value
                    hasValue = true
                }
                literal = ""
                seenPlaceholder = true
                index = format.index(after: close)
            } else {
                literal.append(format[index])
                index = format.index(after: index)
            }
        }
        if hasValue || !seenPlaceholder { output += literal }
        return output
    }
}
