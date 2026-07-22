import Darwin
import Foundation
import XCTest
@testable import CodexNotchPetCore

final class CodexTaskRunnerTests: XCTestCase {
    func testRunsWithFixedReadOnlyPolicyAndPromptOnStandardInput() async throws {
        try await withFakeExecutable(named: "codex-task-success") { executable in
            let runner = CodexTaskRunner(executableURL: executable)
            let result = try await runner.run(
                CodexTaskRequest(
                    prompt: "  inspect this workspace  ",
                    workingDirectory: executable.deletingLastPathComponent()
                )
            )

            XCTAssertEqual(
                result,
                CodexTaskResult(threadID: "fixture-thread", finalMessage: "Fixture answer")
            )
            XCTAssertEqual(
                try String(contentsOf: argumentsURL(for: executable), encoding: .utf8),
                "-a\nnever\nexec\n--ignore-user-config\n--json\n--color\nnever\n-s\nread-only\n--skip-git-repo-check\n-C\n\(executable.deletingLastPathComponent().path)\n-\n"
            )
            XCTAssertEqual(
                try String(contentsOf: promptURL(for: executable), encoding: .utf8),
                "inspect this workspace"
            )
        }
    }

    func testPassesCaptureAsImageAndDeletesItAfterCompletion() async throws {
        try await withFakeExecutable(named: "codex-task-success") { executable in
            let root = executable.deletingLastPathComponent()
            let capture = try ScreenCaptureService(temporaryRoot: root)
                .storePNGData(Data("png fixture".utf8))
            let imagePath = capture.fileURL.path

            _ = try await CodexTaskRunner(executableURL: executable).run(
                CodexTaskRequest(
                    prompt: "guide me",
                    workingDirectory: root,
                    screenCapture: capture,
                    isEphemeral: true
                )
            )

            let arguments = try String(
                contentsOf: argumentsURL(for: executable),
                encoding: .utf8
            )
            XCTAssertTrue(arguments.contains("--ephemeral\n"))
            XCTAssertTrue(arguments.contains("-i\n\(imagePath)\n"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: imagePath))
        }
    }

    func testCancellationTerminatesProcessAndDeletesCapture() async throws {
        try await withFakeExecutable(named: "codex-task-slow") { executable in
            let root = executable.deletingLastPathComponent()
            let capture = try ScreenCaptureService(temporaryRoot: root)
                .storePNGData(Data("png fixture".utf8))
            let imagePath = capture.fileURL.path
            let runner = CodexTaskRunner(executableURL: executable)

            let task = Task {
                try await runner.run(
                    CodexTaskRequest(
                        prompt: "wait",
                        workingDirectory: root,
                        screenCapture: capture
                    )
                )
            }
            try await waitForFile(promptURL(for: executable))
            task.cancel()

            do {
                _ = try await task.value
                XCTFail("Expected cancellation")
            } catch is CancellationError {
                // Expected.
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: imagePath))
        }
    }

    func testImmediateCancellationCannotRaceContinuationRegistration() async throws {
        try await withFakeExecutable(named: "codex-task-slow") { executable in
            let runner = CodexTaskRunner(executableURL: executable)
            let task = Task {
                try await runner.run(
                    CodexTaskRequest(
                        prompt: "wait",
                        workingDirectory: executable.deletingLastPathComponent()
                    )
                )
            }
            task.cancel()

            do {
                _ = try await task.value
                XCTFail("Expected cancellation")
            } catch is CancellationError {
                // Expected.
            }
        }
    }

    func testRejectsBlankPromptAndInvalidWorkingDirectory() async throws {
        try await withFakeExecutable(named: "codex-task-success") { executable in
            let runner = CodexTaskRunner(executableURL: executable)

            do {
                _ = try await runner.run(
                    CodexTaskRequest(
                        prompt: " \n ",
                        workingDirectory: executable.deletingLastPathComponent()
                    )
                )
                XCTFail("Expected empty prompt error")
            } catch {
                XCTAssertEqual(error as? CodexTaskRunnerError, .emptyPrompt)
            }

            do {
                _ = try await runner.run(
                    CodexTaskRequest(prompt: "hello", workingDirectory: executable)
                )
                XCTFail("Expected directory validation error")
            } catch {
                XCTAssertEqual(
                    error as? CodexTaskRunnerError,
                    .invalidWorkingDirectory
                )
            }
        }
    }

    func testReturnsSanitizedExitAndMalformedOutputErrors() async throws {
        try await withFakeExecutable(named: "codex-task-exit") { executable in
            do {
                _ = try await CodexTaskRunner(executableURL: executable).run(
                    CodexTaskRequest(
                        prompt: "hello",
                        workingDirectory: executable.deletingLastPathComponent()
                    )
                )
                XCTFail("Expected process exit error")
            } catch {
                XCTAssertEqual(error as? CodexTaskRunnerError, .processExited(7))
                XCTAssertFalse(String(describing: error).contains("PRIVATE_STDERR_MARKER"))
            }
        }

        try await withFakeExecutable(named: "codex-task-malformed") { executable in
            do {
                _ = try await CodexTaskRunner(executableURL: executable).run(
                    CodexTaskRequest(
                        prompt: "hello",
                        workingDirectory: executable.deletingLastPathComponent()
                    )
                )
                XCTFail("Expected malformed output error")
            } catch {
                XCTAssertEqual(error as? CodexTaskRunnerError, .malformedOutput)
            }
        }
    }

    func testInputFailureTerminatesLaunchedProcess() async throws {
        try await withFakeExecutable(named: "codex-task-no-stdin") { executable in
            let runner = CodexTaskRunner(executableURL: executable)

            do {
                _ = try await runner.run(
                    CodexTaskRequest(
                        prompt: String(repeating: "x", count: 1_048_576),
                        workingDirectory: executable.deletingLastPathComponent()
                    )
                )
                XCTFail("Expected input write failure")
            } catch {
                XCTAssertEqual(error as? CodexTaskRunnerError, .inputWriteFailed)
            }
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: URL(fileURLWithPath: executable.path + ".terminated").path
                )
            )
        }
    }

    private func withFakeExecutable(
        named name: String,
        _ body: (URL) async throws -> Void
    ) async throws {
        let fixture = try XCTUnwrap(
            Bundle.module.url(forResource: "fake-codex-exec", withExtension: "sh")
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
        try await body(executable)
    }

    private func argumentsURL(for executable: URL) -> URL {
        URL(fileURLWithPath: executable.path + ".args")
    }

    private func promptURL(for executable: URL) -> URL {
        URL(fileURLWithPath: executable.path + ".stdin")
    }

    private func waitForFile(_ url: URL) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !FileManager.default.fileExists(atPath: url.path) {
            guard ContinuousClock.now < deadline else {
                XCTFail("Timed out waiting for fixture")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
