@preconcurrency import Foundation
import Darwin

public enum CodexAppServerError: Error, Equatable, Sendable {
    case alreadyStarted
    case notStarted
    case processLaunchFailed
    case processExited(Int32)
    case requestTimedOut
    case writeFailed
    case malformedResponse
    case rpcError(code: Int?)
}

public struct ServerNotification: Sendable {
    public let method: String
    public let params: Data?

    public init(method: String, params: Data?) {
        self.method = method
        self.params = params
    }
}

public struct ThreadStatusChangedNotification: Decodable, Sendable {
    public let threadId: String
    public let status: ThreadStatusPayload

    public init(threadId: String, status: ThreadStatusPayload) {
        self.threadId = threadId
        self.status = status
    }
}

private final class PendingResponse: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var result: Result<Data, CodexAppServerError>?

    func resolve(_ result: Result<Data, CodexAppServerError>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        lock.unlock()
        semaphore.signal()
    }

    func wait(timeout: TimeInterval) -> Result<Data, CodexAppServerError>? {
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}

public final class CodexAppServerClient: @unchecked Sendable {
    public typealias NotificationHandler = @Sendable (ServerNotification) -> Void

    private let executableURL: URL
    private let maximumLineBytes: Int
    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()
    private let processingQueue = DispatchQueue(label: "CodexNotchPet.app-server.stdout")
    private let stateLock = NSLock()
    private let writeLock = NSLock()

    private var outputBuffer = Data()
    private var nextRequestID = 1
    private var pendingResponses: [Int: PendingResponse] = [:]
    private var notificationHandler: NotificationHandler?
    private var hasStarted = false
    private var cleanedUp = false
    private var started = false
    private var exitStatus: Int32?
    private var stderrBytes = 0
    private var malformedLines = 0
    private var discardingOversizedLine = false

    public init(executableURL: URL, maximumLineBytes: Int = 1_048_576) {
        self.executableURL = executableURL
        self.maximumLineBytes = maximumLineBytes
    }

    deinit {
        stop()
    }

    public var observedStderrByteCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stderrBytes
    }

    public var malformedLineCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return malformedLines
    }

    public var isConnected: Bool {
        stateLock.lock()
        let connectionOpen = started && exitStatus == nil
        stateLock.unlock()
        return connectionOpen && process.isRunning
    }

    public func setNotificationHandler(_ handler: NotificationHandler?) {
        stateLock.lock()
        notificationHandler = handler
        stateLock.unlock()
    }

    public func start() throws {
        stateLock.lock()
        guard !hasStarted else {
            stateLock.unlock()
            throw CodexAppServerError.alreadyStarted
        }
        hasStarted = true
        started = true
        stateLock.unlock()

        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let client = self else { return }
            client.processingQueue.async {
                client.consumeOutput(data)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            self.stateLock.lock()
            self.stderrBytes += data.count
            self.stateLock.unlock()
        }

        process.terminationHandler = { [weak self] process in
            self?.recordTermination(process.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            stateLock.lock()
            started = false
            cleanedUp = true
            stateLock.unlock()
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw CodexAppServerError.processLaunchFailed
        }
    }

    public func stop() {
        stateLock.lock()
        guard hasStarted, !cleanedUp else {
            stateLock.unlock()
            return
        }
        cleanedUp = true
        started = false
        stateLock.unlock()

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        try? inputPipe.fileHandleForWriting.close()

        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(1)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
        }

        failAllPending(with: .processExited(process.terminationStatus))
    }

    public func initialize(clientVersion: String = "0.1.0", timeout: TimeInterval = 5) throws {
        struct InitializeResponse: Decodable {}

        let params: [String: Any] = [
            "clientInfo": [
                "name": "CodexNotchPet",
                "version": clientVersion
            ],
            "capabilities": [
                "experimentalApi": true
            ]
        ]

        let _: InitializeResponse = try request(
            method: "initialize",
            params: params,
            timeout: timeout
        )
        try sendNotification(method: "initialized")
    }

    public func request<Response: Decodable>(
        method: String,
        params: Any? = nil,
        timeout: TimeInterval = 5,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> Response {
        stateLock.lock()
        guard started else {
            stateLock.unlock()
            throw CodexAppServerError.notStarted
        }
        let requestID = nextRequestID
        nextRequestID += 1
        let pending = PendingResponse()
        pendingResponses[requestID] = pending
        stateLock.unlock()

        var message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": method
        ]
        if let params {
            message["params"] = params
        }

        do {
            try write(message)
        } catch {
            removePending(requestID)
            throw CodexAppServerError.writeFailed
        }

        guard let result = pending.wait(timeout: timeout) else {
            removePending(requestID)
            throw CodexAppServerError.requestTimedOut
        }

        let data = try result.get()
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw CodexAppServerError.malformedResponse
        }
    }

    public func sendNotification(method: String, params: Any? = nil) throws {
        stateLock.lock()
        let isStarted = started
        stateLock.unlock()
        guard isStarted else { throw CodexAppServerError.notStarted }

        var message: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method
        ]
        if let params {
            message["params"] = params
        }
        try write(message)
    }

    private func write(_ object: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw CodexAppServerError.writeFailed
        }

        var data = try JSONSerialization.data(withJSONObject: object, options: [])
        data.append(0x0A)

        writeLock.lock()
        defer { writeLock.unlock() }
        try inputPipe.fileHandleForWriting.write(contentsOf: data)
    }

    private func consumeOutput(_ data: Data) {
        var incoming = data

        if discardingOversizedLine {
            guard let newline = incoming.firstIndex(of: 0x0A) else { return }
            incoming.removeSubrange(...newline)
            discardingOversizedLine = false
        }

        outputBuffer.append(incoming)

        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            var line = outputBuffer.prefix(upTo: newline)
            outputBuffer.removeSubrange(...newline)

            if line.last == 0x0D {
                line = line.dropLast()
            }
            guard !line.isEmpty else { continue }
            guard line.count <= maximumLineBytes else {
                incrementMalformedLines()
                continue
            }
            handleLine(Data(line))
        }

        if outputBuffer.count > maximumLineBytes {
            outputBuffer.removeAll(keepingCapacity: true)
            discardingOversizedLine = true
            incrementMalformedLines()
        }
    }

    private func handleLine(_ line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            incrementMalformedLines()
            return
        }

        if let method = object["method"] as? String {
            let params = object["params"].flatMap(serializeFragment)
            stateLock.lock()
            let handler = notificationHandler
            stateLock.unlock()
            handler?(ServerNotification(method: method, params: params))

            if let requestID = object["id"] as? NSNumber {
                rejectServerRequest(id: requestID)
            } else if let requestID = object["id"] as? String {
                rejectServerRequest(id: requestID)
            }
            return
        }

        if let id = (object["id"] as? NSNumber)?.intValue {
            let pending = takePending(id)
            guard let pending else { return }

            if let error = object["error"] as? [String: Any] {
                let code = (error["code"] as? NSNumber)?.intValue
                pending.resolve(.failure(.rpcError(code: code)))
                return
            }

            guard let result = object["result"],
                  let resultData = serializeFragment(result) else {
                pending.resolve(.failure(.malformedResponse))
                return
            }
            pending.resolve(.success(resultData))
            return
        }

        incrementMalformedLines()
    }

    private func serializeFragment(_ value: Any) -> Data? {
        if JSONSerialization.isValidJSONObject(value) {
            return try? JSONSerialization.data(withJSONObject: value)
        }
        if value is NSNull {
            return Data("null".utf8)
        }
        return nil
    }

    private func takePending(_ id: Int) -> PendingResponse? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return pendingResponses.removeValue(forKey: id)
    }

    private func removePending(_ id: Int) {
        stateLock.lock()
        pendingResponses.removeValue(forKey: id)
        stateLock.unlock()
    }

    private func failAllPending(with error: CodexAppServerError) {
        stateLock.lock()
        let pending = Array(pendingResponses.values)
        pendingResponses.removeAll()
        stateLock.unlock()

        for response in pending {
            response.resolve(.failure(error))
        }
    }

    private func recordTermination(_ status: Int32) {
        stateLock.lock()
        started = false
        exitStatus = status
        stateLock.unlock()
        failAllPending(with: .processExited(status))
    }

    private func rejectServerRequest(id: Any) {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "error": [
                "code": -32_601,
                "message": "Method unavailable in read-only monitor"
            ]
        ]
        try? write(response)
    }

    private func incrementMalformedLines() {
        stateLock.lock()
        malformedLines += 1
        stateLock.unlock()
    }
}
