import CodexNotchPetCore
import Foundation
import Observation

enum AppDisplayStatus: Equatable, Sendable {
    case connecting
    case offline
    case stale
    case liveUnavailable
    case idle
    case working
    case waiting
    case approval
    case failed
}

struct UsagePresentationRow: Identifiable, Sendable {
    let id: String
    let label: String
    let remainingPercent: Int
    let resetsAt: Date?
}

private enum ConnectionPhase: Sendable {
    case connecting
    case online
    case stale
    case offline
}

private enum MonitorRefreshOutcome: Sendable {
    case success(CodexMonitorSnapshot)
    case failure(code: String)
}

@Observable
@MainActor
final class AppModel {
    var isExpanded = false
    var isNotchRevealed = false
    var isRefreshing = false
    var isPreviewMode = false
    var taskDraft = ""
    private(set) var interactionAnimation: PetAnimationState?
    private(set) var petMessage: String?
    private(set) var taskHandoffFeedback: String?

    var privacyMode: Bool {
        didSet { defaults.set(privacyMode, forKey: Keys.privacyMode) }
    }

    var selectedPetID: String {
        didSet { defaults.set(selectedPetID, forKey: Keys.selectedPetID) }
    }

    var executablePath: String {
        didSet { defaults.set(executablePath, forKey: Keys.executablePath) }
    }

    private(set) var availablePets: [LoadedPetPackage] = []
    private(set) var buckets: [UsageBucket] = []
    private(set) var selectedTask: SelectedTask?
    private(set) var codexRTTMilliseconds: Int64?
    private(set) var lastUpdated: Date?
    private(set) var lastErrorCode: String?

    @ObservationIgnored private let defaults: UserDefaults
    private var connectionPhase: ConnectionPhase = .connecting
    @ObservationIgnored private var periodicTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var interactionTask: Task<Void, Never>?
    @ObservationIgnored private var interactionGeneration: UInt64 = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        privacyMode = defaults.bool(forKey: Keys.privacyMode)
        selectedPetID = defaults.string(forKey: Keys.selectedPetID) ?? ""
        executablePath = defaults.string(forKey: Keys.executablePath) ?? ""
    }

    var selectedPet: LoadedPetPackage? {
        availablePets.first { $0.id == selectedPetID }
    }

    var collapsedRemainingPercent: Int? {
        RateLimitMapper.collapsedWindow(from: buckets)?.remainingPercent
    }

    var quotaAccessibilityLabel: String {
        guard let collapsedRemainingPercent else { return "usage unavailable" }
        return "\(collapsedRemainingPercent) percent remaining\(isStale ? ", stale" : "")"
    }

    var isStale: Bool {
        connectionPhase == .stale
    }

    var displayStatus: AppDisplayStatus {
        switch connectionPhase {
        case .connecting:
            return .connecting
        case .offline:
            return .offline
        case .stale:
            return .stale
        case .online:
            switch selectedTask?.state ?? .unavailable {
            case .offline: return .offline
            case .unavailable, .unknown: return .liveUnavailable
            case .idle: return .idle
            case .working: return .working
            case .waiting: return .waiting
            case .approval: return .approval
            case .failed: return .failed
            }
        }
    }

    var petAnimationState: PetAnimationState {
        if let interactionAnimation {
            return interactionAnimation
        }
        switch displayStatus {
        case .offline, .failed:
            return .failed
        case .working:
            return .running
        case .waiting:
            return .waiting
        case .approval:
            return .review
        case .connecting, .stale, .liveUnavailable, .idle:
            return .idle
        }
    }

    var presentedTaskTitle: String {
        if privacyMode { return "Private task" }
        return selectedTask?.title ?? "No recent task"
    }

    var presentedTaskLocation: String? {
        guard !privacyMode else { return nil }
        return selectedTask?.cwdBasename
    }

    var usageRows: [UsagePresentationRow] {
        buckets.flatMap { bucket in
            bucket.windows.enumerated().map { index, window in
                UsagePresentationRow(
                    id: "\(bucket.id ?? "bucket")-\(window.role.rawValue)-\(index)",
                    label: RateLimitMapper.label(for: window, in: bucket),
                    remainingPercent: window.remainingPercent,
                    resetsAt: window.resetsAt
                )
            }
        }
    }

    var connectionDetail: String {
        var components: [String] = []
        if let codexRTTMilliseconds {
            components.append("Codex RTT \(codexRTTMilliseconds) ms")
        }
        if let lastUpdated {
            components.append("Updated " + lastUpdated.formatted(date: .omitted, time: .shortened))
        }
        if let lastErrorCode, connectionPhase != .online {
            components.append("Error \(lastErrorCode)")
        }
        return components.isEmpty ? "Waiting for Codex" : components.joined(separator: " · ")
    }

    func start(previewMode: Bool) {
        loadPets()
        isPreviewMode = previewMode

        if previewMode {
            applyPreviewSnapshot()
            triggerPetAnimation(.waving, message: "Hi!")
            return
        }

        refresh()
        triggerPetAnimation(.waving, message: "Hi!")
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func stop() {
        periodicTask?.cancel()
        refreshTask?.cancel()
        interactionTask?.cancel()
        periodicTask = nil
        refreshTask = nil
        interactionTask = nil
    }

    func refresh() {
        guard !isPreviewMode, !isRefreshing else { return }
        isRefreshing = true
        if lastUpdated == nil {
            connectionPhase = .connecting
        }

        let trimmedPath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitPath = trimmedPath.isEmpty ? nil : trimmedPath

        refreshTask = Task { [weak self] in
            let outcome = await Task.detached(priority: .utility) {
                do {
                    return MonitorRefreshOutcome.success(
                        try CodexMonitorReader().read(explicitPath: explicitPath)
                    )
                } catch {
                    return MonitorRefreshOutcome.failure(
                        code: Self.sanitizedErrorCode(error)
                    )
                }
            }.value

            guard !Task.isCancelled else { return }
            self?.apply(outcome)
        }
    }

    func waveAtUser() {
        triggerPetAnimation(.waving, message: "Hello!")
    }

    func playWithUser() {
        triggerPetAnimation(.jumping, message: "Let's go!")
    }

    func recordTaskHandoff(opened: Bool) {
        if opened {
            taskDraft = ""
            taskHandoffFeedback = "Ready in Codex — review and send."
            triggerPetAnimation(.waving, message: "Ready in Codex!")
        } else {
            taskHandoffFeedback = "Couldn't open Codex."
        }
    }

    private func apply(_ outcome: MonitorRefreshOutcome) {
        let previousStatus = displayStatus
        isRefreshing = false
        refreshTask = nil

        switch outcome {
        case .success(let snapshot):
            buckets = snapshot.buckets
            selectedTask = snapshot.selectedTask
            codexRTTMilliseconds = snapshot.codexRTTMilliseconds
            lastUpdated = snapshot.updatedAt
            lastErrorCode = Self.taskReadErrorCode(snapshot.taskReadStatus)
            connectionPhase = .online
        case .failure(let code):
            lastErrorCode = code
            connectionPhase = lastUpdated == nil ? .offline : .stale
        }

        if displayStatus != previousStatus {
            cancelPetInteraction()
        }
    }

    private func loadPets() {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/pets", isDirectory: true)
        availablePets = PetLibrary.discover(in: root)

        if !availablePets.contains(where: { $0.id == selectedPetID }) {
            selectedPetID = availablePets.first(where: { $0.id == "miaomiao" })?.id
                ?? availablePets.first?.id
                ?? ""
        }
    }

    private func applyPreviewSnapshot() {
        let response = RateLimitReadResponse(
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                limitName: "Codex",
                primary: RateLimitWindow(
                    usedPercent: 36,
                    windowDurationMins: 300,
                    resetsAt: Int64(Date.now.addingTimeInterval(7_200).timeIntervalSince1970)
                ),
                secondary: RateLimitWindow(
                    usedPercent: 18,
                    windowDurationMins: 10_080,
                    resetsAt: Int64(Date.now.addingTimeInterval(172_800).timeIntervalSince1970)
                )
            ),
            rateLimitsByLimitId: nil
        )

        buckets = RateLimitMapper.buckets(from: response)
        selectedTask = SelectedTask(
            id: "preview",
            title: "Build the Codex-bangs macOS app",
            cwdBasename: "Codex-bangs",
            state: .unavailable,
            recencyAt: Int64(Date.now.timeIntervalSince1970)
        )
        codexRTTMilliseconds = 184
        lastUpdated = .now
        lastErrorCode = nil
        connectionPhase = .online
        isRefreshing = false
    }

    private func triggerPetAnimation(
        _ animation: PetAnimationState,
        message: String
    ) {
        guard interactionAnimation != animation else { return }
        interactionGeneration &+= 1
        let generation = interactionGeneration
        interactionTask?.cancel()
        interactionAnimation = animation
        petMessage = message

        interactionTask = Task { [weak self] in
            try? await Task.sleep(for: Self.singlePassDuration(for: animation))
            guard !Task.isCancelled,
                  let self,
                  self.interactionGeneration == generation else {
                return
            }
            self.interactionAnimation = nil
            self.petMessage = nil
            self.interactionTask = nil
        }
    }

    private func cancelPetInteraction() {
        interactionGeneration &+= 1
        interactionTask?.cancel()
        interactionTask = nil
        interactionAnimation = nil
        petMessage = nil
    }

    nonisolated private static func singlePassDuration(
        for animation: PetAnimationState
    ) -> Duration {
        let milliseconds = PetV2Contract.animationRows
            .first(where: { $0.state == animation })?
            .frameDurationsMilliseconds
            .reduce(0, +) ?? 800
        return .milliseconds(milliseconds)
    }

    nonisolated private static func sanitizedErrorCode(_ error: Error) -> String {
        if let readerError = error as? CodexMonitorReaderError,
           readerError == .executableNotFound {
            return "executable-not-found"
        }
        if let appServerError = error as? CodexAppServerError {
            switch appServerError {
            case .alreadyStarted: return "already-started"
            case .notStarted: return "not-started"
            case .processLaunchFailed: return "launch-failed"
            case .processExited: return "process-exited"
            case .requestTimedOut: return "timeout"
            case .writeFailed: return "write-failed"
            case .malformedResponse: return "malformed-response"
            case .rpcError(let code): return "rpc-\(code.map(String.init) ?? "unknown")"
            }
        }
        return "connection-failed"
    }

    nonisolated private static func taskReadErrorCode(
        _ status: CodexTaskReadStatus
    ) -> String? {
        switch status {
        case .success:
            return nil
        case .unavailable(let reason):
            return "task-\(reason.rawValue)"
        }
    }

    private enum Keys {
        static let privacyMode = "privacyMode"
        static let selectedPetID = "selectedPetID"
        static let executablePath = "codexExecutablePath"
    }
}
