import Foundation
import TetheraKit

/// What happened, one JSON line per event, one file per day:
/// `TETHERA_HOME/journal/YYYY-MM-DD.jsonl`. Agent state changes, messages, approvals and
/// costs. It's what "While you were away", budgets, the audit log and the cost dashboard read.
/// It stays on this Mac.
@MainActor
final class Journal {
    static let shared = Journal()

    struct Event: Codable, Equatable {
        enum Kind: String, Codable {
            case state, approval, cost, budget, started, ended
        }

        var at: Date
        var kind: Kind
        var session: UUID?
        var sessionName: String?
        var agent: String?
        var state: String?
        var message: String?
        var tool: String?
        var detail: String?
        var decision: String?
        var costUSD: Double?
        var repo: String?
        /// Who answered an approval: "you", "phone", "policy" or "team policy".
        var by: String?
    }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private var directory: URL { JournalFile.directory }

    static func dayName(_ date: Date) -> String {
        JournalFile.dayName(date)
    }

    func append(_ event: Event) {
        guard let line = try? encoder.encode(event) else { return }
        JournalFile.append(line, at: event.at)
    }

    /// Events from `start` until now (or `end`), oldest first.
    func events(from start: Date, to end: Date = Date()) -> [Event] {
        var day = Calendar.current.startOfDay(for: start)
        var result: [Event] = []
        while day <= end {
            let url = directory.appendingPathComponent(Self.dayName(day) + ".jsonl")
            if let data = try? Data(contentsOf: url) {
                for line in data.split(separator: 0x0A) {
                    if let event = try? decoder.decode(Event.self, from: line), event.at >= start, event.at <= end { result.append(event) }
                }
            }
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    // MARK: Recording

    /// Called with every session update: notes state changes, new costs, starts and ends.
    func record(_ session: SessionInfo, previous: SessionInfo?) {
        let agent = session.agent
        if previous == nil {
            append(Event(at: Date(), kind: .started, session: session.id, sessionName: session.name, repo: session.cwd))
        }
        if let agent, agent.state != previous?.agent?.state || agent.kind != previous?.agent?.kind {
            append(Event(at: Date(), kind: .state, session: session.id, sessionName: session.name, agent: agent.kind.rawValue,
                         state: agent.state.rawValue, message: agent.message, repo: session.cwd))
        }
        if let cost = agent?.costUSD, cost != previous?.agent?.costUSD {
            append(Event(at: Date(), kind: .cost, session: session.id, sessionName: session.name, agent: agent?.kind.rawValue,
                         costUSD: cost, repo: session.cwd))
        }
    }

    func recordEnded(_ session: SessionInfo) {
        append(Event(at: Date(), kind: .ended, session: session.id, sessionName: session.name, agent: session.agent?.kind.rawValue,
                     repo: session.cwd))
    }

    func recordApproval(_ approval: ApprovalCenter.Approval, decision: String, sessionName: String?, by: String = "you") {
        append(Event(at: Date(), kind: .approval, session: approval.session, sessionName: sessionName, agent: approval.agent.rawValue,
                     tool: approval.tool, detail: approval.summary, decision: decision, repo: approval.cwd, by: by))
    }

    // MARK: Reading costs

    /// Spend over a run of events. Agents report a running total per conversation, so spend is
    /// how far each session's total grew; a total that drops means a new conversation started,
    /// and its whole total counts. `baseline` (events before the window) gives each session's
    /// starting total; without one, a session's first total counts in full.
    static func spend(in events: [Event], baseline: [Event] = []) -> [UUID: Double] {
        var last: [UUID: Double] = [:]
        for event in baseline where event.kind == .cost {
            if let session = event.session, let cost = event.costUSD { last[session] = cost }
        }
        var spent: [UUID: Double] = [:]
        for event in events where event.kind == .cost {
            guard let session = event.session, let cost = event.costUSD else { continue }
            let previous = last[session]
            spent[session, default: 0] += previous.map { cost >= $0 ? cost - $0 : cost } ?? cost
            last[session] = cost
        }
        return spent
    }
}
