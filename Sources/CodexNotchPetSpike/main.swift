import CodexNotchPetCore
import Darwin
import Foundation

private struct Arguments {
    let codexPath: String?
    let listenSeconds: TimeInterval

    static func parse(_ values: [String]) -> Arguments? {
        var codexPath: String?
        var listenSeconds: TimeInterval = 2
        var index = 0

        while index < values.count {
            switch values[index] {
            case "--codex":
                guard index + 1 < values.count else { return nil }
                codexPath = values[index + 1]
                index += 2
            case "--listen-seconds":
                guard index + 1 < values.count,
                      let parsed = TimeInterval(values[index + 1]),
                      (0...30).contains(parsed) else {
                    return nil
                }
                listenSeconds = parsed
                index += 2
            case "--help", "-h":
                printUsage()
                exit(0)
            default:
                return nil
            }
        }

        return Arguments(codexPath: codexPath, listenSeconds: listenSeconds)
    }
}

private final class NotificationCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var methodCounts: [String: Int] = [:]
    private var statusCounts: [String: Int] = [:]

    func record(_ notification: ServerNotification) {
        lock.lock()
        methodCounts[notification.method, default: 0] += 1
        lock.unlock()

        guard notification.method == "thread/status/changed",
              let params = notification.params,
              let decoded = try? JSONDecoder().decode(
                  ThreadStatusChangedNotification.self,
                  from: params
              ) else {
            return
        }

        lock.lock()
        statusCounts[decoded.status.type, default: 0] += 1
        lock.unlock()
    }

    func snapshot() -> (methods: [String: Int], statuses: [String: Int]) {
        lock.lock()
        defer { lock.unlock() }
        return (methodCounts, statusCounts)
    }
}

private func printUsage() {
    let usage = """
    Usage: codex-notch-pet-spike [--codex /path/to/codex] [--listen-seconds 0...30]

    Emits a sanitized JSON summary. It never prints thread titles, prompts, cwd paths,
    tool output, raw stderr, or credentials.
    """
    print(usage)
}

private func countStatuses(_ threads: [ThreadSummary]) -> [String: Int] {
    threads.reduce(into: [:]) { result, thread in
        result[thread.status.type, default: 0] += 1
    }
}

private func readThreads(
    using client: CodexAppServerClient
) throws -> (response: ThreadListResponse, sortKey: String) {
    func request(sortKey: String) throws -> ThreadListResponse {
        try client.request(
            method: "thread/list",
            params: [
                "archived": false,
                "limit": 20,
                "sourceKinds": ["cli", "vscode", "appServer"],
                "sortKey": sortKey,
                "sortDirection": "desc",
                "useStateDbOnly": true
            ],
            timeout: 10
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

private func errorCategory(_ error: CodexAppServerError) -> String {
    switch error {
    case .alreadyStarted:
        return "alreadyStarted"
    case .notStarted:
        return "notStarted"
    case .processLaunchFailed:
        return "processLaunchFailed"
    case .processExited(let status):
        return "processExited(\(status))"
    case .requestTimedOut:
        return "requestTimedOut"
    case .writeFailed:
        return "writeFailed"
    case .malformedResponse:
        return "malformedResponse"
    case .rpcError(let code):
        return "rpcError(\(code.map(String.init) ?? "unknown"))"
    }
}

private func jsonString(_ value: String?) -> Any {
    if let value {
        return value
    }
    return NSNull()
}

private func jsonUsage(_ buckets: [UsageBucket]) -> [[String: Any]] {
    buckets.map { bucket in
        [
            "id": bucket.id ?? NSNull(),
            "name": bucket.name ?? NSNull(),
            "windowCount": bucket.windows.count,
            "windows": bucket.windows.map { window in
                [
                    "role": window.role.rawValue,
                    "usedPercent": window.usedPercent,
                    "remainingPercent": window.remainingPercent,
                    "durationMinutes": window.durationMinutes ?? NSNull(),
                    "resetsAt": window.resetsAt.map {
                        Int64($0.timeIntervalSince1970)
                    } ?? NSNull(),
                    "weekly": window.isWeekly
                ] as [String: Any]
            }
        ] as [String: Any]
    }
}

guard let arguments = Arguments.parse(Array(CommandLine.arguments.dropFirst())) else {
    printUsage()
    exit(64)
}

guard let executableURL = CodexExecutableLocator.locate(explicitPath: arguments.codexPath) else {
    fputs("Codex executable not found or is not a regular executable.\n", stderr)
    exit(2)
}

private let collector = NotificationCollector()
let client = CodexAppServerClient(executableURL: executableURL)
client.setNotificationHandler { notification in
    collector.record(notification)
}

do {
    try client.start()
    defer { client.stop() }

    try client.initialize(timeout: 10)

    let start = ContinuousClock.now
    let rateLimits: RateLimitReadResponse = try client.request(
        method: "account/rateLimits/read",
        timeout: 10
    )
    let codexRTT = start.duration(to: .now)

    var threadRead: (response: ThreadListResponse, sortKey: String)?
    var threadReadError: String?
    do {
        threadRead = try readThreads(using: client)
    } catch let error as CodexAppServerError {
        threadReadError = errorCategory(error)
    }
    let threadList = threadRead?.response ?? ThreadListResponse(data: [])

    if arguments.listenSeconds > 0 {
        Thread.sleep(forTimeInterval: arguments.listenSeconds)
    }

    let buckets = RateLimitMapper.buckets(from: rateLimits)
    let selected = TaskSelector.select(from: threadList.data)
    let activeCount = threadList.data.filter { $0.status.type == "active" }.count
    let notifications = collector.snapshot()
    let selectedState: Any
    if let selected {
        selectedState = selected.state.rawValue
    } else if threadReadError != nil {
        selectedState = MonitorState.unavailable.rawValue
    } else {
        selectedState = NSNull()
    }
    let milliseconds = codexRTT.components.seconds * 1_000
        + Int64(codexRTT.components.attoseconds / 1_000_000_000_000_000)

    let output: [String: Any] = [
        "connection": client.isConnected ? "connected" : "offline",
        "cliVersion": CodexExecutableLocator.versionString(at: executableURL) ?? NSNull(),
        "codexRTTMilliseconds": milliseconds,
        "usage": jsonUsage(buckets),
        "collapsedRemainingPercent": RateLimitMapper.collapsedWindow(from: buckets)?.remainingPercent
            ?? NSNull(),
        "threads": [
            "count": threadList.data.count,
            "activeCount": activeCount,
            "readStatus": threadReadError == nil ? "ok" : "error",
            "readError": jsonString(threadReadError),
            "sortKey": jsonString(threadRead?.sortKey),
            "statusCounts": countStatuses(threadList.data),
            "selectedState": selectedState,
            "observedActiveThreadFromSeparateAppServer": activeCount > 0
        ],
        "notifications": [
            "methodCounts": notifications.methods,
            "statusCounts": notifications.statuses
        ],
        "diagnostics": [
            "stderrBytesDiscarded": client.observedStderrByteCount,
            "malformedLines": client.malformedLineCount
        ]
    ]

    let data = try JSONSerialization.data(
        withJSONObject: output,
        options: [.prettyPrinted, .sortedKeys]
    )
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch let error as CodexAppServerError {
    fputs("Codex app-server probe failed: \(errorCategory(error))\n", stderr)
    exit(1)
} catch {
    fputs("Codex app-server probe failed.\n", stderr)
    exit(1)
}
