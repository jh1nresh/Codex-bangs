import Foundation
import Darwin

private final class BoundedOutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let limit: Int

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard data.count < limit else { return }
        data.append(chunk.prefix(limit - data.count))
    }

    func string() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum CodexExecutableLocator {
    public static let bundledCandidates = [
        "/Applications/Codex.app/Contents/Resources/codex",
        "/Applications/ChatGPT.app/Contents/Resources/codex"
    ]

    public static func locate(
        explicitPath: String? = nil,
        bundledPaths: [String] = bundledCandidates,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates: [String] = []

        if let explicitPath, !explicitPath.isEmpty {
            candidates.append(explicitPath)
        }
        candidates.append(contentsOf: bundledPaths)

        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map {
                String($0) + "/codex"
            })
        }

        for candidate in candidates {
            let expanded = (candidate as NSString).expandingTildeInPath
            let resolved = URL(fileURLWithPath: expanded).resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false

            guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  fileManager.isExecutableFile(atPath: resolved.path),
                  (try? resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  versionString(at: resolved) != nil else {
                continue
            }

            return resolved
        }

        return nil
    }

    public static func versionString(
        at executableURL: URL,
        timeout: TimeInterval = 3
    ) -> String? {
        let process = Process()
        let output = Pipe()
        let capture = BoundedOutputCapture(limit: 4_096)
        process.executableURL = executableURL
        process.arguments = ["--version"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            capture.append(chunk)
        }

        guard (try? process.run()) != nil else {
            output.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }

        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
        output.fileHandleForReading.readabilityHandler = nil
        capture.append(output.fileHandleForReading.readDataToEndOfFile())

        guard process.terminationStatus == 0,
              let version = capture.string(),
              !version.isEmpty else {
            return nil
        }
        return version
    }
}
