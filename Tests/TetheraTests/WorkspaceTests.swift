import XCTest
@testable import Tethera

final class WorkspaceTests: XCTestCase {
    func testPanesFromVersion4LayoutsMigrate() throws {
        let session = UUID(), pane = UUID(), empty = UUID()
        let legacy = #"[{"id":"\#(pane)","session":"\#(session)"},{"id":"\#(empty)"}]"#
        let panes = try JSONDecoder().decode([Workspace.Pane].self, from: Data(legacy.utf8))
        XCTAssertEqual(panes.map(\.id), [pane, empty])
        XCTAssertEqual(panes[0].content, .session(session))
        XCTAssertEqual(panes[1].content, .home)
    }

    func testPaneContentRoundTrips() throws {
        let panes = [Workspace.Pane(content: .home), Workspace.Pane(content: .session(UUID()))]
        let decoded = try JSONDecoder().decode([Workspace.Pane].self, from: JSONEncoder().encode(panes))
        XCTAssertEqual(decoded, panes)
    }

    @MainActor
    func testRestoreKeepsHomeAndLiveSessionsOnly() {
        let alive = UUID(), gone = UUID()
        let panes = [Workspace.Pane(content: .session(gone)), Workspace.Pane(content: .home), Workspace.Pane(content: .session(alive))]
        let kept = Workspace.validPanes(panes, sessions: [alive])
        XCTAssertEqual(kept.map(\.content), [.home, .session(alive)])
    }

    func testRecentFoldersAreNewestFirstDedupedAndCapped() {
        var list: [String] = []
        for path in ["/p/a", "/p/b", "/p/a/", "/home/me", "/", "/p/c"] {
            list = RecentFolders.adding(path, to: list, home: "/home/me")
        }
        XCTAssertEqual(list, ["/p/c", "/p/a", "/p/b"])
        for index in 0..<20 { list = RecentFolders.adding("/x/\(index)", to: list, home: "/home/me") }
        XCTAssertEqual(list.count, RecentFolders.limit)
        XCTAssertEqual(list.first, "/x/19")
    }
}
