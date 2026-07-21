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
        guard isRegularFile(manifestURL, fileManager: fileManager) else {
            throw PetLibraryError.missingOrNonRegularManifest
        }

        let manifest: PetPackageManifest
        do {
            let data = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
            manifest = try JSONDecoder().decode(PetPackageManifest.self, from: data)
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
        guard isRegularFile(spritesheetURL, fileManager: fileManager) else {
            throw PetLibraryError.missingOrNonRegularSpritesheet
        }

        let supportedExtensions = ["png", "webp"]
        guard supportedExtensions.contains(spritesheetURL.pathExtension.lowercased()) else {
            throw PetLibraryError.unsupportedSpritesheetFormat
        }

        guard let source = CGImageSourceCreateWithURL(spritesheetURL as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
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

    private static func isRegularFile(_ url: URL, fileManager: FileManager) -> Bool {
        guard url.isFileURL,
              !isSymbolicLink(url),
              fileManager.fileExists(atPath: url.path) else {
            return false
        }
        return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}
