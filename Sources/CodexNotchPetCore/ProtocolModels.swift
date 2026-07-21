import Foundation

public struct RateLimitReadResponse: Decodable, Sendable {
    public let rateLimits: RateLimitSnapshot
    public let rateLimitsByLimitId: [String: RateLimitSnapshot]?

    private enum CodingKeys: String, CodingKey {
        case rateLimits
        case rateLimitsByLimitId
    }

    public init(
        rateLimits: RateLimitSnapshot,
        rateLimitsByLimitId: [String: RateLimitSnapshot]?
    ) {
        self.rateLimits = rateLimits
        self.rateLimitsByLimitId = rateLimitsByLimitId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rateLimits = try container.decode(RateLimitSnapshot.self, forKey: .rateLimits)
        rateLimitsByLimitId = try container.decodeIfPresent(
            [String: RateLimitSnapshot].self,
            forKey: .rateLimitsByLimitId
        )
    }
}

public struct RateLimitSnapshot: Decodable, Sendable {
    public let limitId: String?
    public let limitName: String?
    public let planType: String?
    public let primary: RateLimitWindow?
    public let secondary: RateLimitWindow?
    public let rateLimitReachedType: String?

    public init(
        limitId: String? = nil,
        limitName: String? = nil,
        planType: String? = nil,
        primary: RateLimitWindow? = nil,
        secondary: RateLimitWindow? = nil,
        rateLimitReachedType: String? = nil
    ) {
        self.limitId = limitId
        self.limitName = limitName
        self.planType = planType
        self.primary = primary
        self.secondary = secondary
        self.rateLimitReachedType = rateLimitReachedType
    }
}

public struct RateLimitWindow: Decodable, Sendable {
    public let usedPercent: Int
    public let windowDurationMins: Int64?
    public let resetsAt: Int64?

    public init(usedPercent: Int, windowDurationMins: Int64?, resetsAt: Int64?) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }
}

public enum UsageWindowRole: String, Sendable {
    case primary
    case secondary
}

public struct UsageWindow: Equatable, Sendable {
    public let role: UsageWindowRole
    public let usedPercent: Int
    public let remainingPercent: Int
    public let durationMinutes: Int64?
    public let resetsAt: Date?

    public init(role: UsageWindowRole, source: RateLimitWindow) {
        let clampedUsed = min(max(source.usedPercent, 0), 100)
        self.role = role
        usedPercent = clampedUsed
        remainingPercent = 100 - clampedUsed
        durationMinutes = source.windowDurationMins
        resetsAt = source.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    public var isWeekly: Bool {
        guard let durationMinutes else { return false }
        return abs(durationMinutes - 10_080) <= 60
    }
}

public struct UsageBucket: Equatable, Sendable {
    public let id: String?
    public let name: String?
    public let planType: String?
    public let windows: [UsageWindow]
    public let reachedReason: String?

    public init(
        id: String?,
        name: String?,
        planType: String?,
        windows: [UsageWindow],
        reachedReason: String?
    ) {
        self.id = id
        self.name = name
        self.planType = planType
        self.windows = windows
        self.reachedReason = reachedReason
    }
}

public enum RateLimitMapper {
    public static func buckets(from response: RateLimitReadResponse) -> [UsageBucket] {
        let snapshots: [(String?, RateLimitSnapshot)]

        if let byId = response.rateLimitsByLimitId, !byId.isEmpty {
            snapshots = byId.keys.sorted().compactMap { key in
                byId[key].map { (key, $0) }
            }
        } else {
            snapshots = [(response.rateLimits.limitId, response.rateLimits)]
        }

        return snapshots.map { key, snapshot in
            var windows: [UsageWindow] = []
            if let primary = snapshot.primary {
                windows.append(UsageWindow(role: .primary, source: primary))
            }
            if let secondary = snapshot.secondary {
                windows.append(UsageWindow(role: .secondary, source: secondary))
            }

            return UsageBucket(
                id: snapshot.limitId ?? key,
                name: snapshot.limitName,
                planType: snapshot.planType,
                windows: windows,
                reachedReason: snapshot.rateLimitReachedType
            )
        }
    }

    public static func collapsedWindow(from buckets: [UsageBucket]) -> UsageWindow? {
        guard !buckets.isEmpty else { return nil }

        let bucket = buckets.first {
            $0.id?.localizedCaseInsensitiveCompare("codex") == .orderedSame
        } ?? buckets[0]

        return bucket.windows.max { lhs, rhs in
            (lhs.durationMinutes ?? -1) < (rhs.durationMinutes ?? -1)
        }
    }

    public static func label(for window: UsageWindow, in bucket: UsageBucket) -> String {
        if window.isWeekly {
            if let name = bucket.name?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                return "\(name) · Weekly"
            }
            if let id = bucket.id?.trimmingCharacters(in: .whitespacesAndNewlines),
               !id.isEmpty {
                let bucketLabel = id.localizedCaseInsensitiveCompare("codex") == .orderedSame
                    ? "Codex"
                    : id
                return "\(bucketLabel) · Weekly"
            }
            return "Weekly"
        }
        if let name = bucket.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return window.role == .primary ? "Primary window" : "Secondary window"
    }
}

public struct ThreadListResponse: Decodable, Sendable {
    public let data: [ThreadSummary]
    public let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case data
        case nextCursor
    }

    public init(data: [ThreadSummary], nextCursor: String? = nil) {
        self.data = data
        self.nextCursor = nextCursor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode([ThreadSummary].self, forKey: .data)
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
    }
}

public struct ThreadSummary: Decodable, Sendable {
    public let id: String
    public let name: String?
    public let preview: String
    public let cwd: String
    public let ephemeral: Bool
    public let parentThreadId: String?
    public let recencyAt: Int64?
    public let updatedAt: Int64
    public let status: ThreadStatusPayload

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case preview
        case cwd
        case ephemeral
        case parentThreadId
        case recencyAt
        case updatedAt
        case status
    }

    public init(
        id: String,
        name: String? = nil,
        preview: String = "",
        cwd: String = "",
        ephemeral: Bool = false,
        parentThreadId: String? = nil,
        recencyAt: Int64? = nil,
        updatedAt: Int64 = 0,
        status: ThreadStatusPayload
    ) {
        self.id = id
        self.name = name
        self.preview = preview
        self.cwd = cwd
        self.ephemeral = ephemeral
        self.parentThreadId = parentThreadId
        self.recencyAt = recencyAt
        self.updatedAt = updatedAt
        self.status = status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name)
        preview = try container.decodeIfPresent(String.self, forKey: .preview) ?? ""
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        ephemeral = try container.decodeIfPresent(Bool.self, forKey: .ephemeral) ?? false
        parentThreadId = try container.decodeIfPresent(String.self, forKey: .parentThreadId)
        recencyAt = try container.decodeIfPresent(Int64.self, forKey: .recencyAt)
        updatedAt = try container.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
        status = try container.decodeIfPresent(ThreadStatusPayload.self, forKey: .status)
            ?? ThreadStatusPayload(type: "unknown", activeFlags: [])
    }
}

public struct ThreadStatusPayload: Decodable, Equatable, Sendable {
    public let type: String
    public let activeFlags: [String]

    private enum CodingKeys: String, CodingKey {
        case type
        case activeFlags
    }

    public init(type: String, activeFlags: [String] = []) {
        self.type = type
        self.activeFlags = activeFlags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "unknown"
        activeFlags = try container.decodeIfPresent([String].self, forKey: .activeFlags) ?? []
    }
}

public enum MonitorState: String, CaseIterable, Sendable {
    case offline
    case unavailable
    case idle
    case working
    case waiting
    case approval
    case failed
    case unknown
}

public struct SelectedTask: Equatable, Sendable {
    public let id: String
    public let title: String
    public let cwdBasename: String?
    public let state: MonitorState
    public let recencyAt: Int64

    public init(
        id: String,
        title: String,
        cwdBasename: String?,
        state: MonitorState,
        recencyAt: Int64
    ) {
        self.id = id
        self.title = title
        self.cwdBasename = cwdBasename
        self.state = state
        self.recencyAt = recencyAt
    }
}

public enum TaskSelector {
    public static func select(from threads: [ThreadSummary]) -> SelectedTask? {
        let allCandidates = threads.filter { !$0.ephemeral && !$0.id.isEmpty }
        let parentCandidates = allCandidates.filter { $0.parentThreadId == nil }
        let candidates = parentCandidates.isEmpty ? allCandidates : parentCandidates
        let active = candidates.filter { $0.status.type == "active" }
        let pool = active.isEmpty ? candidates : active

        guard let selected = pool.max(by: { lhs, rhs in
            let left = lhs.recencyAt ?? lhs.updatedAt
            let right = rhs.recencyAt ?? rhs.updatedAt
            if left == right {
                return lhs.id < rhs.id
            }
            return left < right
        }) else {
            return nil
        }

        return SelectedTask(
            id: selected.id,
            title: title(for: selected),
            cwdBasename: cwdBasename(for: selected.cwd),
            state: monitorState(for: selected.status),
            recencyAt: selected.recencyAt ?? selected.updatedAt
        )
    }

    public static func monitorState(for status: ThreadStatusPayload) -> MonitorState {
        switch status.type {
        case "notLoaded":
            return .unavailable
        case "idle":
            return .idle
        case "systemError":
            return .failed
        case "active":
            if status.activeFlags.contains("waitingOnApproval") {
                return .approval
            }
            if status.activeFlags.contains("waitingOnUserInput") {
                return .waiting
            }
            return .working
        default:
            return .unknown
        }
    }

    private static func title(for thread: ThreadSummary) -> String {
        if let name = nonempty(thread.name) {
            return name
        }
        if let preview = nonempty(thread.preview) {
            return preview
        }
        if let basename = cwdBasename(for: thread.cwd) {
            return basename
        }
        return "Untitled task"
    }

    private static func cwdBasename(for path: String) -> String? {
        guard let path = nonempty(path) else { return nil }
        let basename = URL(fileURLWithPath: path).lastPathComponent
        return basename.isEmpty ? nil : basename
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
