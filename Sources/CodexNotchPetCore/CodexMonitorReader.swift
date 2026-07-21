import Foundation

public enum CodexMonitorReaderError: Error, Equatable, Sendable {
    case executableNotFound
}

public enum CodexTaskReadFailure: String, Equatable, Sendable {
    case appServerUnavailable
    case timedOut
    case writeFailed
    case malformedResponse
    case rpcError
    case unknown
}

public enum CodexTaskReadStatus: Equatable, Sendable {
    case success(sortKey: String)
    case unavailable(reason: CodexTaskReadFailure)
}

public struct CodexMonitorSnapshot: Equatable, Sendable {
    public let buckets: [UsageBucket]
    public let selectedTask: SelectedTask?
    public let codexRTTMilliseconds: Int64
    public let updatedAt: Date
    public let cliVersion: String?
    public let taskReadStatus: CodexTaskReadStatus

    public init(
        buckets: [UsageBucket],
        selectedTask: SelectedTask?,
        codexRTTMilliseconds: Int64,
        updatedAt: Date,
        cliVersion: String?,
        taskReadStatus: CodexTaskReadStatus
    ) {
        self.buckets = buckets
        self.selectedTask = selectedTask
        self.codexRTTMilliseconds = codexRTTMilliseconds
        self.updatedAt = updatedAt
        self.cliVersion = cliVersion
        self.taskReadStatus = taskReadStatus
    }
}

public struct CodexMonitorReader: Sendable {
    private let requestTimeout: TimeInterval
    private let threadLimit: Int

    public init(requestTimeout: TimeInterval = 10, threadLimit: Int = 20) {
        self.requestTimeout = requestTimeout
        self.threadLimit = threadLimit
    }

    public func read(explicitPath: String? = nil) throws -> CodexMonitorSnapshot {
        guard let executableURL = CodexExecutableLocator.locate(explicitPath: explicitPath) else {
            throw CodexMonitorReaderError.executableNotFound
        }
        return try read(executableURL: executableURL)
    }

    public func read(executableURL: URL) throws -> CodexMonitorSnapshot {
        let cliVersion = sanitizedVersion(at: executableURL)
        let client = CodexAppServerClient(executableURL: executableURL)
        try client.start()
        defer { client.stop() }

        try client.initialize(timeout: requestTimeout)

        let rateLimitStart = ContinuousClock.now
        let rateLimits: RateLimitReadResponse = try client.request(
            method: "account/rateLimits/read",
            timeout: requestTimeout
        )
        let codexRTT = rateLimitStart.duration(to: .now)

        let taskResult: TaskResult
        do {
            let threadResult = try readThreads(using: client)
            taskResult = TaskResult(
                selectedTask: TaskSelector.select(from: threadResult.response.data),
                status: .success(sortKey: threadResult.sortKey)
            )
        } catch let error as CodexAppServerError {
            taskResult = TaskResult(
                selectedTask: nil,
                status: .unavailable(reason: taskFailure(from: error))
            )
        } catch {
            taskResult = TaskResult(
                selectedTask: nil,
                status: .unavailable(reason: .unknown)
            )
        }

        return CodexMonitorSnapshot(
            buckets: RateLimitMapper.buckets(from: rateLimits),
            selectedTask: taskResult.selectedTask,
            codexRTTMilliseconds: milliseconds(in: codexRTT),
            updatedAt: Date(),
            cliVersion: cliVersion,
            taskReadStatus: taskResult.status
        )
    }

    private func readThreads(
        using client: CodexAppServerClient
    ) throws -> (response: ThreadListResponse, sortKey: String) {
        func request(sortKey: String) throws -> ThreadListResponse {
            let params: [String: Any] = [
                "archived": false,
                "limit": threadLimit,
                "sourceKinds": ["cli", "vscode", "appServer"],
                "sortKey": sortKey,
                "sortDirection": "desc",
                "useStateDbOnly": true
            ]
            return try client.request(
                method: "thread/list",
                params: params,
                timeout: requestTimeout
            )
        }

        do {
            return (try request(sortKey: "recency_at"), "recency_at")
        } catch let error as CodexAppServerError {
            guard case .rpcError(let code) = error, code == -32_600 else {
                throw error
            }
            return (try request(sortKey: "updated_at"), "updated_at")
        }
    }

    private func sanitizedVersion(at executableURL: URL) -> String? {
        guard let rawVersion = CodexExecutableLocator.versionString(at: executableURL),
              let firstLine = rawVersion.split(whereSeparator: \.isNewline).first else {
            return nil
        }

        let version = String(firstLine.prefix(200))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard version.hasPrefix("codex-cli ") else { return nil }
        return version
    }

    private func milliseconds(in duration: Duration) -> Int64 {
        duration.components.seconds * 1_000
            + Int64(duration.components.attoseconds / 1_000_000_000_000_000)
    }

    private func taskFailure(from error: CodexAppServerError) -> CodexTaskReadFailure {
        switch error {
        case .alreadyStarted, .notStarted, .processLaunchFailed, .processExited:
            return .appServerUnavailable
        case .requestTimedOut:
            return .timedOut
        case .writeFailed:
            return .writeFailed
        case .malformedResponse:
            return .malformedResponse
        case .rpcError:
            return .rpcError
        }
    }
}

private struct TaskResult {
    let selectedTask: SelectedTask?
    let status: CodexTaskReadStatus
}
