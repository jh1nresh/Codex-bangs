import Darwin
import Foundation

public enum HatchPetSkillPresence: Equatable, Sendable {
    case missing
    case installed
    case blockedByExistingEntry
}

public enum HatchPetSkillInstallerError: Error, Equatable, Sendable {
    case invalidSkillsRoot
    case invalidBundledSource
    case missingRequiredResource(String)
    case unsafeBundledResource(String)
    case destinationAlreadyExists
    case stagingFailed
    case installationFailed
}

extension HatchPetSkillInstallerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidSkillsRoot:
            return "The Codex skills folder is not a safe local directory."
        case .invalidBundledSource:
            return "This app build does not contain a valid hatch-pet skill."
        case .missingRequiredResource(let path):
            return "The bundled hatch-pet skill is missing \(path)."
        case .unsafeBundledResource(let path):
            return "The bundled hatch-pet resource is unsafe: \(path)."
        case .destinationAlreadyExists:
            return "A hatch-pet item already exists. Codex-bangs did not replace it."
        case .stagingFailed:
            return "Codex-bangs could not prepare the hatch-pet installation."
        case .installationFailed:
            return "Codex-bangs could not finish installing hatch-pet."
        }
    }
}

public enum HatchPetSkillInstaller {
    public static let skillDirectoryName = "hatch-pet"

    public static func destinationURL(in skillsRoot: URL) -> URL {
        skillsRoot.appendingPathComponent(skillDirectoryName, isDirectory: true)
    }

    public static func presence(
        in skillsRoot: URL,
        fileManager: FileManager = .default
    ) -> HatchPetSkillPresence {
        let destination = destinationURL(in: skillsRoot)
        switch fileType(at: destination, fileManager: fileManager) {
        case nil:
            return .missing
        case .typeDirectory:
            let manifest = destination.appendingPathComponent("SKILL.md")
            return fileType(at: manifest, fileManager: fileManager) == .typeRegular
                ? .installed
                : .blockedByExistingEntry
        default:
            return .blockedByExistingEntry
        }
    }

    @discardableResult
    public static func install(
        bundledSkillAt sourceURL: URL,
        into skillsRoot: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        try validateBundledSource(sourceURL, fileManager: fileManager)
        try prepareSkillsRoot(skillsRoot, fileManager: fileManager)

        let destination = destinationURL(in: skillsRoot)
        guard !pathEntryExists(at: destination, fileManager: fileManager) else {
            throw HatchPetSkillInstallerError.destinationAlreadyExists
        }

        let stagingRoot = skillsRoot.appendingPathComponent(
            ".hatch-pet-install-\(UUID().uuidString)",
            isDirectory: true
        )
        var createdStagingRoot: URL?
        defer {
            if let createdStagingRoot {
                try? fileManager.removeItem(at: createdStagingRoot)
            }
        }

        do {
            try fileManager.createDirectory(
                at: stagingRoot,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            createdStagingRoot = stagingRoot
        } catch {
            throw HatchPetSkillInstallerError.stagingFailed
        }

        let stagedSkill = stagingRoot.appendingPathComponent(
            skillDirectoryName,
            isDirectory: true
        )

        do {
            try fileManager.createDirectory(
                at: stagedSkill,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            try copyAllowlistedResources(
                from: sourceURL,
                to: stagedSkill,
                fileManager: fileManager
            )
        } catch let error as HatchPetSkillInstallerError {
            throw error
        } catch {
            throw HatchPetSkillInstallerError.stagingFailed
        }

        try moveExclusively(
            from: stagedSkill,
            to: destination,
            fileManager: fileManager
        )
        return destination.standardizedFileURL
    }

    private static let requiredFiles = ["SKILL.md", "LICENSE.txt"]
    private static let requiredDirectories = ["agents", "references", "scripts"]

    private static func validateBundledSource(
        _ sourceURL: URL,
        fileManager: FileManager
    ) throws {
        guard sourceURL.isFileURL,
              fileType(at: sourceURL, fileManager: fileManager) == .typeDirectory else {
            throw HatchPetSkillInstallerError.invalidBundledSource
        }

        for name in requiredFiles {
            let resource = sourceURL.appendingPathComponent(name, isDirectory: false)
            guard fileType(at: resource, fileManager: fileManager) == .typeRegular else {
                throw HatchPetSkillInstallerError.missingRequiredResource(name)
            }
        }

        for name in requiredDirectories {
            let resource = sourceURL.appendingPathComponent(name, isDirectory: true)
            guard fileType(at: resource, fileManager: fileManager) == .typeDirectory else {
                throw HatchPetSkillInstallerError.missingRequiredResource(name)
            }
            try validateTree(
                at: resource,
                relativeTo: sourceURL,
                fileManager: fileManager
            )
        }
    }

    private static func validateTree(
        at url: URL,
        relativeTo sourceRoot: URL,
        fileManager: FileManager
    ) throws {
        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            throw HatchPetSkillInstallerError.unsafeBundledResource(
                relativePath(of: url, from: sourceRoot)
            )
        }

        for child in children {
            let relativePath = relativePath(of: child, from: sourceRoot)
            guard child.lastPathComponent != "__pycache__",
                  child.lastPathComponent != "tests",
                  child.pathExtension.lowercased() != "pyc" else {
                throw HatchPetSkillInstallerError.unsafeBundledResource(relativePath)
            }

            switch fileType(at: child, fileManager: fileManager) {
            case .typeRegular:
                continue
            case .typeDirectory:
                try validateTree(
                    at: child,
                    relativeTo: sourceRoot,
                    fileManager: fileManager
                )
            default:
                throw HatchPetSkillInstallerError.unsafeBundledResource(relativePath)
            }
        }
    }

    private static func prepareSkillsRoot(
        _ skillsRoot: URL,
        fileManager: FileManager
    ) throws {
        guard skillsRoot.isFileURL else {
            throw HatchPetSkillInstallerError.invalidSkillsRoot
        }

        if let type = fileType(at: skillsRoot, fileManager: fileManager) {
            guard type == .typeDirectory else {
                throw HatchPetSkillInstallerError.invalidSkillsRoot
            }
            return
        }

        let parent = skillsRoot.deletingLastPathComponent()
        guard fileType(at: parent, fileManager: fileManager) == .typeDirectory else {
            throw HatchPetSkillInstallerError.invalidSkillsRoot
        }

        do {
            try fileManager.createDirectory(
                at: skillsRoot,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw HatchPetSkillInstallerError.invalidSkillsRoot
        }

        guard fileType(at: skillsRoot, fileManager: fileManager) == .typeDirectory else {
            throw HatchPetSkillInstallerError.invalidSkillsRoot
        }
    }

    private static func copyAllowlistedResources(
        from sourceRoot: URL,
        to destinationRoot: URL,
        fileManager: FileManager
    ) throws {
        for name in requiredFiles + requiredDirectories {
            let source = sourceRoot.appendingPathComponent(name)
            let destination = destinationRoot.appendingPathComponent(name)
            try copyTree(
                from: source,
                to: destination,
                sourceRoot: sourceRoot,
                fileManager: fileManager
            )
        }
    }

    private static func copyTree(
        from source: URL,
        to destination: URL,
        sourceRoot: URL,
        fileManager: FileManager
    ) throws {
        let relativePath = relativePath(of: source, from: sourceRoot)
        switch fileType(at: source, fileManager: fileManager) {
        case .typeRegular:
            try copyRegularFile(
                from: source,
                to: destination,
                relativePath: relativePath,
                fileManager: fileManager
            )
        case .typeDirectory:
            do {
                try fileManager.createDirectory(
                    at: destination,
                    withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700]
                )
                let children = try fileManager.contentsOfDirectory(
                    at: source,
                    includingPropertiesForKeys: nil,
                    options: []
                )
                for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    try copyTree(
                        from: child,
                        to: destination.appendingPathComponent(child.lastPathComponent),
                        sourceRoot: sourceRoot,
                        fileManager: fileManager
                    )
                }
            } catch let error as HatchPetSkillInstallerError {
                throw error
            } catch {
                throw HatchPetSkillInstallerError.stagingFailed
            }
        default:
            throw HatchPetSkillInstallerError.unsafeBundledResource(relativePath)
        }
    }

    private static func copyRegularFile(
        from source: URL,
        to destination: URL,
        relativePath: String,
        fileManager: FileManager
    ) throws {
        let descriptor = source.path.withCString { path in
            Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        }
        guard descriptor >= 0 else {
            throw HatchPetSkillInstallerError.unsafeBundledResource(relativePath)
        }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            Darwin.close(descriptor)
            throw HatchPetSkillInstallerError.unsafeBundledResource(relativePath)
        }

        let sourceHandle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? sourceHandle.close() }

        guard fileManager.createFile(
            atPath: destination.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw HatchPetSkillInstallerError.stagingFailed
        }

        do {
            let destinationHandle = try FileHandle(forWritingTo: destination)
            defer { try? destinationHandle.close() }

            while let data = try sourceHandle.read(upToCount: 64 * 1_024), !data.isEmpty {
                try destinationHandle.write(contentsOf: data)
            }
        } catch {
            throw HatchPetSkillInstallerError.stagingFailed
        }
    }

    private static func moveExclusively(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager
    ) throws {
        let result = sourceURL.path.withCString { sourcePath in
            destinationURL.path.withCString { destinationPath in
                renamex_np(sourcePath, destinationPath, UInt32(RENAME_EXCL))
            }
        }
        guard result == 0 else {
            if pathEntryExists(at: destinationURL, fileManager: fileManager) {
                throw HatchPetSkillInstallerError.destinationAlreadyExists
            }
            throw HatchPetSkillInstallerError.installationFailed
        }
    }

    private static func relativePath(of url: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard path.hasPrefix(prefix) else { return url.lastPathComponent }
        return String(path.dropFirst(prefix.count))
    }

    private static func fileType(
        at url: URL,
        fileManager: FileManager
    ) -> FileAttributeType? {
        guard url.isFileURL,
              let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return attributes[.type] as? FileAttributeType
    }

    private static func pathEntryExists(at url: URL, fileManager: FileManager) -> Bool {
        fileType(at: url, fileManager: fileManager) != nil
    }
}
