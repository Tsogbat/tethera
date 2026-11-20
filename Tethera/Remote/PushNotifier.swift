import AppKit
import Foundation
import TetheraKit

/// Phone push through ntfy (https://ntfy.sh), off until you turn it on: subscribe to the topic
/// in the ntfy app and agents that need you reach your phone while you're away from this Mac.
/// The topic is a long random name; anyone who knows it can read the pushes, so they carry the
/// session name and a one-line summary, never terminal output. Allow and Deny buttons call the
/// phone dashboard with a one-time link, so they work only where the dashboard is reachable.
@MainActor
final class PushNotifier {
    static let shared = PushNotifier()
    static let defaultServer = "https://ntfy.sh"
    /// Pushes go out once nobody has used this Mac's keyboard or mouse for this long.
    static let awayAfter: TimeInterval = 120

    private init() {}

    static func newTopic() -> String {
        "tethera-" + PhoneServer.randomToken(bytes: 15).lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
    }

    /// Seconds since the last key press, click, or mouse move.
    static var idleSeconds: TimeInterval {
        [CGEventType.keyDown, .mouseMoved, .leftMouseDown, .scrollWheel, .flagsChanged]
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }

    struct Action: Equatable {
        let label: String
        let url: URL
    }

    /// ntfy's JSON publish body.
    static func payload(topic: String, title: String, message: String, tags: [String], priority: Int,
                        click: URL?, actions: [Action]) -> [String: Any] {
        var body: [String: Any] = ["topic": topic, "title": title, "message": message, "tags": tags, "priority": priority]
        if let click { body["click"] = click.absoluteString }
        if !actions.isEmpty {
            body["actions"] = actions.map { ["action": "http", "label": $0.label, "url": $0.url.absoluteString, "method": "POST", "clear": true] }
        }
        return body
    }

    // MARK: Events

    /// An agent asked for permission.
    func approval(_ approval: ApprovalCenter.Approval) {
        guard shouldPush else { return }
        let phone = PhoneServer.shared
        let session = DaemonClient.shared.session(approval.session)?.name
        var actions: [Action] = []
        if let deny = phone.actionLink(for: approval.id, .deny), let allow = phone.actionLink(for: approval.id, .allow) {
            actions = [Action(label: "Deny", url: deny), Action(label: "Allow", url: allow)]
        }
        send(title: "\(approval.agent.displayName) wants to run \(approval.tool)" + (session.map { " · \($0)" } ?? ""),
             message: String(approval.summary.prefix(200)), tags: ["lock"], priority: 4, actions: actions)
    }

    /// A session changed: push when its agent starts needing you, finishes, or fails.
    func sessionChanged(_ session: SessionInfo, previous: SessionInfo?) {
        guard let previous, let agent = session.agent, shouldPush else { return }
        let old = previous.agent?.state
        let name = "\(agent.kind.displayName) · \(session.name)"
        switch agent.state {
        case .needsInput where old != .needsInput:
            // A permission request pushes on its own, with buttons; give it a moment to arrive.
            let id = session.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                MainActor.assumeIsolated {
                    guard !ApprovalCenter.shared.hasPending(for: id) else { return }
                    self?.send(title: "\(name) needs you", message: agent.message ?? "Waiting for your answer.", tags: ["raising_hand"], priority: 4)
                }
            }
        case .done where old == .working:
            send(title: "\(name) finished", message: agent.message ?? "Done.", tags: ["white_check_mark"], priority: 3)
        case .error where old != .error:
            send(title: "\(name) hit an error", message: agent.message ?? "Check the session.", tags: ["warning"], priority: 4)
        default:
            break
        }
    }

    /// A push right now, from Settings, to check the phone gets it.
    func sendTest() {
        send(title: "Tethera", message: "Pushes from \(Host.current().localizedName ?? "your Mac") will look like this.", tags: ["computer"], priority: 3, force: true)
    }

    private var shouldPush: Bool {
        PreferencesStore.shared.value.pushEnabled && Self.idleSeconds >= Self.awayAfter
    }

    private func send(title: String, message: String, tags: [String], priority: Int, actions: [Action] = [], force: Bool = false) {
        let preferences = PreferencesStore.shared.value
        guard preferences.pushEnabled || force, let topic = preferences.pushTopic,
              let server = URL(string: preferences.pushServer ?? Self.defaultServer) else { return }
        let body = Self.payload(topic: topic, title: title, message: message, tags: tags, priority: priority,
                                click: PhoneServer.shared.baseURL, actions: actions)
        var request = URLRequest(url: server)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error { NSLog("tethera push: \(error.localizedDescription)") }
            else if let http = response as? HTTPURLResponse, http.statusCode >= 300 { NSLog("tethera push: HTTP \(http.statusCode)") }
        }.resume()
    }
}
