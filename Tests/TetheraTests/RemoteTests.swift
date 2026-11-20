import XCTest
@testable import Tethera
@testable import TetheraKit

final class RemoteTests: XCTestCase {
    private func session(_ name: String, cwd: String, host: String? = nil) -> SessionInfo {
        var info = SessionInfo(name: name, cwd: cwd, shell: "/bin/zsh", cols: 80, rows: 24, order: 0)
        info.host = host
        return info
    }

    func testOtherMacsGroupAfterThisMacsRepositories() {
        let sessions = [
            session("api", cwd: "/code/api"),
            session("build", cwd: "/Users/me/web", host: "h1"),
            session("scratch", cwd: "/tmp"),
            session("docs", cwd: "/code/api/docs"),
            session("logs", cwd: "/var/log", host: "h1"),
        ]
        let groups = SessionGroups.make(sessions, repoRoot: { $0.hasPrefix("/code/api") ? "/code/api" : nil },
                                        hostName: { $0 == "h1" ? "Studio" : "?" })
        XCTAssertEqual(groups.map(\.title), ["api", "Studio", "This Mac"])
        XCTAssertEqual(groups[0].sessions.map(\.name), ["api", "docs"])
        XCTAssertEqual(groups[1].sessions.map(\.name), ["build", "logs"], "a remote path is never looked up on this disk")
        XCTAssertEqual(groups[1].host, "h1")
        XCTAssertEqual(SessionGroups.make([session("x", cwd: "/tmp")], repoRoot: { _ in nil }).first?.title, "Other")
    }

    func testRemoteSessionsHaveNoLocalFolder() {
        XCTAssertEqual(session("a", cwd: "/code").localFolder, "/code")
        XCTAssertNil(session("b", cwd: "/code", host: "h1").localFolder)
        XCTAssertEqual(session("c", cwd: "/Users/someone/api", host: "h1").displayPath, "~/api")
    }

    func testSessionsFromOlderDaemonsDecode() throws {
        let original = session("a", cwd: "/code")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        json["host"] = nil
        let decoded = try JSONDecoder().decode(SessionInfo.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.host)
        XCTAssertEqual(decoded.name, "a")
    }

    func testRemoteCommandFindsTetheraInPlainSh() {
        let command = DaemonClient.remoteCommand("bridge")
        XCTAssertTrue(command.hasPrefix("exec /bin/sh -c '"))
        XCTAssertTrue(command.contains(#"exec "$c" bridge"#))
        XCTAssertEqual(command.filter { $0 == "'" }.count, 2, "one quoted script, nothing inside breaks out")
    }

    func testHTTPRequestsParseOnlyWhenComplete() {
        let head = "POST /api/sessions/x/reply HTTP/1.1\r\nHost: mac\r\nAuthorization: Bearer abc\r\nContent-Length: 13\r\n\r\n"
        XCTAssertNil(PhoneServer.parse(Data((head + "{\"text\":").utf8)), "waits for the whole body")
        let request = PhoneServer.parse(Data((head + "{\"text\":\"pg\"}").utf8))
        XCTAssertEqual(request?.method, "POST")
        XCTAssertEqual(request?.path, "/api/sessions/x/reply")
        XCTAssertEqual(request?.headers["authorization"], "Bearer abc")
        XCTAssertEqual(request.map { String(decoding: $0.body, as: UTF8.self) }, "{\"text\":\"pg\"}")
        XCTAssertNil(PhoneServer.parse(Data("GET / HTTP/1.1\r\nHost: mac\r\n".utf8)))
    }

    @MainActor
    func testRepliesOnlyGoToAgentQuestions() {
        var asking = session("web", cwd: "/w")
        asking.agent = AgentInfo(kind: .claude, state: .needsInput)
        asking.agent?.reason = "question"
        XCTAssertTrue(PhoneServer.takesReplies(asking))
        asking.agent?.reason = "permission"
        XCTAssertFalse(PhoneServer.takesReplies(asking), "Allow and Deny answer permission prompts")
        asking.agent?.state = .working
        asking.agent?.reason = nil
        XCTAssertFalse(PhoneServer.takesReplies(asking))
        XCTAssertFalse(PhoneServer.takesReplies(session("shell", cwd: "/w")), "never a shell")
    }

    @MainActor
    func testPairingLinksKeepTheTokenInTheFragment() {
        let url = PhoneServer.url(host: "100.101.102.103", port: 7340, token: "tok")
        XCTAssertEqual(url?.absoluteString, "http://100.101.102.103:7340/#t=tok")
        XCTAssertEqual(PhoneServer.url(host: "fd7a::1", port: 7340, token: "t")?.host, "fd7a::1")
        let token = PhoneServer.randomToken()
        XCTAssertGreaterThanOrEqual(token.count, 32)
        XCTAssertNil(token.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")), "URL-safe")
    }

    @MainActor
    func testPushPayloadForNtfy() throws {
        let allow = try XCTUnwrap(URL(string: "http://100.1.2.3:7340/a/nonce"))
        let body = PushNotifier.payload(topic: "tethera-abc", title: "Claude wants to run Bash", message: "npm test",
                                        tags: ["lock"], priority: 4, click: nil, actions: [.init(label: "Allow", url: allow)])
        XCTAssertEqual(body["topic"] as? String, "tethera-abc")
        XCTAssertNil(body["click"])
        let action = try XCTUnwrap((body["actions"] as? [[String: Any]])?.first)
        XCTAssertEqual(action["action"] as? String, "http")
        XCTAssertEqual(action["method"] as? String, "POST")
        XCTAssertEqual(action["url"] as? String, allow.absoluteString)
        XCTAssertTrue(PushNotifier.newTopic().hasPrefix("tethera-"))
        XCTAssertGreaterThan(PushNotifier.newTopic().count, 24, "long enough not to guess")
    }
}
