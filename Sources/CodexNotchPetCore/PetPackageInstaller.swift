import Darwin
import Foundation

public enum PetPackageInstallerError: Error, Equatable, Sendable {
    case invalidPetsRoot
    case unsafePackageDirectory
    case invalidPackageExtension
    case missingOrNonRegularManifest
    case manifestTooLarge(maximumByteCount: Int)
    case invalidManifest
    case invalidManifestContract(PetPackageValidationError)
    case invalidIdentifier
    case invalidDisplayName
    case unsafeSpritesheetPath
    case missingOrNonRegularSpritesheet
    case unsupportedSpritesheetFormat
    case spritesheetTooLarge(maximumByteCount: Int)
    case undecodableSpritesheet
    case invalidAtlasSize(width: Int, height: Int)
    case destinationAlreadyExists
    case stagingFailed
    case installationFailed
}

public enum PetPackageInstaller {
    public static let maximumManifestByteCount = 64 * 1_024
    public static let maximumIdentifierByteCount = 64
    public static let maximumDisplayNameByteCount = 128
    public static let maximumSpritesheetByteCount = 32 * 1_024 * 1_024

    public static func install(
        packageAt sourcePackageURL: URL,
        into petsRoot: URL,
        fileManager: FileManager = .default
    ) throws -> LoadedPetPackage {
        try preparePetsRoot(petsRoot, fileManager: fileManager)

        guard sourcePackageURL.pathExtension.lowercased() == "codexpet" else {
            throw PetPackageInstallerError.invalidPackageExtension
        }
        guard fileType(at: sourcePackageURL, fileManager: fileManager) == .typeDirectory else {
            throw PetPackageInstallerError.unsafePackageDirectory
        }

        let manifestURL = sourcePackageURL.appendingPathComponent("pet.json", isDirectory: false)
        guard fileType(at: manifestURL, fileManager: fileManager) == .typeRegular else {
            throw PetPackageInstallerError.missingOrNonRegularManifest
        }
        let manifestData = try readManifest(at: manifestURL)

        let manifest: PetPackageManifest
        do {
            manifest = try JSONDecoder().decode(PetPackageManifest.self, from: manifestData)
        } catch {
            throw PetPackageInstallerError.invalidManifest
        }

        do {
            try PetPackageValidator.validate(manifest)
        } catch let error as PetPackageValidationError {
            throw PetPackageInstallerError.invalidManifestContract(error)
        } catch {
            throw PetPackageInstallerError.invalidManifest
        }

        guard isSafeIdentifier(manifest.id) else {
            throw PetPackageInstallerError.invalidIdentifier
        }
        guard isSafeDisplayName(manifest.displayName) else {
            throw PetPackageInstallerError.invalidDisplayName
        }

        let destinationURL = petsRoot.appendingPathComponent(manifest.id, isDirectory: true)
        guard !pathEntryExists(at: destinationURL, fileManager: fileManager) else {
            throw PetPackageInstallerError.destinationAlreadyExists
        }

        let sourceSpritesheetURL = try spritesheetURL(
            for: manifest.spritesheetPath,
            in: sourcePackageURL,
            fileManager: fileManager
        )
        guard fileType(at: sourceSpritesheetURL, fileManager: fileManager) == .typeRegular else {
            throw PetPackageInstallerError.missingOrNonRegularSpritesheet
        }
        guard ["png", "webp"].contains(sourceSpritesheetURL.pathExtension.lowercased()) else {
            throw PetPackageInstallerError.unsupportedSpritesheetFormat
        }
        guard let sourceSpritesheet = openRegularFile(at: sourceSpritesheetURL) else {
            throw PetPackageInstallerError.missingOrNonRegularSpritesheet
        }
        defer { try? sourceSpritesheet.handle.close() }
        guard sourceSpritesheet.byteCount <= maximumSpritesheetByteCount else {
            throw PetPackageInstallerError.spritesheetTooLarge(
                maximumByteCount: maximumSpritesheetByteCount
            )
        }

        let stagingRoot = petsRoot.appendingPathComponent(
            ".codexpet-install-\(UUID().uuidString)",
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
            throw PetPackageInstallerError.stagingFailed
        }

        let stagedPackageURL = stagingRoot.appendingPathComponent(manifest.id, isDirectory: true)
        let stagedManifestURL = stagedPackageURL.appendingPathComponent(
            "pet.json",
            isDirectory: false
        )
        let stagedSpritesheetURL = stagedPackageURL.appendingPathComponent(
            manifest.spritesheetPath,
            isDirectory: false
        )

        do {
            try fileManager.createDirectory(
                at: stagedPackageURL,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.createDirectory(
                at: stagedSpritesheetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try write(manifestData, to: stagedManifestURL, fileManager: fileManager)
            try copyContents(
                from: sourceSpritesheet.handle,
                to: stagedSpritesheetURL,
                fileManager: fileManager
            )
        } catch let error as PetPackageInstallerError {
            throw error
        } catch {
            throw PetPackageInstallerError.stagingFailed
        }

        let stagedPackage: LoadedPetPackage
        do {
            stagedPackage = try PetLibrary.loadPackage(
                at: stagedPackageURL,
                within: stagingRoot,
                fileManager: fileManager
            )
        } catch let error as PetLibraryError {
            throw mapLibraryError(error)
        } catch {
            throw PetPackageInstallerError.installationFailed
        }

        try moveExclusively(from: stagedPackageURL, to: destinationURL, fileManager: fileManager)

        return LoadedPetPackage(
            manifest: stagedPackage.manifest,
            directoryURL: destinationURL.standardizedFileURL,
            spritesheetURL: destinationURL
                .appendingPathComponent(manifest.spritesheetPath, isDirectory: false)
                .standardizedFileURL
        )
    }

    private static func preparePetsRoot(_ petsRoot: URL, fileManager: FileManager) throws {
        guard petsRoot.isFileURL else {
            throw PetPackageInstallerError.invalidPetsRoot
        }

        if let type = fileType(at: petsRoot, fileManager: fileManager) {
            guard type == .typeDirectory else {
                throw PetPackageInstallerError.invalidPetsRoot
            }
            return
        }

        do {
            try fileManager.createDirectory(
                at: petsRoot,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw PetPackageInstallerError.invalidPetsRoot
        }

        guard fileType(at: petsRoot, fileManager: fileManager) == .typeDirectory else {
            throw PetPackageInstallerError.invalidPetsRoot
        }
    }

    private static func readManifest(at url: URL) throws -> Data {
        guard let manifestFile = openRegularFile(at: url) else {
            throw PetPackageInstallerError.missingOrNonRegularManifest
        }
        defer { try? manifestFile.handle.close() }
        guard manifestFile.byteCount <= maximumManifestByteCount else {
            throw PetPackageInstallerError.manifestTooLarge(
                maximumByteCount: maximumManifestByteCount
            )
        }

        var data = Data()
        do {
            while data.count <= maximumManifestByteCount {
                let readCount = min(8_192, maximumManifestByteCount + 1 - data.count)
                guard let chunk = try manifestFile.handle.read(upToCount: readCount),
                      !chunk.isEmpty else {
                    break
                }
                data.append(chunk)
            }
        } catch {
            throw PetPackageInstallerError.invalidManifest
        }

        guard data.count <= maximumManifestByteCount else {
            throw PetPackageInstallerError.manifestTooLarge(
                maximumByteCount: maximumManifestByteCount
            )
        }
        return data
    }

    private static func isSafeIdentifier(_ identifier: String) -> Bool {
        let bytes = Array(identifier.utf8)
        guard !bytes.isEmpty, bytes.count <= maximumIdentifierByteCount else { return false }

        return bytes.allSatisfy { byte in
            (0x61...0x7A).contains(byte)
                || (0x30...0x39).contains(byte)
                || byte == 0x2D
                || byte == 0x5F
        }
    }

    private static func isSafeDisplayName(_ displayName: String) -> Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && displayName.utf8.count <= maximumDisplayNameByteCount
    }

    private static func spritesheetURL(
        for relativePath: String,
        in packageURL: URL,
        fileManager: FileManager
    ) throws -> URL {
        var candidate = packageURL
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)

        for (index, component) in components.enumerated() {
            candidate.appendPathComponent(String(component), isDirectory: false)
            guard let type = fileType(at: candidate, fileManager: fileManager) else {
                if index < components.index(before: components.endIndex) {
                    throw PetPackageInstallerError.missingOrNonRegularSpritesheet
                }
                continue
            }
            guard type != .typeSymbolicLink else {
                throw PetPackageInstallerError.unsafeSpritesheetPath
            }
            if index < components.index(before: components.endIndex), type != .typeDirectory {
                throw PetPackageInstallerError.missingOrNonRegularSpritesheet
            }
        }

        let resolvedPackage = packageURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        let packagePrefix = resolvedPackage.path.hasSuffix("/")
            ? resolvedPackage.path
            : resolvedPackage.path + "/"
        guard resolvedCandidate.path.hasPrefix(packagePrefix) else {
            throw PetPackageInstallerError.unsafeSpritesheetPath
        }

        return candidate
    }

    private static func write(
        _ data: Data,
        to destinationURL: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.createFile(
            atPath: destinationURL.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw PetPackageInstallerError.stagingFailed
        }
    }

    private static func copyContents(
        from sourceHandle: FileHandle,
        to destinationURL: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.createFile(
            atPath: destinationURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw PetPackageInstallerError.stagingFailed
        }

        let destinationHandle = try FileHandle(forWritingTo: destinationURL)
        defer { try? destinationHandle.close() }

        var copiedByteCount = 0
        while let chunk = try sourceHandle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            copiedByteCount += chunk.count
            guard copiedByteCount <= maximumSpritesheetByteCount else {
                throw PetPackageInstallerError.spritesheetTooLarge(
                    maximumByteCount: maximumSpritesheetByteCount
                )
            }
            try destinationHandle.write(contentsOf: chunk)
        }
    }

    private struct OpenedRegularFile {
        let handle: FileHandle
        let byteCount: Int
    }

    private static func openRegularFile(at url: URL) -> OpenedRegularFile? {
        let descriptor = url.path.withCString { path in
            Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        }
        guard descriptor >= 0 else { return nil }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              metadata.st_size >= 0,
              metadata.st_size <= off_t(Int.max) else {
            Darwin.close(descriptor)
            return nil
        }

        return OpenedRegularFile(
            handle: FileHandle(fileDescriptor: descriptor, closeOnDealloc: true),
            byteCount: Int(metadata.st_size)
        )
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
                throw PetPackageInstallerError.destinationAlreadyExists
            }
            throw PetPackageInstallerError.installationFailed
        }
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

    private static func mapLibraryError(
        _ error: PetLibraryError
    ) -> PetPackageInstallerError {
        switch error {
        case .invalidManifest:
            return .invalidManifest
        case .invalidManifestContract(let validationError):
            return .invalidManifestContract(validationError)
        case .unsafeSpritesheetPath:
            return .unsafeSpritesheetPath
        case .missingOrNonRegularSpritesheet:
            return .missingOrNonRegularSpritesheet
        case .unsupportedSpritesheetFormat:
            return .unsupportedSpritesheetFormat
        case .undecodableSpritesheet:
            return .undecodableSpritesheet
        case .invalidAtlasSize(let width, let height):
            return .invalidAtlasSize(width: width, height: height)
        case .manifestIdentifierMismatch:
            return .invalidIdentifier
        case .invalidRoot,
             .unsafePackageDirectory,
             .missingOrNonRegularManifest:
            return .stagingFailed
        }
    }
}
