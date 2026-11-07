import Foundation
import TetheraKit

/// `tethera mcp`: a stdio MCP server that gives agents Tethera's browser. Each tool call is
/// passed to the app over `AppChannel`; the page opens in a pane beside the agent's session,
/// so you watch what it does.
enum MCPServer {
    static let protocolVersion = "2025-06-18"

    static func run(version: String) -> Never {
        var connection: AppChannel.Connection?
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty,
                  let message = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            let id = message["id"]
            let method = message["method"] as? String ?? ""
            let params = message["params"] as? [String: Any] ?? [:]
            // Notifications (no id) need no answer.
            guard let id else { continue }

            switch method {
            case "initialize":
                let requested = params["protocolVersion"] as? String
                respond(id, result: [
                    "protocolVersion": requested ?? protocolVersion,
                    "capabilities": ["tools": ["listChanged": false]],
                    "serverInfo": ["name": "tethera", "title": "Tethera browser", "version": version],
                    "instructions": "A real browser tab shown to the user in Tethera, next to your session. Use browser_navigate, then browser_snapshot to get element refs for browser_click and browser_type. Good for checking a local dev server (http://localhost:PORT) after you change code.",
                ])
            case "ping":
                respond(id, result: [:])
            case "tools/list":
                respond(id, result: ["tools": tools])
            case "tools/call":
                let name = params["name"] as? String ?? ""
                let arguments = params["arguments"] as? [String: Any] ?? [:]
                guard tools.contains(where: { $0["name"] as? String == name }) else {
                    respond(id, error: -32602, message: "Unknown tool \(name)")
                    continue
                }
                do {
                    if connection == nil { connection = try connect() }
                    let session = ProcessInfo.processInfo.environment["TETHERA_SESSION_ID"]
                    let response: AppChannel.Response
                    do {
                        response = try connection!.call(name, params: arguments, session: session)
                    } catch {
                        // The app may have restarted: one fresh try.
                        connection = try connect()
                        response = try connection!.call(name, params: arguments, session: session)
                    }
                    if let error = response.error {
                        respond(id, result: ["content": [["type": "text", "text": error]], "isError": true])
                    } else {
                        var content: [[String: Any]] = []
                        if let image = response.image { content.append(["type": "image", "data": image, "mimeType": "image/png"]) }
                        if let text = response.text { content.append(["type": "text", "text": text]) }
                        respond(id, result: ["content": content])
                    }
                } catch {
                    connection = nil
                    respond(id, result: ["content": [["type": "text", "text": error.localizedDescription]], "isError": true])
                }
            default:
                respond(id, error: -32601, message: "Method not found: \(method)")
            }
        }
        exit(0)
    }

    /// Connects to the app, opening Tethera first if it isn't running.
    static func connect() throws -> AppChannel.Connection {
        if let connection = try? AppChannel.Connection() { return connection }
        // A custom TETHERA_HOME is a development or test setup: never launch the installed app for it.
        if let home = ProcessInfo.processInfo.environment["TETHERA_HOME"], !home.isEmpty { throw AppChannel.Failure.notRunning }
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-g", "-b", "com.tethera.app"]
        try? open.run()
        open.waitUntilExit()
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if let connection = try? AppChannel.Connection() { return connection }
            usleep(200_000)
        }
        throw AppChannel.Failure.notRunning
    }

    private static func respond(_ id: Any, result: [String: Any]) {
        write(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private static func respond(_ id: Any, error code: Int, message: String) {
        write(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }

    private static func write(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }

    // MARK: Tools (Playwright MCP's names and arguments)

    private static func tool(_ name: String, _ description: String, _ properties: [String: [String: Any]] = [:],
                             required: [String] = [], readOnly: Bool = false) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": ["type": "object", "properties": properties, "required": required, "additionalProperties": false],
            "annotations": ["readOnlyHint": readOnly],
        ]
    }

    private static let element: [String: Any] = ["type": "string", "description": "Human-readable element description, for the user"]
    private static let ref: [String: Any] = ["type": "string", "description": "Exact element ref from the page snapshot, e.g. e12"]

    static let tools: [[String: Any]] = [
        tool("browser_navigate", "Open a URL in the Tethera browser tab beside your session.",
             ["url": ["type": "string", "description": "The URL, e.g. http://localhost:5173"]], required: ["url"]),
        tool("browser_navigate_back", "Go back to the previous page."),
        tool("browser_snapshot", "Accessibility snapshot of the page, with refs for elements you can act on. Better than a screenshot for acting.",
             readOnly: true),
        tool("browser_click", "Click an element.",
             ["element": element, "ref": ref, "doubleClick": ["type": "boolean", "description": "Double-click instead"]],
             required: ["element", "ref"]),
        tool("browser_type", "Type text into an editable element.",
             ["element": element, "ref": ref, "text": ["type": "string"], "submit": ["type": "boolean", "description": "Press Enter after"]],
             required: ["element", "ref", "text"]),
        tool("browser_press_key", "Press a key, e.g. Enter, Escape, ArrowDown or a character.",
             ["key": ["type": "string"]], required: ["key"]),
        tool("browser_wait_for", "Wait for text to appear or disappear, or for a number of seconds.",
             ["text": ["type": "string"], "textGone": ["type": "string"], "time": ["type": "number", "description": "Seconds"]]),
        tool("browser_take_screenshot", "A PNG screenshot of the visible page. You can't act on it; use browser_snapshot for that.",
             readOnly: true),
        tool("browser_evaluate", "Run JavaScript in the page and return the JSON result.",
             ["function": ["type": "string", "description": "() => { /* code */ }"]], required: ["function"]),
        tool("browser_tabs", "List, create, select or close browser tabs.",
             ["action": ["type": "string", "enum": ["list", "new", "select", "close"]], "index": ["type": "number"],
              "url": ["type": "string", "description": "For new: a URL to open"]],
             required: ["action"]),
    ]
}
