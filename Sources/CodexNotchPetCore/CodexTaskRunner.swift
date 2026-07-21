@preconcurrency import Foundation
import Darwin

public struct CodexTaskRequest: Sendable {
    public let prompt: String
    public let workingDirectory: URL
    public let screenCapture: EphemeralScreenCapture?
    public let isEphemeral: Bool

    public init(
        prompt: String,
        workingDirectory: URL,
        screenCapture: EphemeralScreenCapture? = nil,
        isEphemeral: Bool = false
    ) {
        self.prompt = prompt
        self.workingDirectory = workingDirectory
        self.screenCapture = screenCapture
        self.isEphemeral = isEphemeral
    }
}

public struct CodexTaskResult: Equatable, Sendable {
    public let threadID: String?
    public let finalMessage: String

    public init(threadID: String?, finalMessage: String) {
        self.threadID = threadID
        self.finalMessage = finalMessage
    }
}

public enum CodexTaskRunnerError: Error, Equatable, Sendable {
    case emptyPrompt
    case invalidWorkingDirectory
    case missingScreenCapture
    case alreadyRunning
    case processLaunchFailed
    case inputWriteFailed
    case processExited(Int32)
    case outputLimitExceeded
    case malformedOutput
    case noFinalMessage
}

public final class CodexTaskRunner: @unchecked Sendable {
    private let executableURL: URL
    private let maximumOutputBytes: Int
    private let stateLock = NSLock()
    private var activeSession: CodexTaskProcessSession?

    public init(executableURL: URL, maximumOutputBytes: Int = 8_388_608) {
        self.executableURL = executableURL
        self.maximumOutputBytes = maximumOutputBytes
    }

    public func run(_ request: CodexTaskRequest) async throws -> CodexTaskResult {
        defer { request.screenCapture?.remove() }

        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { throw CodexTaskRunnerError.emptyPrompt }
        guard isDirectory(request.workingDirectory) else {
            throw CodexTaskRunnerError.invalidWorkingDirectory
        }
        if let capture = request.screenCapture,
           !isRegularFile(capture.fileURL) {
            throw CodexTaskRunnerError.missingScreenCapture
        }
        if Task.isCancelled { throw CancellationError() }

        let session = CodexTaskProcessSession(
            executableURL: executableURL,
            request: CodexTaskRequest(
                prompt: prompt,
                workingDirectory: request.workingDirectory,
                screenCapture: request.screenCapture,
                isEphemeral: request.isEphemeral
            ),
            maximumOutputBytes: maximumOutputBytes
        )
        try register(session)
        defer { unregister(session) }

        return try await withTaskCancellationHandler {
            try await session.run()
        } onCancel: {
            session.cancel()
        }
    }

    public func cancel() {
        stateLock.lock()
        let session = activeSession
        stateLock.unlock()
        session?.cancel()
    }

    private func register(_ session: CodexTaskProcessSession) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard activeSession == nil else {
            throw CodexTaskRunnerError.alreadyRunning
        }
        activeSession = session
    }

    private func unregister(_ session: CodexTaskProcessSession) {
        stateLock.lock()
        if activeSession === session {
            activeSession = nil
        }
        stateLock.unlock()
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func isRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey
        ]) else {
            return false
        }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }
}

private final class CodexTaskProcessSession: @unchecked Sendable {
    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()
    private let outputCapture: BoundedTaskOutput
    private let errorCapture = BoundedTaskOutput(limit: 65_536)
    private let prompt: String
    private let stateLock = NSLock()

    private var continuation: CheckedContinuation<CodexTaskResult, Error>?
    private var didFinish = false
    private var didLaunch = false
    private var wasCancelled = false
    private var forcedFailure: CodexTaskRunnerError?

    init(
        executableURL: URL,
        request: CodexTaskRequest,
        maximumOutputBytes: Int
    ) {
        prompt = request.prompt
        outputCapture = BoundedTaskOutput(limit: maximumOutputBytes)
        process.executableURL = executableURL

        var arguments = [
            "-a", "never",
            "exec",
            "--ignore-user-config",
            "--json",
            "--color", "never",
            "-s", "read-only",
            "--skip-git-repo-check",
            "-C", request.workingDirectory.standardizedFileURL.path
        ]
        if request.isEphemeral {
            arguments.append("--ephemeral")
        }
        if let capture = request.screenCapture {
            arguments.append(contentsOf: ["-i", capture.fileURL.standardizedFileURL.path])
        }
        arguments.append("-")

        process.arguments = arguments
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
    }

    func run() async throws -> CodexTaskResult {
        try await withCheckedThrowingContinuation { continuation in
            stateLock.lock()
            if wasCancelled {
                stateLock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            stateLock.unlock()

            outputPipe.fileHandleForReading.readabilityHandler = { [outputCapture] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                outputCapture.append(data)
            }
            errorPipe.fileHandleForReading.readabilityHandler = { [errorCapture] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                errorCapture.append(data)
            }
            process.terminationHandler = { [weak self] process in
                self?.finish(terminationStatus: process.terminationStatus)
            }

            guard fcntl(
                inputPipe.fileHandleForWriting.fileDescriptor,
                F_SETNOSIGPIPE,
                1
            ) != -1 else {
                finish(error: CodexTaskRunnerError.inputWriteFailed)
                return
            }

            stateLock.lock()
            if wasCancelled {
                stateLock.unlock()
                finish(error: CancellationError())
                return
            }
            do {
                try process.run()
                didLaunch = true
            } catch {
                stateLock.unlock()
                finish(error: CodexTaskRunnerError.processLaunchFailed)
                return
            }
            stateLock.unlock()

            do {
                try inputPipe.fileHandleForWriting.write(contentsOf: Data(prompt.utf8))
                try inputPipe.fileHandleForWriting.close()
            } catch {
                try? inputPipe.fileHandleForWriting.close()
                failRunningProcess(with: .inputWriteFailed)
            }
        }
    }

    func cancel() {
        stateLock.lock()
        wasCancelled = true
        let launched = didLaunch
        let shouldFinishImmediately = continuation != nil && !launched
        stateLock.unlock()

        if launched {
            terminateRunningProcess()
        } else if shouldFinishImmediately {
            finish(error: CancellationError())
        }
    }

    private func finish(terminationStatus: Int32) {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        outputCapture.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        errorCapture.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

        stateLock.lock()
        let cancelled = wasCancelled
        let forcedFailure = forcedFailure
        stateLock.unlock()

        if cancelled {
            finish(error: CancellationError())
            return
        }
        if let forcedFailure {
            finish(error: forcedFailure)
            return
        }
        guard terminationStatus == 0 else {
            finish(error: CodexTaskRunnerError.processExited(terminationStatus))
            return
        }
        guard !outputCapture.wasTruncated else {
            finish(error: CodexTaskRunnerError.outputLimitExceeded)
            return
        }

        do {
            finish(result: try parseResult(from: outputCapture.data()))
        } catch {
            finish(error: error)
        }
    }

    private func parseResult(from data: Data) throws -> CodexTaskResult {
        var threadID: String?
        var finalMessage: String?
        var sawJSONEvent = false

        for rawLine in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(rawLine)),
                  let event = object as? [String: Any] else {
                continue
            }
            sawJSONEvent = true

            if event["type"] as? String == "thread.started" {
                threadID = event["thread_id"] as? String
            }
            guard event["type"] as? String == "item.completed",
                  let item = event["item"] as? [String: Any],
                  item["type"] as? String == "agent_message",
                  let text = item["text"] as? String else {
                continue
            }
            finalMessage = text
        }

        guard sawJSONEvent else { throw CodexTaskRunnerError.malformedOutput }
        guard let finalMessage else { throw CodexTaskRunnerError.noFinalMessage }
        return CodexTaskResult(threadID: threadID, finalMessage: finalMessage)
    }

    private func finish(result: CodexTaskResult) {
        resume(with: .success(result))
    }

    private func finish(error: Error) {
        resume(with: .failure(error))
    }

    private func failRunningProcess(with error: CodexTaskRunnerError) {
        stateLock.lock()
        if forcedFailure == nil {
            forcedFailure = error
        }
        let launched = didLaunch
        stateLock.unlock()

        if launched {
            terminateRunningProcess()
        } else {
            finish(error: error)
        }
    }

    private func terminateRunningProcess() {
        if process.isRunning {
            process.terminate()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.process.isRunning else { return }
            kill(self.process.processIdentifier, SIGKILL)
        }
    }

    private func resume(with result: Result<CodexTaskResult, Error>) {
        stateLock.lock()
        guard !didFinish, let continuation else {
            stateLock.unlock()
            return
        }
        didFinish = true
        self.continuation = nil
        stateLock.unlock()
        continuation.resume(with: result)
    }
}

private final class BoundedTaskOutput: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var captured = Data()
    private var truncated = false

    init(limit: Int) {
        self.limit = max(limit, 0)
    }

    var wasTruncated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return truncated
    }

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        let available = max(0, limit - captured.count)
        if data.count > available {
            truncated = true
        }
        captured.append(data.prefix(available))
    }

    func data() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }
}
