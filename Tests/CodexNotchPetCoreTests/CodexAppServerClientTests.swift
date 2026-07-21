import Darwin
import Foundation
import XCTest
@testable import CodexNotchPetCore

final class CodexAppServerClientTests: XCTestCase {
    func testInitializeReadNotificationMalformedInputAndStderrDrain() throws {
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

        let executable = temporaryRoot.appendingPathComponent("codex")
        try FileManager.default.copyItem(at: fixture, to: executable)
        XCTAssertEqual(chmod(executable.path, 0o755), 0)

        let notification = expectation(description: "status notification")
        let client = CodexAppServerClient(
            executableURL: executable,
            maximumLineBytes: 512
        )
        client.setNotificationHandler { event in
            guard event.method == "thread/status/changed",
                  let params = event.params,
                  let status = try? JSONDecoder().decode(
                      ThreadStatusChangedNotification.self,
                      from: params
                  ) else {
                return
            }
            XCTAssertEqual(status.status.activeFlags, ["waitingOnApproval"])
            notification.fulfill()
        }

        try client.start()
        defer { client.stop() }
        do {
            try client.initialize()
        } catch {
            XCTFail("initialize failed: \(error)")
            return
        }

        let rateLimits: RateLimitReadResponse
        do {
            rateLimits = try client.request(method: "account/rateLimits/read")
        } catch {
            XCTFail("rate-limit read failed: \(error)")
            return
        }
        XCTAssertEqual(rateLimits.rateLimits.primary?.usedPercent, 25)

        let threads: ThreadListResponse
        do {
            threads = try client.request(
                method: "thread/list",
                params: ["limit": 5]
            )
        } catch {
            XCTFail("thread list failed: \(error)")
            return
        }
        XCTAssertEqual(TaskSelector.select(from: threads.data)?.state, .approval)

        wait(for: [notification], timeout: 2)
        XCTAssertGreaterThanOrEqual(client.malformedLineCount, 2)
        XCTAssertGreaterThan(client.observedStderrByteCount, 0)

        struct EmptyResponse: Decodable {}
        do {
            let _: EmptyResponse = try client.request(method: "test/error")
            XCTFail("expected RPC error")
        } catch let error as CodexAppServerError {
            XCTAssertEqual(error, .rpcError(code: -32_000))
            XCTAssertFalse(String(describing: error).contains("PRIVATE_MARKER"))
        }

        try client.sendNotification(method: "test/exit")
        let deadline = Date().addingTimeInterval(2)
        while client.isConnected, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertFalse(client.isConnected)
    }
}
