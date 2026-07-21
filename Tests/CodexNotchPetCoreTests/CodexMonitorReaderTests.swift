import Darwin
import Foundation
import XCTest
@testable import CodexNotchPetCore

final class CodexMonitorReaderTests: XCTestCase {
    func testReadsQuotaAndTaskThroughExplicitExecutablePath() throws {
        try withFakeExecutable(named: "codex-success") { executable in
            let earliestUpdate = Date()
            let snapshot = try CodexMonitorReader(requestTimeout: 2).read(
                explicitPath: executable.path
            )
            let latestUpdate = Date()

            XCTAssertEqual(snapshot.cliVersion, "codex-cli fixture")
            XCTAssertEqual(snapshot.buckets.count, 1)
            XCTAssertEqual(snapshot.buckets[0].id, "codex")
            XCTAssertEqual(snapshot.buckets[0].windows.first?.usedPercent, 25)
            XCTAssertEqual(snapshot.buckets[0].windows.first?.remainingPercent, 75)
            XCTAssertEqual(snapshot.selectedTask?.id, "fixture-thread")
            XCTAssertEqual(snapshot.selectedTask?.state, .approval)
            XCTAssertEqual(
                snapshot.taskReadStatus,
                .success(sortKey: "recency_at")
            )
            XCTAssertGreaterThanOrEqual(snapshot.codexRTTMilliseconds, 0)
            XCTAssertGreaterThanOrEqual(snapshot.updatedAt, earliestUpdate)
            XCTAssertLessThanOrEqual(snapshot.updatedAt, latestUpdate)
            XCTAssertTrue(FileManager.default.fileExists(atPath: stopMarker(for: executable).path))
        }
    }

    func testFallsBackToUpdatedAtOnlyForUnsupportedRecencySort() throws {
        try withFakeExecutable(named: "codex-sort-fallback") { executable in
            let snapshot = try CodexMonitorReader(requestTimeout: 2).read(
                executableURL: executable
            )

            XCTAssertEqual(snapshot.selectedTask?.id, "fixture-thread")
            XCTAssertEqual(
                snapshot.taskReadStatus,
                .success(sortKey: "updated_at")
            )
        }
    }

    func testTaskFailureReturnsSanitizedPartialQuotaSnapshotWithoutFallback() throws {
        try withFakeExecutable(named: "codex-task-error") { executable in
            let snapshot = try CodexMonitorReader(requestTimeout: 2).read(
                executableURL: executable
            )

            XCTAssertEqual(snapshot.buckets.first?.id, "codex")
            XCTAssertNil(snapshot.selectedTask)
            XCTAssertEqual(
                snapshot.taskReadStatus,
                .unavailable(reason: .rpcError)
            )
            XCTAssertFalse(
                String(describing: snapshot.taskReadStatus).contains("PRIVATE_TASK_MARKER")
            )
        }
    }

    func testRateLimitFailureThrowsSanitizedErrorAndStopsClient() throws {
        try withFakeExecutable(named: "codex-rate-error") { executable in
            XCTAssertThrowsError(
                try CodexMonitorReader(requestTimeout: 2).read(executableURL: executable)
            ) { error in
                XCTAssertEqual(
                    error as? CodexAppServerError,
                    .rpcError(code: -32_000)
                )
                XCTAssertFalse(String(describing: error).contains("PRIVATE_RATE_MARKER"))
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: stopMarker(for: executable).path))
        }
    }

    func testNotLoadedStatusDoesNotBecomeWorkingFromRecency() throws {
        try withFakeExecutable(named: "codex-not-loaded") { executable in
            let snapshot = try CodexMonitorReader(requestTimeout: 2).read(
                executableURL: executable
            )

            XCTAssertEqual(snapshot.selectedTask?.recencyAt, 99)
            XCTAssertEqual(snapshot.selectedTask?.state, .unavailable)
        }
    }

    private func withFakeExecutable(
        named name: String,
        _ body: (URL) throws -> Void
    ) throws {
        let fixture = try XCTUnwrap(
            Bundle.module.url(forResource: "fake-codex", withExtension: "sh")
        )
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let executable = temporaryRoot.appendingPathComponent(name)
        try FileManager.default.copyItem(at: fixture, to: executable)
        XCTAssertEqual(chmod(executable.path, 0o755), 0)
        try body(executable)
    }

    private func stopMarker(for executable: URL) -> URL {
        URL(fileURLWithPath: executable.path + ".stopped")
    }
}
