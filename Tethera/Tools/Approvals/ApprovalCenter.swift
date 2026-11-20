import AppKit
import Foundation
import TetheraKit
import UserNotifications

/// Permission requests from agents, answered from Tethera instead of the agent's own dialog.
///
/// Claude Code's `PermissionRequest` hook runs `tethera hook claude`, which asks the app over
/// `app.sock` and waits. The request shows in the inbox and as a notification with Allow and
/// Deny; the answer goes back to the hook, which prints Claude's decision. "Answer in terminal"
/// (or no answer) prints nothing, and Claude shows its own dialog.
@MainActor
final class ApprovalCenter: ObservableObject {
    static let shared = ApprovalCenter()
    static let notificationCategory = "tethera.approval"

    enum Answer: String {
        case allow, deny, terminal
    }

    struct Approval: Identifiable, Equatable {
        let id: UUID
        let session: UUID?
        let agent: AgentKind
        let tool: String
        /// The command, file or URL the tool wants, in one line.
        let summary: String
        let cwd: String?
        let since: Date
        let connection: Int32

        static func == (a: Approval, b: Approval) -> Bool { a.id == b.id }
    }

    @Published private(set) var pending: [Approval] = []
    private var waiting: [UUID: CheckedContinuation<Answer, Never>] = [:]

    func register(on server: AppServer) {
        server.register("approval.request") { request, connection in
            await ApprovalCenter.shared.handle(request, connection: connection)
        }
        server.onDisconnect.append { connection in
            MainActor.assumeIsolated { ApprovalCenter.shared.drop(connection: connection) }
        }
    }

    func hasPending(for session: UUID) -> Bool {
        pending.contains { $0.session == session }
    }

    // MARK: Requests

    private func handle(_ request: AppChannel.Request, connection: Int32) async -> AppChannel.Response {
        let params = (try? JSONSerialization.jsonObject(with: Data(request.params.utf8))) as? [String: Any] ?? [:]
        let tool = params["tool_name"] as? String ?? "a tool"
        let approval = Approval(
            id: UUID(),
            session: request.session.flatMap(UUID.init(uuidString:)),
            agent: (params["agent"] as? String).flatMap(AgentKind.init(rawValue:)) ?? .claude,
            tool: tool,
            summary: Self.summary(tool: tool, input: params["tool_input"] as? [String: Any] ?? [:]),
            cwd: params["cwd"] as? String,
            since: Date(),
            connection: connection)
        pending.append(approval)
        notify(approval)
        PushNotifier.shared.approval(approval)
        let answer = await withCheckedContinuation { continuation in waiting[approval.id] = continuation }
        return AppChannel.Response(id: request.id, text: answer.rawValue)
    }

    /// Answers a request: from the inbox, a notification, or the phone.
    func answer(_ id: UUID, _ answer: Answer, from source: String = "you") {
        guard let continuation = waiting.removeValue(forKey: id) else { return }
        if let approval = pending.first(where: { $0.id == id }) {
            Journal.shared.recordApproval(approval, decision: answer.rawValue, sessionName: DaemonClient.shared.session(approval.session)?.name,
                                          by: source)
        }
        let session = pending.first { $0.id == id }?.session
        pending.removeAll { $0.id == id }
        Self.notifications?.removeDeliveredNotifications(withIdentifiers: [id.uuidString])
        continuation.resume(returning: answer)
        if answer == .terminal, let session { Workspace.shared.show(session) }
    }

    /// The hook went away: Claude timed it out, or the question was answered in the terminal.
    private func drop(connection: Int32) {
        for approval in pending where approval.connection == connection {
            waiting.removeValue(forKey: approval.id)?.resume(returning: .terminal)
            Self.notifications?.removeDeliveredNotifications(withIdentifiers: [approval.id.uuidString])
        }
        pending.removeAll { $0.connection == connection }
    }

    /// Releases everything when Tethera quits, so no agent is left waiting.
    func releaseAll() {
        for (_, continuation) in waiting { continuation.resume(returning: .terminal) }
        waiting.removeAll()
        pending.removeAll()
    }

    static func summary(tool: String, input: [String: Any]) -> String {
        let subject = ApprovalPolicies.subject(tool: tool, input: input)
        return subject.isEmpty ? tool : subject.replacingOccurrences(of: "\n", with: " ⏎ ")
    }

    // MARK: Notifications

    /// Notifications need a real app bundle; `swift run` builds have none (and would throw).
    static var notifications: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier != nil ? UNUserNotificationCenter.current() : nil
    }

    static func registerCategory() {
        let allow = UNNotificationAction(identifier: Answer.allow.rawValue, title: "Allow", options: [])
        let deny = UNNotificationAction(identifier: Answer.deny.rawValue, title: "Deny", options: [.destructive])
        let category = UNNotificationCategory(identifier: notificationCategory, actions: [allow, deny], intentIdentifiers: [], options: [])
        notifications?.setNotificationCategories([category])
    }

    private func notify(_ approval: Approval) {
        guard Bundle.main.bundleIdentifier != nil else {
            NSApp.requestUserAttention(.criticalRequest)
            return
        }
        let content = UNMutableNotificationContent()
        let session = DaemonClient.shared.session(approval.session)
        content.title = "\(approval.agent.displayName) wants to run \(approval.tool)"
        content.subtitle = session?.name ?? ""
        content.body = approval.summary
        content.categoryIdentifier = Self.notificationCategory
        content.userInfo = ["approval": approval.id.uuidString, "session": approval.session?.uuidString ?? ""]
        content.interruptionLevel = .timeSensitive
        Self.notifications?.add(UNNotificationRequest(identifier: approval.id.uuidString, content: content, trigger: nil))
    }

    /// A notification button was pressed. Returns false if it wasn't an approval.
    func handleNotificationResponse(_ response: UNNotificationResponse) -> Bool {
        guard let raw = response.notification.request.content.userInfo["approval"] as? String, let id = UUID(uuidString: raw) else { return false }
        switch response.actionIdentifier {
        case Answer.allow.rawValue: answer(id, .allow)
        case Answer.deny.rawValue: answer(id, .deny)
        default: Workspace.shared.showApprovals()
        }
        return true
    }
}
