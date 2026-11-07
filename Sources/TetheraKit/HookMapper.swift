import Foundation

/// What an agent hook or status-line payload tells us about the agent.
public struct AgentUpdate: Equatable, Sendable {
    public var kind: AgentKind
    public var state: AgentState?
    /// permission, question or auth when `state` is `.needsInput`.
    public var reason: String?
    public var message: String?
    /// The tool in use; an empty string clears it.
    public var tool: String?
    public var model: String?
    public var contextPercent: Double?
    public var costUSD: Double?

    public init(kind: AgentKind, state: AgentState? = nil) {
        self.kind = kind
        self.state = state
    }
}

/// Maps the JSON agents hand to their hooks (forwarded by `tethera hook <source>`) to updates.
/// Sources: `claude`, `claude-statusline`, `codex`, `codex-notify`, `agy`, `agy-status`,
/// `hermes`, `opencode`. Unknown events return nil; nothing here throws.
public enum HookMapper {
    public static func update(source: String, payload: Data) -> AgentUpdate? {
        guard let json = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else { return nil }
        switch source {
        case "claude": return claude(json)
        case "claude-statusline": return claudeStatusLine(json)
        case "codex": return codex(json)
        case "codex-notify": return codexNotify(json)
        case "agy": return antigravity(json)
        case "agy-status": return antigravityStatus(json)
        case "hermes": return hermes(json)
        case "opencode": return opencode(json)
        default: return nil
        }
    }

    // MARK: Claude Code

    private static func claude(_ json: [String: Any]) -> AgentUpdate? {
        var update = AgentUpdate(kind: .claude)
        switch json.string("hook_event_name") {
        case "UserPromptSubmit":
            update.state = .working
            update.message = json.string("prompt").map { clip($0) }
            update.tool = ""
        case "PreToolUse":
            update.state = .working
            update.tool = describeTool(json)
        case "PostToolUse", "PostToolUseFailure":
            return nil
        case "PermissionRequest":
            update.state = .needsInput
            update.reason = "permission"
            update.message = describeTool(json).map { "Allow \($0)?" }
        case "Notification":
            switch json.string("notification_type") {
            case "permission_prompt":
                update.state = .needsInput
                update.reason = "permission"
            case "elicitation_dialog", "agent_needs_input":
                update.state = .needsInput
                update.reason = "question"
            case "idle_prompt":
                update.state = .idle
            default:
                break
            }
            update.message = json.string("message").map { clip($0) }
            if update.state == nil && update.message == nil { return nil }
        case "Stop":
            update.state = .done
            update.message = json.string("last_assistant_message").map { clip($0) }
            update.tool = ""
        case "StopFailure":
            update.state = .error
            update.message = json.string("error") ?? json.string("matcher") ?? json.string("reason") ?? "Stopped with an error"
        case "SessionStart", "SessionEnd":
            update.state = .idle
            update.tool = ""
        default:
            return nil
        }
        return update
    }

    private static func claudeStatusLine(_ json: [String: Any]) -> AgentUpdate? {
        var update = AgentUpdate(kind: .claude)
        update.model = (json["model"] as? [String: Any])?.string("display_name")
        update.contextPercent = (json["context_window"] as? [String: Any])?.number("used_percentage")
        update.costUSD = (json["cost"] as? [String: Any])?.number("total_cost_usd")
        return update.model == nil && update.contextPercent == nil && update.costUSD == nil ? nil : update
    }

    // MARK: Codex

    private static func codex(_ json: [String: Any]) -> AgentUpdate? {
        var update = AgentUpdate(kind: .codex)
        update.model = json.string("model")
        switch json.string("hook_event_name") {
        case "UserPromptSubmit":
            update.state = .working
            update.message = json.string("prompt").map { clip($0) }
            update.tool = ""
        case "PreToolUse":
            update.state = .working
            update.tool = describeTool(json)
        case "PostToolUse":
            update.state = .working
        case "PermissionRequest":
            update.state = .needsInput
            update.reason = "permission"
            update.message = describeTool(json).map { "Allow \($0)?" }
        case "Stop":
            update.state = .done
            update.message = json.string("last_assistant_message").map { clip($0) }
            update.tool = ""
        case "Interrupt", "SessionStart", "SessionEnd":
            update.state = .idle
            update.tool = ""
        default:
            return nil
        }
        return update
    }

    private static func codexNotify(_ json: [String: Any]) -> AgentUpdate? {
        guard json.string("type") == "agent-turn-complete" else { return nil }
        var update = AgentUpdate(kind: .codex, state: .done)
        update.message = json.string("last-assistant-message").map { clip($0) }
        update.tool = ""
        return update
    }

    // MARK: Antigravity

    private static func antigravity(_ json: [String: Any]) -> AgentUpdate? {
        var update = AgentUpdate(kind: .antigravity)
        update.model = json.string("modelName")
        switch json.string("hook_event_name") ?? json.string("hookEventName") {
        case "PreInvocation":
            update.state = .working
            update.message = json.string("lastUserInput").map { clip($0) }
        case "PreToolUse":
            update.state = .working
            update.tool = (json["toolCall"] as? [String: Any])?.string("name") ?? json.string("toolName")
        case "PostToolUse", "PostInvocation":
            return nil
        case "Stop":
            if let error = json.string("error"), !error.isEmpty {
                update.state = .error
                update.message = clip(error)
            } else {
                update.state = .done
            }
            update.tool = ""
        case "SessionStart":
            update.state = .idle
        default:
            return nil
        }
        return update
    }

    private static func antigravityStatus(_ json: [String: Any]) -> AgentUpdate? {
        var update = AgentUpdate(kind: .antigravity)
        if json.bool("tool_confirmation_pending") == true {
            update.state = .needsInput
            update.reason = "permission"
        } else {
            switch json.string("agent_state") {
            case "idle": update.state = .idle
            case "working", "tool_use", "reviewing", "initializing": update.state = .working
            case "authenticating":
                update.state = .needsInput
                update.reason = "auth"
            case "error": update.state = .error
            default: break
            }
        }
        update.costUSD = (json["cost"] as? [String: Any])?.number("total_usd")
        update.contextPercent = (json["context_window"] as? [String: Any])?.number("used_percentage")
        update.model = (json["model"] as? [String: Any])?.string("display_name") ?? json.string("model")
        return update
    }

    // MARK: Hermes

    private static func hermes(_ json: [String: Any]) -> AgentUpdate? {
        var update = AgentUpdate(kind: .hermes)
        switch json.string("hook_event_name") {
        case "pre_llm_call", "post_llm_call":
            update.state = .working
        case "pre_tool_call":
            update.state = .working
            update.tool = describeTool(json)
        case "post_tool_call":
            return nil
        case "pre_approval_request":
            update.state = .needsInput
            update.reason = "permission"
            let extra = json["extra"] as? [String: Any] ?? [:]
            update.message = (extra.string("description") ?? extra.string("command")).map { "Allow \(clip($0, to: 80))?" }
        case "on_session_start":
            update.state = .idle
        case "on_session_end":
            let extra = json["extra"] as? [String: Any] ?? json
            if extra.bool("failed") == true || extra.string("turn_exit_reason") == "failed" {
                update.state = .error
            } else if extra.bool("interrupted") == true {
                update.state = .idle
            } else {
                update.state = .done
            }
            update.tool = ""
        default:
            return nil
        }
        return update
    }

    // MARK: OpenCode (payload shaped by Tethera's own plugin)

    private static func opencode(_ json: [String: Any]) -> AgentUpdate? {
        var update = AgentUpdate(kind: .opencode)
        let properties = json["properties"] as? [String: Any] ?? [:]
        switch json.string("type") {
        case "session.status":
            let status = (properties["status"] as? [String: Any])?.string("type")
            update.state = status == "busy" || status == "retry" ? .working : .done
            if status == "idle" { update.tool = "" }
        case "session.idle":
            update.state = .done
            update.tool = ""
        case "permission.asked", "permission.updated":
            update.state = .needsInput
            update.reason = "permission"
            let what = properties.string("permission") ?? properties.string("title") ?? properties.string("type")
            let patterns = (properties["patterns"] as? [String])?.joined(separator: " ")
            update.message = what.map { "Allow \($0)\(patterns.map { " " + clip($0, to: 60) } ?? "")?" }
        case "question.asked":
            update.state = .needsInput
            update.reason = "question"
        case "permission.replied", "question.replied", "question.rejected":
            update.state = .working
        case "session.error":
            update.state = .error
            update.message = (properties["error"] as? [String: Any])?.string("name") ?? "Error"
        case "tool.execute.before":
            update.state = .working
            update.tool = json.string("tool")
        default:
            return nil
        }
        return update
    }

    // MARK: Helpers

    /// "Bash: npm test", "Edit Package.swift", or the tool name.
    static func describeTool(_ json: [String: Any]) -> String? {
        guard let name = json.string("tool_name") ?? json.string("tool") else { return nil }
        let input = json["tool_input"] as? [String: Any] ?? json["args"] as? [String: Any] ?? [:]
        if let command = input.string("command") ?? (input["command"] as? [String])?.joined(separator: " ") {
            return "\(name): \(clip(command, to: 80))"
        }
        if let path = input.string("file_path") ?? input.string("path") ?? input.string("filePath") {
            return "\(name) \((path as NSString).lastPathComponent)"
        }
        if let pattern = input.string("pattern") ?? input.string("query") ?? input.string("url") {
            return "\(name) \(clip(pattern, to: 60))"
        }
        return name
    }

    static func clip(_ text: String, to limit: Int = 160) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return flat.count > limit ? String(flat.prefix(limit - 1)) + "…" : flat
    }
}

private extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? {
        (self[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    func number(_ key: String) -> Double? {
        (self[key] as? NSNumber)?.doubleValue ?? (self[key] as? String).flatMap(Double.init)
    }

    func bool(_ key: String) -> Bool? {
        self[key] as? Bool
    }
}
