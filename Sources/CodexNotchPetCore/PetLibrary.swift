import Darwin
import Foundation
import ImageIO

public struct LoadedPetPackage: Identifiable, Equatable, Sendable {
    public var id: String {
        manifest.id
    }

    public let manifest: PetPackageManifest
    public let directoryURL: URL
    public let spritesheetURL: URL

    public init(
        manifest: PetPackageManifest,
        directoryURL: URL,
        spritesheetURL: URL
    ) {
        self.manifest = manifest
        self.directoryURL = directoryURL
        self.spritesheetURL = spritesheetURL
    }
}

public enum PetLibraryError: Error, Equatable, Sendable {
    case invalidRoot
    case unsafePackageDirectory
    case missingOrNonRegularManifest
    case invalidManifest
    case manifestIdentifierMismatch
    case invalidManifestContract(PetPackageValidationError)
    case unsafeSpritesheetPath
    case missingOrNonRegularSpritesheet
    case unsupportedSpritesheetFormat
    case undecodableSpritesheet
    case invalidAtlasSize(width: Int, height: Int)
}

public enum PetLibrary {
    public static func discover(
        in petsRoot: URL,
        fileManager: FileManager = .default
    ) -> [LoadedPetPackage] {
        guard isDirectory(petsRoot, fileManager: fileManager) else { return [] }

        let candidates: [URL]
        do {
            candidates = try fileManager.contentsOfDirectory(
                at: petsRoot,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        return candidates.compactMap { candidate in
            try? loadPackage(at: candidate, within: petsRoot, fileManager: fileManager)
        }
        .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    public static func loadPackage(
        at directoryURL: URL,
        within petsRoot: URL,
        fileManager: FileManager = .default
    ) throws -> LoadedPetPackage {
        guard isDirectory(petsRoot, fileManager: fileManager) else {
            throw PetLibraryError.invalidRoot
        }
        guard isDirectory(directoryURL, fileManager: fileManager),
              isDirectChild(directoryURL, of: petsRoot) else {
            throw PetLibraryError.unsafePackageDirectory
        }

        let manifestURL = directoryURL.appendingPathComponent("pet.json", isDirectory: false)
        guard let manifestFile = openRegularFile(at: manifestURL) else {
            throw PetLibraryError.missingOrNonRegularManifest
        }
        defer { try? manifestFile.handle.close() }
        guard manifestFile.byteCount <= PetPackageInstaller.maximumManifestByteCount else {
            throw PetLibraryError.invalidManifest
        }

        let manifest: PetPackageManifest
        do {
            let data = try readContents(
                from: manifestFile.handle,
                maximumByteCount: PetPackageInstaller.maximumManifestByteCount
            )
            guard data.count <= PetPackageInstaller.maximumManifestByteCount else {
                throw PetLibraryError.invalidManifest
            }
            manifest = try JSONDecoder().decode(PetPackageManifest.self, from: data)
        } catch let error as PetLibraryError {
            throw error
        } catch {
            throw PetLibraryError.invalidManifest
        }

        do {
            try PetPackageValidator.validate(manifest)
        } catch let error as PetPackageValidationError {
            throw PetLibraryError.invalidManifestContract(error)
        } catch {
            throw PetLibraryError.invalidManifest
        }

        guard manifest.id == directoryURL.lastPathComponent else {
            throw PetLibraryError.manifestIdentifierMismatch
        }

        let spritesheetURL = try assetURL(
            for: manifest.spritesheetPath,
            in: directoryURL
        )
        guard let spritesheetFile = openRegularFile(at: spritesheetURL) else {
            throw PetLibraryError.missingOrNonRegularSpritesheet
        }
        defer { try? spritesheetFile.handle.close() }

        let supportedExtensions = ["png", "webp"]
        guard supportedExtensions.contains(spritesheetURL.pathExtension.lowercased()) else {
            throw PetLibraryError.unsupportedSpritesheetFormat
        }

        guard spritesheetFile.byteCount <= PetPackageInstaller.maximumSpritesheetByteCount else {
            throw PetLibraryError.undecodableSpritesheet
        }

        let spritesheetData: Data
        do {
            spritesheetData = try readContents(
                from: spritesheetFile.handle,
                maximumByteCount: PetPackageInstaller.maximumSpritesheetByteCount
            )
        } catch {
            throw PetLibraryError.undecodableSpritesheet
        }
        guard spritesheetData.count <= PetPackageInstaller.maximumSpritesheetByteCount,
              let source = CGImageSourceCreateWithData(spritesheetData as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  source,
                  0,
                  [kCGImageSourceShouldCache: false] as CFDictionary
              ) as? [CFString: Any],
              let advertisedWidth = pixelDimension(
                  kCGImagePropertyPixelWidth,
                  in: properties
              ),
              let advertisedHeight = pixelDimension(
                  kCGImagePropertyPixelHeight,
                  in: properties
              ) else {
            throw PetLibraryError.undecodableSpritesheet
        }
        guard advertisedWidth == PetV2Contract.atlasWidth,
              advertisedHeight == PetV2Contract.atlasHeight else {
            throw PetLibraryError.invalidAtlasSize(
                width: advertisedWidth,
                height: advertisedHeight
            )
        }

        guard let image = CGImageSourceCreateImageAtIndex(
            source,
            0,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            throw PetLibraryError.undecodableSpritesheet
        }
        guard image.width == PetV2Contract.atlasWidth,
              image.height == PetV2Contract.atlasHeight else {
            throw PetLibraryError.invalidAtlasSize(width: image.width, height: image.height)
        }

        return LoadedPetPackage(
            manifest: manifest,
            directoryURL: directoryURL.standardizedFileURL,
            spritesheetURL: spritesheetURL.standardizedFileURL
        )
    }

    private static func assetURL(
        for relativePath: String,
        in directoryURL: URL
    ) throws -> URL {
        var candidate = directoryURL
        for component in relativePath.split(separator: "/", omittingEmptySubsequences: false) {
            candidate.appendPathComponent(String(component), isDirectory: false)
            if isSymbolicLink(candidate) {
                throw PetLibraryError.unsafeSpritesheetPath
            }
        }

        let resolvedDirectory = directoryURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        let directoryPrefix = resolvedDirectory.path.hasSuffix("/")
            ? resolvedDirectory.path
            : resolvedDirectory.path + "/"
        guard resolvedCandidate.path.hasPrefix(directoryPrefix) else {
            throw PetLibraryError.unsafeSpritesheetPath
        }

        return candidate
    }

    private static func isDirectChild(_ child: URL, of parent: URL) -> Bool {
        let resolvedParent = parent.resolvingSymlinksInPath().standardizedFileURL
        let resolvedChildParent = child.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL
        return resolvedChildParent.path == resolvedParent.path
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        guard url.isFileURL, !isSymbolicLink(url) else { return false }
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func openRegularFile(at url: URL) -> OpenedRegularFile? {
        guard url.isFileURL else { return nil }

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

    private static func readContents(
        from handle: FileHandle,
        maximumByteCount: Int
    ) throws -> Data {
        var data = Data()
        while data.count <= maximumByteCount {
            let readCount = min(64 * 1_024, maximumByteCount + 1 - data.count)
            guard let chunk = try handle.read(upToCount: readCount),
                  !chunk.isEmpty else {
                break
            }
            data.append(chunk)
        }
        return data
    }

    private static func pixelDimension(
        _ key: CFString,
        in properties: [CFString: Any]
    ) -> Int? {
        guard let number = properties[key] as? NSNumber else { return nil }
        let value = number.intValue
        return value >= 0 ? value : nil
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private struct OpenedRegularFile {
        let handle: FileHandle
        let byteCount: Int
    }
}
