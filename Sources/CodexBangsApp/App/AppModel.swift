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

struct PetImportFeedback: Equatable, Sendable {
    let message: String
    let isError: Bool
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

private enum PetImportOutcome: Sendable {
    case success(package: LoadedPetPackage, availablePets: [LoadedPetPackage])
    case failure(PetPackageInstallerError)
    case unknownFailure
}

private struct CapabilityDiscoveryOutcome: Sendable {
    let skills: [CodexSkillMetadata]
    let plugins: [ConfiguredCodexPlugin]
}

private enum PetTaskKind: Equatable, Sendable {
    case ask
    case guide
}

private enum PetTaskPreparationError: Error, Sendable {
    case executableNotFound
    case invalidWorkspace
}

@Observable
@MainActor
final class AppModel {
    static let builtInPetID = PetV2Contract.builtInPetIdentifier

    var isExpanded = false
    var isNotchRevealed = false
    var isRefreshing = false
    private(set) var voiceInputRequest: UInt64 = 0
    private(set) var voiceCancellationRequest: UInt64 = 0
    private(set) var isRefreshingCapabilities = false
    private(set) var isRunningPetTask = false
    private(set) var isVoiceSessionActive = false
    private(set) var isImportingPet = false
    private(set) var isTalkShortcutAvailable = true
    var isPreviewMode = false
    var taskDraft = ""
    private(set) var interactionAnimation: PetAnimationState?
    private(set) var petMessage: String?
    private(set) var taskHandoffFeedback: String?
    private(set) var taskResponse: String?
    private(set) var petImportFeedback: PetImportFeedback?

    var privacyMode: Bool {
        didSet { defaults.set(privacyMode, forKey: Keys.privacyMode) }
    }

    var selectedPetID: String {
        didSet {
            defaults.set(selectedPetID, forKey: Keys.selectedPetID)
            updateActiveProfilePetIfNeeded()
        }
    }

    var selectedAgentProfileID: String {
        didSet {
            defaults.set(selectedAgentProfileID, forKey: Keys.selectedAgentProfileID)
            synchronizePetWithActiveProfile()
        }
    }

    var executablePath: String {
        didSet { defaults.set(executablePath, forKey: Keys.executablePath) }
    }

    var taskWorkspacePath: String {
        didSet { defaults.set(taskWorkspacePath, forKey: Keys.taskWorkspacePath) }
    }

    private(set) var availablePets: [LoadedPetPackage] = []
    private(set) var availableSkills: [CodexSkillMetadata] = []
    private(set) var configuredPlugins: [ConfiguredCodexPlugin] = []
    private(set) var agentProfiles: [AgentPetProfile]
    private(set) var buckets: [UsageBucket] = []
    private(set) var selectedTask: SelectedTask?
    private(set) var codexRTTMilliseconds: Int64?
    private(set) var lastUpdated: Date?
    private(set) var lastErrorCode: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let petsRoot: URL
    private var connectionPhase: ConnectionPhase = .connecting
    @ObservationIgnored private var periodicTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var petDiscoveryTask: Task<Void, Never>?
    @ObservationIgnored private var petImportTask: Task<Void, Never>?
    @ObservationIgnored private var capabilityDiscoveryTask: Task<Void, Never>?
    @ObservationIgnored private var petTask: Task<Void, Never>?
    @ObservationIgnored private var taskRunner: CodexTaskRunner?
    @ObservationIgnored private var interactionTask: Task<Void, Never>?
    @ObservationIgnored private var petLibraryGeneration: UInt64 = 0
    @ObservationIgnored private var interactionGeneration: UInt64 = 0

    init(
        defaults: UserDefaults = .standard,
        petsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/pets", isDirectory: true)
    ) {
        self.defaults = defaults
        self.petsRoot = petsRoot
        let initialPetID = defaults.string(forKey: Keys.selectedPetID)
            ?? Self.builtInPetID
        let profiles = Self.initialAgentProfiles(
            from: defaults.data(forKey: Keys.agentProfiles),
            fallbackPetID: initialPetID
        )
        let storedProfileID = defaults.string(forKey: Keys.selectedAgentProfileID)
        let initialProfileID = storedProfileID.flatMap { candidate in
            profiles.contains(where: { $0.id == candidate }) ? candidate : nil
        } ?? profiles[0].id

        privacyMode = defaults.bool(forKey: Keys.privacyMode)
        selectedPetID = profiles.first(where: { $0.id == initialProfileID })?.petID
            ?? initialPetID
        selectedAgentProfileID = initialProfileID
        executablePath = defaults.string(forKey: Keys.executablePath) ?? ""
        taskWorkspacePath = defaults.string(forKey: Keys.taskWorkspacePath) ?? ""
        agentProfiles = profiles
    }

    var selectedPet: LoadedPetPackage? {
        availablePets.first { $0.id == selectedPetID }
    }

    var usesBuiltInPet: Bool {
        selectedPetID == Self.builtInPetID || selectedPet == nil
    }

    var activeAgentProfile: AgentPetProfile {
        agentProfiles.first(where: { $0.id == selectedAgentProfileID })
            ?? agentProfiles[0]
    }

    var activeAgentSelectedSkillIDs: Set<String> {
        let installed = Set(availableSkills.map(\.id))
        return Set(activeAgentProfile.selectedSkillIDs.filter(installed.contains))
    }

    var taskPromptForHandoff: String {
        CodexDesktopHandoff.truncatingToMaximumUTF8Bytes(
            composedTaskPrompt(from: taskDraft, enforceReadOnly: false)
        )
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
        if isRunningPetTask {
            return .running
        }
        if isVoiceSessionActive {
            return .lookDirectionsA
        }
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
        if isPreviewMode {
            return "Preview fixture · Not live Codex data"
        }

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
        reloadCapabilities()
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
        petDiscoveryTask?.cancel()
        petImportTask?.cancel()
        capabilityDiscoveryTask?.cancel()
        petTask?.cancel()
        taskRunner?.cancel()
        interactionTask?.cancel()
        petLibraryGeneration &+= 1
        isImportingPet = false
        periodicTask = nil
        refreshTask = nil
        petDiscoveryTask = nil
        petImportTask = nil
        capabilityDiscoveryTask = nil
        petTask = nil
        taskRunner = nil
        interactionTask = nil
        isRefreshingCapabilities = false
        isRunningPetTask = false
        isVoiceSessionActive = false
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

    func reloadCapabilities() {
        guard !isRefreshingCapabilities else { return }
        isRefreshingCapabilities = true
        capabilityDiscoveryTask?.cancel()

        capabilityDiscoveryTask = Task { [weak self] in
            let outcome = await Task.detached(priority: .utility) {
                CapabilityDiscoveryOutcome(
                    skills: CodexCapabilityDiscovery.discoverSkills(),
                    plugins: CodexCapabilityDiscovery.discoverConfiguredPlugins()
                )
            }.value

            guard !Task.isCancelled, let self else { return }
            self.availableSkills = outcome.skills
            self.configuredPlugins = outcome.plugins
            self.isRefreshingCapabilities = false
            self.capabilityDiscoveryTask = nil
        }
    }

    func activateAgentProfile(_ profileID: String) {
        guard agentProfiles.contains(where: { $0.id == profileID }) else { return }
        selectedAgentProfileID = profileID
        triggerPetAnimation(.waving, message: "\(activeAgentProfile.name) is here!")
    }

    func assignPet(_ petID: String, to profileID: String) {
        guard petID == Self.builtInPetID
                || availablePets.contains(where: { $0.id == petID }),
              let index = agentProfiles.firstIndex(where: { $0.id == profileID }) else {
            return
        }

        agentProfiles[index].petID = petID
        persistAgentProfiles()
        if profileID == selectedAgentProfileID {
            selectedPetID = petID
        }
    }

    func isSkillSelected(_ skillID: String, for profileID: String) -> Bool {
        agentProfiles.first(where: { $0.id == profileID })?
            .selectedSkillIDs.contains(skillID) == true
    }

    func setSkill(_ skillID: String, enabled: Bool, for profileID: String) {
        guard availableSkills.contains(where: { $0.id == skillID }),
              let index = agentProfiles.firstIndex(where: { $0.id == profileID }) else {
            return
        }

        var selected = agentProfiles[index].selectedSkillIDs
        if enabled {
            if !selected.contains(skillID) {
                selected.append(skillID)
            }
        } else {
            selected.removeAll { $0 == skillID }
        }
        agentProfiles[index].selectedSkillIDs = selected
        persistAgentProfiles()
    }

    func askPet() {
        runPetTask(.ask)
    }

    func guideMe() {
        runPetTask(.guide)
    }

    func cancelPetTask() {
        petTask?.cancel()
        taskRunner?.cancel()
    }

    func requestVoiceInput() {
        voiceInputRequest &+= 1
    }

    func requestVoiceCancellation() {
        voiceCancellationRequest &+= 1
    }

    func setVoiceSessionActive(_ isActive: Bool) {
        isVoiceSessionActive = isActive
    }

    func setTalkShortcutAvailable(_ isAvailable: Bool) {
        isTalkShortcutAvailable = isAvailable
    }

    func waveAtUser() {
        triggerPetAnimation(.waving, message: "Hello!")
    }

    func playWithUser() {
        triggerPetAnimation(.jumping, message: "Let's go!")
    }

    @discardableResult
    func importPetPackage(at packageURL: URL) -> Bool {
        guard petImportTask == nil else {
            petImportFeedback = PetImportFeedback(
                message: "Another pet is still importing. Try again when it finishes.",
                isError: true
            )
            return false
        }
        guard packageURL.pathExtension.caseInsensitiveCompare("codexpet") == .orderedSame else {
            petImportFeedback = PetImportFeedback(
                message: "Choose a .codexpet package.",
                isError: true
            )
            return false
        }

        petLibraryGeneration &+= 1
        let generation = petLibraryGeneration
        petDiscoveryTask?.cancel()
        petDiscoveryTask = nil

        let accessed = packageURL.startAccessingSecurityScopedResource()
        let destinationRoot = petsRoot
        isImportingPet = true
        petImportFeedback = nil

        petImportTask = Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                defer {
                    if accessed {
                        packageURL.stopAccessingSecurityScopedResource()
                    }
                }

                do {
                    let package = try PetPackageInstaller.install(
                        packageAt: packageURL,
                        into: destinationRoot
                    )
                    return PetImportOutcome.success(
                        package: package,
                        availablePets: PetLibrary.discover(in: destinationRoot)
                    )
                } catch let error as PetPackageInstallerError {
                    return PetImportOutcome.failure(error)
                } catch {
                    return PetImportOutcome.unknownFailure
                }
            }.value

            guard !Task.isCancelled,
                  let self,
                  self.petLibraryGeneration == generation else {
                return
            }
            self.petImportTask = nil
            self.isImportingPet = false
            self.apply(outcome)
        }

        return true
    }

    func reloadPets() {
        guard petImportTask == nil else { return }
        loadPets(selecting: selectedPetID)
    }

    func recordPetImportPickerFailure(_ error: Error) {
        guard !(error is CancellationError) else { return }
        let cocoaError = error as NSError
        guard !(cocoaError.domain == NSCocoaErrorDomain
                && cocoaError.code == NSUserCancelledError) else {
            return
        }
        petImportFeedback = PetImportFeedback(
            message: "The selected package couldn't be opened. Choose it again and retry.",
            isError: true
        )
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

    private func runPetTask(_ kind: PetTaskKind) {
        guard !isRunningPetTask else { return }

        let draft = taskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind == .ask, draft.isEmpty {
            taskHandoffFeedback = "Tell your pet what you need first."
            return
        }
        guard !isPreviewMode else {
            taskHandoffFeedback = "Direct Codex tasks are unavailable in Preview mode."
            return
        }

        let userPrompt = kind == .guide
            ? Self.guidePrompt(question: draft)
            : draft
        let prompt = composedTaskPrompt(
            from: userPrompt,
            enforceReadOnly: true
        )
        let explicitExecutablePath = executablePath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let configuredWorkspacePath = taskWorkspacePath

        isVoiceSessionActive = false
        isRunningPetTask = true
        taskResponse = nil
        taskHandoffFeedback = kind == .guide
            ? "Capturing this screen once…"
            : "Asking \(activeAgentProfile.name)…"
        triggerPetAnimation(.running, message: kind == .guide ? "Looking…" : "Working…")

        petTask = Task { [weak self] in
            guard let self else { return }
            var capture: EphemeralScreenCapture?
            defer { capture?.remove() }

            do {
                let executableURL = await Task.detached(priority: .userInitiated) {
                    CodexExecutableLocator.locate(
                        explicitPath: explicitExecutablePath.isEmpty
                            ? nil
                            : explicitExecutablePath
                    )
                }.value
                guard let executableURL else {
                    throw PetTaskPreparationError.executableNotFound
                }
                try Task.checkCancellation()

                let workspaceURL = try await Task.detached(priority: .utility) {
                    guard let url = Self.resolveTaskWorkspace(
                        configuredPath: configuredWorkspacePath
                    ) else {
                        throw PetTaskPreparationError.invalidWorkspace
                    }
                    return url
                }.value
                try Task.checkCancellation()

                if kind == .guide {
                    capture = try await ScreenCaptureService()
                        .captureDisplayUnderPointer()
                }
                try Task.checkCancellation()

                let runner = CodexTaskRunner(executableURL: executableURL)
                self.taskRunner = runner
                let result = try await runner.run(
                    CodexTaskRequest(
                        prompt: prompt,
                        workingDirectory: workspaceURL,
                        screenCapture: capture,
                        isEphemeral: kind == .guide
                    )
                )
                try Task.checkCancellation()
                self.finishPetTask(result: result, kind: kind)
            } catch {
                self.finishPetTask(error: error)
            }
        }
    }

    private func finishPetTask(result: CodexTaskResult, kind: PetTaskKind) {
        taskRunner = nil
        petTask = nil
        isRunningPetTask = false
        taskDraft = ""
        taskResponse = Self.boundedTaskResponse(result.finalMessage)
        taskHandoffFeedback = kind == .guide
            ? "One-time screenshot removed. Nothing was clicked."
            : "Codex task finished in read-only mode."
        triggerPetAnimation(.waving, message: "Done!")
        if kind == .ask {
            refresh()
        }
    }

    private func finishPetTask(error: Error) {
        taskRunner = nil
        petTask = nil
        isRunningPetTask = false

        if error is CancellationError {
            taskHandoffFeedback = "Stopped."
            triggerPetAnimation(.idle, message: "Stopped")
            return
        }

        switch error {
        case PetTaskPreparationError.executableNotFound:
            taskHandoffFeedback = "Couldn't find a supported Codex executable."
        case PetTaskPreparationError.invalidWorkspace:
            taskHandoffFeedback = "Choose an existing task folder in Settings."
        case ScreenCaptureServiceError.permissionDenied:
            taskHandoffFeedback = "Allow Screen Recording in System Settings, then relaunch Codex-bangs."
        case ScreenCaptureServiceError.noDisplayAvailable:
            taskHandoffFeedback = "No display is available to capture."
        case ScreenCaptureServiceError.captureFailed,
             ScreenCaptureServiceError.encodingFailed,
             ScreenCaptureServiceError.storageFailed:
            taskHandoffFeedback = "The one-time screenshot couldn't be prepared."
        case CodexTaskRunnerError.outputLimitExceeded:
            taskHandoffFeedback = "Codex returned more text than this panel can safely display."
        case is CodexTaskRunnerError:
            taskHandoffFeedback = "Codex couldn't finish this read-only task."
        default:
            taskHandoffFeedback = "The pet task couldn't be completed."
        }
        triggerPetAnimation(.failed, message: "Try again")
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

    private func loadPets(selecting preferredID: String? = nil) {
        petLibraryGeneration &+= 1
        let generation = petLibraryGeneration
        petDiscoveryTask?.cancel()
        let root = petsRoot

        petDiscoveryTask = Task { [weak self] in
            let pets = await Task.detached(priority: .utility) {
                PetLibrary.discover(in: root)
            }.value

            guard !Task.isCancelled,
                  let self,
                  self.petLibraryGeneration == generation else {
                return
            }
            self.petDiscoveryTask = nil
            self.applyDiscoveredPets(pets, selecting: preferredID)
        }
    }

    private func apply(_ outcome: PetImportOutcome) {
        switch outcome {
        case .success(let package, let discoveredPets):
            applyDiscoveredPets(discoveredPets, selecting: package.id)
            petImportFeedback = PetImportFeedback(
                message: "\(package.manifest.displayName) is ready and selected.",
                isError: false
            )
            triggerPetAnimation(.waving, message: "New pet ready!")
        case .failure(let error):
            petImportFeedback = PetImportFeedback(
                message: Self.petImportMessage(for: error),
                isError: true
            )
            loadPets(selecting: selectedPetID)
        case .unknownFailure:
            petImportFeedback = PetImportFeedback(
                message: "That pet package couldn't be imported.",
                isError: true
            )
            loadPets(selecting: selectedPetID)
        }
    }

    private func applyDiscoveredPets(
        _ discoveredPets: [LoadedPetPackage],
        selecting preferredID: String?
    ) {
        availablePets = discoveredPets

        if let preferredID,
           (preferredID == Self.builtInPetID
                || discoveredPets.contains(where: { $0.id == preferredID })) {
            selectedPetID = preferredID
        } else if selectedPetID == Self.builtInPetID
                    || discoveredPets.contains(where: { $0.id == selectedPetID }) {
            return
        } else {
            selectedPetID = Self.builtInPetID
        }
    }

    private func synchronizePetWithActiveProfile() {
        let petID = activeAgentProfile.petID
        guard selectedPetID != petID else { return }
        selectedPetID = petID
    }

    private func updateActiveProfilePetIfNeeded() {
        guard let index = agentProfiles.firstIndex(where: {
            $0.id == selectedAgentProfileID
        }), agentProfiles[index].petID != selectedPetID else {
            return
        }
        agentProfiles[index].petID = selectedPetID
        persistAgentProfiles()
    }

    private func persistAgentProfiles() {
        guard let data = try? JSONEncoder().encode(agentProfiles) else { return }
        defaults.set(data, forKey: Keys.agentProfiles)
    }

    private func composedTaskPrompt(
        from userPrompt: String,
        enforceReadOnly: Bool
    ) -> String {
        let trimmed = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = activeAgentProfile
        let installedSkillIDs = Set(availableSkills.map(\.id))
        let skillPrefix = profile.selectedSkillIDs
            .filter(installedSkillIDs.contains)
            .map { "$\($0)" }
            .joined(separator: " ")

        var sections = [
            skillPrefix,
            Self.roleInstruction(for: profile.role),
        ]
        if enforceReadOnly {
            sections.append(
                "Do not perform external side effects through plugins or connected apps. Use read-only tools only."
            )
        }
        sections.append(trimmed)
        return sections
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    nonisolated private static func roleInstruction(for role: AgentPetRole) -> String {
        switch role {
        case .builder:
            return "Act as a focused builder. Give a concrete, verifiable result."
        case .reviewer:
            return "Act as a careful reviewer. Prioritize correctness, risk, and evidence."
        case .guide:
            return "Act as a concise guide. Explain the next action in clear steps."
        case .custom:
            return "Help with the request clearly and concretely."
        }
    }

    nonisolated private static func guidePrompt(question: String) -> String {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = trimmed.isEmpty
            ? "Tell me what I should do next."
            : trimmed
        return """
        Analyze only the attached one-time screenshot. Do not click, type, control the computer, or call tools that change files or external systems. Explain what is visible, then give at most three concrete next steps.

        Question: \(request)
        """
    }

    nonisolated private static func resolveTaskWorkspace(
        configuredPath: String
    ) -> URL? {
        let fileManager = FileManager.default
        let trimmed = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let usesPrivateDefault = trimmed.isEmpty

        let candidate: URL
        if usesPrivateDefault {
            guard let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                return nil
            }
            candidate = applicationSupport
                .appendingPathComponent("Codex-bangs", isDirectory: true)
                .appendingPathComponent("Assistant Tasks", isDirectory: true)
            do {
                try fileManager.createDirectory(
                    at: candidate,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                return nil
            }
        } else {
            candidate = URL(
                fileURLWithPath: (trimmed as NSString).expandingTildeInPath,
                isDirectory: true
            ).resolvingSymlinksInPath()
        }

        guard let values = try? candidate.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ]), values.isDirectory == true, values.isSymbolicLink != true else {
            return nil
        }
        if usesPrivateDefault {
            do {
                try fileManager.setAttributes(
                    [.posixPermissions: 0o700],
                    ofItemAtPath: candidate.path
                )
            } catch {
                return nil
            }
        }
        return candidate.standardizedFileURL
    }

    nonisolated private static func boundedTaskResponse(_ response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let maximumCharacters = 6_000
        guard trimmed.count > maximumCharacters else { return trimmed }
        return String(trimmed.prefix(maximumCharacters)) + "…"
    }

    nonisolated private static func initialAgentProfiles(
        from data: Data?,
        fallbackPetID: String
    ) -> [AgentPetProfile] {
        let persisted = data.flatMap {
            try? JSONDecoder().decode([AgentPetProfile].self, from: $0)
        } ?? []

        return AgentPetProfile.builtIns.map { builtIn in
            guard let saved = persisted.first(where: { $0.id == builtIn.id }) else {
                return AgentPetProfile(
                    id: builtIn.id,
                    name: builtIn.name,
                    role: builtIn.role,
                    petID: fallbackPetID
                )
            }
            return AgentPetProfile(
                id: builtIn.id,
                name: builtIn.name,
                role: builtIn.role,
                petID: saved.petID.isEmpty ? fallbackPetID : saved.petID,
                selectedSkillIDs: saved.selectedSkillIDs
            )
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

    nonisolated private static func petImportMessage(
        for error: PetPackageInstallerError
    ) -> String {
        switch error {
        case .destinationAlreadyExists:
            return "A pet with this ID is already installed. Change the id in pet.json and export again."
        case .invalidPackageExtension:
            return "Choose a .codexpet package."
        case .missingOrNonRegularManifest:
            return "This package needs a regular pet.json file at its top level."
        case .manifestTooLarge(let maximumByteCount):
            return "pet.json is too large. Keep it under \(maximumByteCount / 1_024) KB."
        case .invalidManifest:
            return "pet.json couldn't be read. Export the pet again using the Codex pet v2 format."
        case .invalidManifestContract(let validationError):
            switch validationError {
            case .unsupportedSpriteVersion(let version):
                return "This pet uses sprite version \(version). Export it as Codex pet v2."
            case .missingIdentifier:
                return "pet.json needs a lowercase id before this pet can be installed."
            case .reservedIdentifier:
                return "The built-in pet ID is reserved. Choose a different id in pet.json."
            case .unsafeSpritesheetPath:
                return "This .codexpet package is invalid or unsafe."
            }
        case .invalidDisplayName:
            return "pet.json needs a displayName no longer than 128 bytes."
        case .missingOrNonRegularSpritesheet:
            return "The atlas referenced by pet.json is missing. Export the complete package again."
        case .unsupportedSpritesheetFormat:
            return "Use a PNG or WebP atlas, then export the pet again."
        case .spritesheetTooLarge(let maximumByteCount):
            return "The atlas is too large. Keep it under \(maximumByteCount / 1_024 / 1_024) MB."
        case .undecodableSpritesheet:
            return "The atlas couldn't be decoded. Re-export it as PNG or WebP."
        case .invalidAtlasSize(let width, let height):
            return "The atlas is \(width)x\(height). Codex pet v2 requires exactly \(PetV2Contract.atlasWidth)x\(PetV2Contract.atlasHeight)."
        case .invalidPetsRoot,
             .unsafePackageDirectory,
             .invalidIdentifier,
             .unsafeSpritesheetPath,
             .stagingFailed,
             .installationFailed:
            return "This .codexpet package is invalid or unsafe."
        }
    }

    private enum Keys {
        static let privacyMode = "privacyMode"
        static let selectedPetID = "selectedPetID"
        static let selectedAgentProfileID = "selectedAgentProfileID"
        static let agentProfiles = "agentPetProfiles"
        static let executablePath = "codexExecutablePath"
        static let taskWorkspacePath = "taskWorkspacePath"
    }
}
