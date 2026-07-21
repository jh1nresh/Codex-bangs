import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import CodexNotchPetCore

final class PetPackageInstallerTests: XCTestCase {
    func testInstallsValidPackageUnderManifestIdentifierAndCopiesOnlyRequiredFiles() throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }

        let source = try makePackage(
            named: "download-428.codexpet",
            id: "miaomiao",
            spritesheetPath: "art/spritesheet.png",
            in: base
        )
        try writeImage(
            to: source.appendingPathComponent("art/spritesheet.png"),
            width: PetV2Contract.atlasWidth,
            height: PetV2Contract.atlasHeight,
            type: .png
        )
        try Data("ignore me".utf8).write(to: source.appendingPathComponent("notes.txt"))
        let external = base.appendingPathComponent("external.txt")
        try Data("also ignore me".utf8).write(to: external)
        try FileManager.default.createSymbolicLink(
            at: source.appendingPathComponent("unreferenced-link"),
            withDestinationURL: external
        )

        let petsRoot = base.appendingPathComponent("new-pets", isDirectory: true)
        let installed = try PetPackageInstaller.install(packageAt: source, into: petsRoot)
        let destination = petsRoot.appendingPathComponent("miaomiao", isDirectory: true)

        XCTAssertEqual(installed.id, "miaomiao")
        XCTAssertEqual(installed.directoryURL, destination)
        XCTAssertEqual(
            installed.spritesheetURL,
            destination.appendingPathComponent("art/spritesheet.png")
        )
        XCTAssertEqual(try childNames(of: petsRoot), ["miaomiao"])
        XCTAssertEqual(try childNames(of: destination), ["art", "pet.json"])
        XCTAssertEqual(try childNames(of: destination.appendingPathComponent("art")), [
            "spritesheet.png"
        ])
        XCTAssertEqual(
            try PetLibrary.loadPackage(at: destination, within: petsRoot),
            installed
        )
    }

    func testInstallsValidWebPSpritesheet() throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }

        let source = try makePackage(
            named: "character.codexpet",
            id: "webp-pet",
            spritesheetPath: "spritesheet.webp",
            in: base
        )
        let webPData = try XCTUnwrap(
            Data(
                base64Encoded: "UklGRrQAAABXRUJQVlA4TKgAAAAv/8U7AgcQEf0PCEiS/u8PjOh/xn/+85///Oc///nPf/7zn//85z//+c9//vOf//znP//5z3/+85///Oc///nPf/7zn//85z//+c9//vOf//znP//5z3/+85///Oc///nPf/7zn//85z//+c9//vOf//znP//5z3/+85///Oc///nPf/7zn//85z//+c9//vOf//znP//5z3/+85///Oc///nPf/7z/zQ="
            )
        )
        try webPData.write(to: source.appendingPathComponent("spritesheet.webp"))

        let installed = try PetPackageInstaller.install(
            packageAt: source,
            into: base.appendingPathComponent("pets")
        )

        XCTAssertEqual(installed.spritesheetURL.pathExtension, "webp")
    }

    func testAllowsSpritesheetAtEncodedByteLimit() throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = try makePackage(named: "boundary.codexpet", id: "boundary", in: base)
        let spritesheet = source.appendingPathComponent("spritesheet.png")
        try writeImage(
            to: spritesheet,
            width: PetV2Contract.atlasWidth,
            height: PetV2Contract.atlasHeight,
            type: .png
        )
        try resizeFile(
            at: spritesheet,
            to: PetPackageInstaller.maximumSpritesheetByteCount
        )

        let installed = try PetPackageInstaller.install(
            packageAt: source,
            into: base.appendingPathComponent("pets")
        )

        XCTAssertEqual(
            try fileSize(at: installed.spritesheetURL),
            PetPackageInstaller.maximumSpritesheetByteCount
        )
    }

    func testRejectsSpritesheetOverEncodedByteLimitBeforeStaging() throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = try makePackage(named: "oversized.codexpet", id: "oversized", in: base)
        let spritesheet = source.appendingPathComponent("spritesheet.png")
        XCTAssertTrue(FileManager.default.createFile(atPath: spritesheet.path, contents: nil))
        try resizeFile(
            at: spritesheet,
            to: PetPackageInstaller.maximumSpritesheetByteCount + 1
        )
        let petsRoot = base.appendingPathComponent("pets", isDirectory: true)

        assertInstallThrows(
            .spritesheetTooLarge(
                maximumByteCount: PetPackageInstaller.maximumSpritesheetByteCount
            ),
            packageAt: source,
            into: petsRoot
        )

        XCTAssertEqual(try childNames(of: petsRoot), [])
    }

    func testRejectsWrongExtensionAndNonDirectoryOrSymlinkedSources() throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let petsRoot = base.appendingPathComponent("pets", isDirectory: true)

        let wrongExtension = base.appendingPathComponent("pet.zip", isDirectory: true)
        try FileManager.default.createDirectory(at: wrongExtension, withIntermediateDirectories: false)
        assertInstallThrows(.invalidPackageExtension, packageAt: wrongExtension, into: petsRoot)

        let regularFile = base.appendingPathComponent("regular.codexpet")
        try Data().write(to: regularFile)
        assertInstallThrows(.unsafePackageDirectory, packageAt: regularFile, into: petsRoot)

        let realDirectory = base.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: false)
        let symlink = base.appendingPathComponent("linked.codexpet", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: realDirectory)
        assertInstallThrows(.unsafePackageDirectory, packageAt: symlink, into: petsRoot)
    }

    func testCreatesAbsentPetsRootAndRejectsExistingFileOrSymlinkRoots() throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("source.codexpet", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)

        let fileRoot = base.appendingPathComponent("file-root")
        try Data().write(to: fileRoot)
        assertInstallThrows(.invalidPetsRoot, packageAt: source, into: fileRoot)

        let realRoot = base.appendingPathComponent("real-root", isDirectory: true)
        try FileManager.default.createDirectory(at: realRoot, withIntermediateDirectories: false)
        let linkedRoot = base.appendingPathComponent("linked-root", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: realRoot)
        assertInstallThrows(.invalidPetsRoot, packageAt: source, into: linkedRoot)

        let absentRoot = base.appendingPathComponent("created-root", isDirectory: true)
        assertInstallThrows(
            .missingOrNonRegularManifest,
            packageAt: source,
            into: absentRoot
        )
        XCTAssertEqual(try fileType(at: absentRoot), .typeDirectory)
    }

    func testRejectsMalformedSymlinkedAndOversizedManifests() throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let petsRoot = base.appendingPathComponent("pets", isDirectory: true)

        let malformed = try makeEmptyPackage(named: "malformed.codexpet", in: base)
        try Data("{not-json".utf8).write(to: malformed.appendingPathComponent("pet.json"))
        assertInstallThrows(.invalidManifest, packageAt: malformed, into: petsRoot)

        let externalManifest = base.appendingPathComponent("external.json")
        try manifestData(id: "linked").write(to: externalManifest)
        let linked = try makeEmptyPackage(named: "linked.codexpet", in: base)
        try FileManager.default.createSymbolicLink(
            at: linked.appendingPathComponent("pet.json"),
            withDestinationURL: externalManifest
        )
        assertInstallThrows(
            .missingOrNonRegularManifest,
            packageAt: linked,
            into: petsRoot
        )

        let oversized = try makeEmptyPackage(named: "oversized.codexpet", in: base)
        try Data(repeating: 0x20, count: PetPackageInstaller.maximumManifestByteCount + 1)
            .write(to: oversized.appendingPathComponent("pet.json"))
        assertInstallThrows(
            .manifestTooLarge(
                maximumByteCount: PetPackageInstaller.maximumManifestByteCount
            ),
            packageAt: oversized,
            into: petsRoot
        )
    }

    func testRejectsTraversalWrongVersionUnsupportedFormatAndCorruptImage() throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let petsRoot = base.appendingPathComponent("pets", isDirectory: true)

        let traversal = try makePackage(
            named: "traversal.codexpet",
            id: "traversal",
            spritesheetPath: "../outside.png",
            in: base
        )
        assertInstallThrows(
            .invalidManifestContract(.unsafeSpritesheetPath),
            packageAt: traversal,
            into: petsRoot
        )

        let old = try makePackage(
            named: "old.codexpet",
            id: "old",
            version: 1,
            in: base
        )
        assertInstallThrows(
            .invalidManifestContract(.unsupportedSpriteVersion(1)),
            packageAt: old,
            into: petsRoot
        )

        let unsupported = try makePackage(
            named: "unsupported.codexpet",
            id: "unsupported",
            spritesheetPath: "spritesheet.gif",
            in: base
        )
        try Data("not relevant".utf8).write(
            to: unsupported.appendingPathComponent("spritesheet.gif")
        )
        assertInstallThrows(
            .unsupportedSpritesheetFormat,
            packageAt: unsupported,
            into: petsRoot
        )

        let corrupt = try makePackage(
            named: "corrupt.codexpet",
            id: "corrupt",
            in: base
        )
        try Data("not an image".utf8).write(
            to: corrupt.appendingPathComponent("spritesheet.png")
        )
        assertInstallThrows(.undecodableSpritesheet, packageAt: corrupt, into: petsRoot)
    }

    func testRejectsSymlinkedSpritesheetAndSymlinkedPathComponent() throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let petsRoot = base.appendingPathComponent("pets", isDirectory: true)
        let externalDirectory = base.appendingPathComponent("external", isDirectory: true)
        try FileManager.default.createDirectory(
            at: externalDirectory,
            withIntermediateDirectories: false
        )
        let externalSpritesheet = externalDirectory.appendingPathComponent("spritesheet.png")
        try writeImage(
            to: externalSpritesheet,
            width: PetV2Contract.atlasWidth,
            height: PetV2Contract.atlasHeight,
            type: .png
        )

        let linkedFile = try makePackage(
            named: "linked-file.codexpet",
            id: "linked-file",
            in: base
        )
        try FileManager.default.createSymbolicLink(
            at: linkedFile.appendingPathComponent("spritesheet.png"),
            withDestinationURL: externalSpritesheet
        )
        assertInstallThrows(.unsafeSpritesheetPath, packageAt: linkedFile, into: petsRoot)

        let linkedDirectory = try makePackage(
            named: "linked-directory.codexpet",
            id: "linked-directory",
            spritesheetPath: "art/spritesheet.png",
            in: base
        )
        try FileManager.default.createSymbolicLink(
            at: linkedDirectory.appendingPathComponent("art"),
            withDestinationURL: externalDirectory
        )
        assertInstallThrows(
            .unsafeSpritesheetPath,
            packageAt: linkedDirectory,
            into: petsRoot
        )
    }

    func testRejectsWrongDimensionsAndCleansItsStagingDirectory() throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = try makePackage(named: "tiny.codexpet", id: "tiny", in: base)
        try writeImage(
            to: source.appendingPathComponent("spritesheet.png"),
            width: 32,
            height: 24,
            type: .png
        )
        let petsRoot = base.appendingPathComponent("pets", isDirectory: true)
        try FileManager.default.createDirectory(at: petsRoot, withIntermediateDirectories: false)
        let unrelatedStagingDirectory = petsRoot.appendingPathComponent(
            ".codexpet-install-preserve",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: unrelatedStagingDirectory,
            withIntermediateDirectories: false
        )
        try Data("preserve".utf8).write(
            to: unrelatedStagingDirectory.appendingPathComponent("marker")
        )

        assertInstallThrows(
            .invalidAtlasSize(width: 32, height: 24),
            packageAt: source,
            into: petsRoot
        )

        XCTAssertEqual(try childNames(of: petsRoot), [".codexpet-install-preserve"])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: unrelatedStagingDirectory.appendingPathComponent("marker").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: petsRoot.appendingPathComponent("tiny").path
            )
        )
    }

    func testRejectsUnsafeAndOverlongIdentifiers() throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let petsRoot = base.appendingPathComponent("pets", isDirectory: true)
        let identifiers = [
            "../x",
            "/x",
            ".hidden",
            "with/slash",
            "with\\separator",
            "Uppercase",
            String(repeating: "a", count: PetPackageInstaller.maximumIdentifierByteCount + 1)
        ]

        for (index, identifier) in identifiers.enumerated() {
            let package = try makePackage(
                named: "unsafe-\(index).codexpet",
                id: identifier,
                in: base
            )
            assertInstallThrows(.invalidIdentifier, packageAt: package, into: petsRoot)
        }

        XCTAssertEqual(try childNames(of: petsRoot), [])
    }

    func testRejectsBuiltInPetIdentifier() throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let petsRoot = base.appendingPathComponent("pets", isDirectory: true)
        let package = try makePackage(
            named: "reserved.codexpet",
            id: PetV2Contract.builtInPetIdentifier,
            in: base
        )

        assertInstallThrows(
            .invalidManifestContract(.reservedIdentifier),
            packageAt: package,
            into: petsRoot
        )
        XCTAssertEqual(try childNames(of: petsRoot), [])
    }

    func testRejectsBlankAndOverlongDisplayNames() throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let petsRoot = base.appendingPathComponent("pets", isDirectory: true)
        let displayNames = [
            "",
            " \n\t ",
            String(repeating: "x", count: PetPackageInstaller.maximumDisplayNameByteCount + 1)
        ]

        for (index, displayName) in displayNames.enumerated() {
            let package = try makePackage(
                named: "display-name-\(index).codexpet",
                id: "display-name-\(index)",
                displayName: displayName,
                in: base
            )
            assertInstallThrows(.invalidDisplayName, packageAt: package, into: petsRoot)
        }
    }

    func testExistingDestinationOfAnyFileTypeFailsWithoutOverwrite() throws {
        enum ExistingKind: CaseIterable {
            case directory
            case file
            case brokenSymlink
        }

        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }

        for (index, kind) in ExistingKind.allCases.enumerated() {
            let caseRoot = base.appendingPathComponent("case-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: caseRoot, withIntermediateDirectories: false)
            let id = "taken-\(index)"
            let source = try makePackage(
                named: "source.codexpet",
                id: id,
                in: caseRoot
            )
            let petsRoot = caseRoot.appendingPathComponent("pets", isDirectory: true)
            try FileManager.default.createDirectory(at: petsRoot, withIntermediateDirectories: false)
            let destination = petsRoot.appendingPathComponent(id)
            let expectedType: FileAttributeType

            switch kind {
            case .directory:
                expectedType = .typeDirectory
                try FileManager.default.createDirectory(
                    at: destination,
                    withIntermediateDirectories: false
                )
                try Data("preserve".utf8).write(
                    to: destination.appendingPathComponent("marker")
                )
            case .file:
                expectedType = .typeRegular
                try Data("preserve".utf8).write(to: destination)
            case .brokenSymlink:
                expectedType = .typeSymbolicLink
                try FileManager.default.createSymbolicLink(
                    at: destination,
                    withDestinationURL: caseRoot.appendingPathComponent("missing")
                )
            }

            assertInstallThrows(.destinationAlreadyExists, packageAt: source, into: petsRoot)
            XCTAssertEqual(try fileType(at: destination), expectedType)
            XCTAssertFalse(try childNames(of: petsRoot).contains { name in
                name.hasPrefix(".codexpet-install-")
            })
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeEmptyPackage(named name: String, in root: URL) throws -> URL {
        let package = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
        return package
    }

    private func makePackage(
        named name: String,
        id: String,
        displayName: String? = nil,
        version: Int = PetV2Contract.spriteVersionNumber,
        spritesheetPath: String = "spritesheet.png",
        in root: URL
    ) throws -> URL {
        let package = try makeEmptyPackage(named: name, in: root)
        try manifestData(
            id: id,
            displayName: displayName ?? id,
            version: version,
            spritesheetPath: spritesheetPath
        ).write(to: package.appendingPathComponent("pet.json"))
        return package
    }

    private func manifestData(
        id: String,
        displayName: String? = nil,
        version: Int = PetV2Contract.spriteVersionNumber,
        spritesheetPath: String = "spritesheet.png"
    ) throws -> Data {
        let manifest: [String: Any] = [
            "id": id,
            "displayName": displayName ?? id,
            "description": "Synthetic installer fixture.",
            "spriteVersionNumber": version,
            "spritesheetPath": spritesheetPath
        ]
        return try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
    }

    private func writeImage(
        to url: URL,
        width: Int,
        height: Int,
        type: UTType
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            )
        )
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func childNames(of directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .map(\.lastPathComponent)
        .sorted()
    }

    private func fileType(at url: URL) throws -> FileAttributeType {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.type] as? FileAttributeType)
    }

    private func fileSize(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.size] as? NSNumber).intValue
    }

    private func resizeFile(at url: URL, to byteCount: Int) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(byteCount))
    }

    private func assertInstallThrows(
        _ expected: PetPackageInstallerError,
        packageAt packageURL: URL,
        into petsRoot: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try PetPackageInstaller.install(packageAt: packageURL, into: petsRoot),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? PetPackageInstallerError,
                expected,
                file: file,
                line: line
            )
        }
    }
}
