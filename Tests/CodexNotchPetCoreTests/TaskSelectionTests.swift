import XCTest
@testable import CodexNotchPetCore

final class TaskSelectionTests: XCTestCase {
    func testMostRecentActiveThreadWinsAndApprovalHasPriority() throws {
        let response = try JSONDecoder().decode(
            ThreadListResponse.self,
            from: FixtureLoader.data(named: "thread-list")
        )

        let selected = try XCTUnwrap(TaskSelector.select(from: response.data))
        XCTAssertEqual(selected.id, "active-approval")
        XCTAssertEqual(selected.title, "Approval task")
        XCTAssertEqual(selected.cwdBasename, "approval-project")
        XCTAssertEqual(selected.state, .approval)
    }

    func testWaitingAndWorkingStatesRemainDistinct() {
        XCTAssertEqual(
            TaskSelector.monitorState(
                for: ThreadStatusPayload(
                    type: "active",
                    activeFlags: ["waitingOnUserInput"]
                )
            ),
            .waiting
        )
        XCTAssertEqual(
            TaskSelector.monitorState(for: ThreadStatusPayload(type: "active")),
            .working
        )
        XCTAssertEqual(
            TaskSelector.monitorState(for: ThreadStatusPayload(type: "systemError")),
            .failed
        )
    }

    func testUnknownFieldsAndFutureStatusDoNotBreakDecoding() throws {
        let response = try JSONDecoder().decode(
            ThreadListResponse.self,
            from: FixtureLoader.data(named: "thread-unknown-status")
        )

        let selected = try XCTUnwrap(TaskSelector.select(from: response.data))
        XCTAssertEqual(selected.state, .unknown)
        XCTAssertEqual(selected.title, "Untitled task")
        XCTAssertThrowsError(
            try JSONDecoder().decode(ThreadListResponse.self, from: Data("{}".utf8))
        )
    }

    func testNewestNonEphemeralThreadIsFallbackWhenNothingIsActive() throws {
        let threads = [
            ThreadSummary(
                id: "older",
                name: nil,
                preview: "Older preview",
                updatedAt: 10,
                status: ThreadStatusPayload(type: "idle")
            ),
            ThreadSummary(
                id: "newer",
                name: "Newer",
                updatedAt: 20,
                status: ThreadStatusPayload(type: "notLoaded")
            )
        ]

        XCTAssertEqual(TaskSelector.select(from: threads)?.id, "newer")
        XCTAssertEqual(TaskSelector.select(from: threads)?.state, .unavailable)
    }

    func testCollapsedSelectionPrefersParentOverNewerActiveSubagent() {
        let threads = [
            ThreadSummary(
                id: "parent",
                name: "Parent task",
                updatedAt: 20,
                status: ThreadStatusPayload(type: "idle")
            ),
            ThreadSummary(
                id: "child",
                name: "Child agent",
                parentThreadId: "parent",
                updatedAt: 30,
                status: ThreadStatusPayload(type: "active")
            )
        ]

        XCTAssertEqual(TaskSelector.select(from: threads)?.id, "parent")
    }
}
