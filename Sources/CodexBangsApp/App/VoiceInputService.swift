@preconcurrency import AVFoundation
import Foundation
import Observation
@preconcurrency import Speech

private final class SpeechAudioBufferSink: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest

    init(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
    }
}

@Observable
@MainActor
final class VoiceInputService {
    enum Phase: Equatable, Sendable {
        case idle
        case requestingPermission
        case listening
        case finalizing
        case ready
        case error
    }

    private enum PermissionResult: Sendable {
        case authorized
        case denied
        case restricted
    }

    private(set) var phase: Phase = .idle
    private(set) var transcript = ""
    private(set) var errorMessage: String?

    var isListening: Bool {
        phase == .listening
    }

    var isActive: Bool {
        switch phase {
        case .requestingPermission, .listening, .finalizing:
            return true
        case .idle, .ready, .error:
            return false
        }
    }

    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var speechRecognizer: SFSpeechRecognizer?
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var maximumDurationTask: Task<Void, Never>?
    @ObservationIgnored private var finalizationTask: Task<Void, Never>?
    @ObservationIgnored private var hasInstalledAudioTap = false
    @ObservationIgnored private var generation: UInt64 = 0

    func start() async {
        tearDownResources(invalidateCallbacks: true)
        transcript = ""
        errorMessage = nil
        phase = .requestingPermission
        let sessionGeneration = generation

        let speechPermission = await requestSpeechRecognitionPermission()
        guard generation == sessionGeneration else { return }
        guard speechPermission == .authorized else {
            switch speechPermission {
            case .denied:
                fail(
                    "Speech Recognition access is off. Enable Codex-bangs in System Settings → Privacy & Security → Speech Recognition."
                )
            case .restricted:
                fail("Speech Recognition is restricted on this Mac.")
            case .authorized:
                break
            }
            return
        }

        let microphonePermission = await requestMicrophonePermission()
        guard generation == sessionGeneration else { return }
        guard microphonePermission == .authorized else {
            switch microphonePermission {
            case .denied:
                fail(
                    "Microphone access is off. Enable Codex-bangs in System Settings → Privacy & Security → Microphone."
                )
            case .restricted:
                fail("Microphone access is restricted on this Mac.")
            case .authorized:
                break
            }
            return
        }

        guard let recognizer = SFSpeechRecognizer(locale: .autoupdatingCurrent) else {
            fail("Speech recognition isn’t available for the current language.")
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            fail(
                "On-device speech recognition isn’t available for the current language. Choose another dictation language in System Settings and try again."
            )
            return
        }
        guard recognizer.isAvailable else {
            fail("Speech recognition is unavailable right now. Try again in a moment.")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            fail("No microphone input is available. Check your Mac’s sound input settings.")
            return
        }

        speechRecognizer = recognizer
        recognitionRequest = request

        let sink = SpeechAudioBufferSink(request: request)
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: recordingFormat
        ) { buffer, _ in
            sink.append(buffer)
        }
        hasInstalledAudioTap = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let recognizedText = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            let didFail = error != nil

            Task { @MainActor [weak self] in
                self?.receiveRecognitionResult(
                    text: recognizedText,
                    isFinal: isFinal,
                    didFail: didFail,
                    generation: sessionGeneration
                )
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            fail(
                "I couldn’t start the microphone. Check your sound input and microphone permission, then try again."
            )
            return
        }

        guard generation == sessionGeneration else {
            tearDownResources(invalidateCallbacks: false)
            return
        }

        phase = .listening
        maximumDurationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                return
            }
            self?.finish()
        }
    }

    /// Stops listening and prepares the current transcript for review. It never submits a task.
    func finish() {
        guard phase == .listening else { return }

        phase = .finalizing
        maximumDurationTask?.cancel()
        maximumDurationTask = nil
        stopAudioInput(endRecognitionAudio: true)

        let sessionGeneration = generation
        finalizationTask?.cancel()
        finalizationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(900))
            } catch {
                return
            }
            guard let self, self.generation == sessionGeneration else { return }
            self.completeReview()
        }
    }

    /// Abandons an in-progress or reviewed recording and returns to the idle state.
    func cancel() {
        tearDownResources(invalidateCallbacks: true)
        transcript = ""
        errorMessage = nil
        phase = .idle
    }

    /// Clears a completed transcript or error so a fresh recording can begin.
    func reset() {
        cancel()
    }

    private func receiveRecognitionResult(
        text: String?,
        isFinal: Bool,
        didFail: Bool,
        generation resultGeneration: UInt64
    ) {
        guard resultGeneration == generation else { return }
        guard phase == .listening || phase == .finalizing else { return }

        if let text {
            transcript = text
        }

        if isFinal {
            completeReview()
        } else if didFail {
            if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fail("I couldn’t hear that clearly. Check your microphone and try again.")
            } else {
                completeReview()
            }
        }
    }

    private func completeReview() {
        let reviewedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        tearDownResources(invalidateCallbacks: true)
        transcript = reviewedTranscript

        if reviewedTranscript.isEmpty {
            errorMessage = "I didn’t hear anything. Try speaking a little closer to the microphone."
            phase = .error
        } else {
            errorMessage = nil
            phase = .ready
        }
    }

    private func fail(_ message: String) {
        tearDownResources(invalidateCallbacks: true)
        errorMessage = message
        phase = .error
    }

    private func tearDownResources(invalidateCallbacks: Bool) {
        if invalidateCallbacks {
            generation &+= 1
        }

        maximumDurationTask?.cancel()
        maximumDurationTask = nil
        finalizationTask?.cancel()
        finalizationTask = nil

        stopAudioInput(endRecognitionAudio: true)
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        speechRecognizer = nil
        audioEngine.reset()
    }

    private func stopAudioInput(endRecognitionAudio: Bool) {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInstalledAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledAudioTap = false
        }
        if endRecognitionAudio {
            recognitionRequest?.endAudio()
        }
    }

    private func requestSpeechRecognitionPermission() async -> PermissionResult {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: Self.permissionResult(for: status))
                }
            }
        @unknown default:
            return .restricted
        }
    }

    private func requestMicrophonePermission() async -> PermissionResult {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio) ? .authorized : .denied
        @unknown default:
            return .restricted
        }
    }

    nonisolated private static func permissionResult(
        for status: SFSpeechRecognizerAuthorizationStatus
    ) -> PermissionResult {
        switch status {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .restricted
        @unknown default:
            return .restricted
        }
    }
}
