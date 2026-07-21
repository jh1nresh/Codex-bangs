import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import CodexNotchPetCore

final class PetLibraryTests: XCTestCase {
    func testDiscoversValidV2PackageAndSkipsInvalidContractsAndDimensions() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let valid = try makePackage(id: "valid", in: root)
        try writePNG(
            to: valid.appendingPathComponent("spritesheet.png"),
            width: PetV2Contract.atlasWidth,
            height: PetV2Contract.atlasHeight
        )

        let old = try makePackage(id: "old", version: 1, in: root)
        let traversal = try makePackage(
            id: "traversal",
            spritesheetPath: "../spritesheet.png",
            in: root
        )
        let wrongSize = try makePackage(id: "wrong-size", in: root)
        try writePNG(
            to: wrongSize.appendingPathComponent("spritesheet.png"),
            width: 32,
            height: 32
        )

        let packages = PetLibrary.discover(in: root)
        XCTAssertEqual(packages.map(\.id), ["valid"])
        XCTAssertEqual(packages[0].directoryURL, valid)
        XCTAssertEqual(
            packages[0].spritesheetURL,
            valid.appendingPathComponent("spritesheet.png")
        )

        XCTAssertThrowsError(try PetLibrary.loadPackage(at: old, within: root)) { error in
            XCTAssertEqual(
                error as? PetLibraryError,
                .invalidManifestContract(.unsupportedSpriteVersion(1))
            )
        }
        XCTAssertThrowsError(try PetLibrary.loadPackage(at: traversal, within: root)) { error in
            XCTAssertEqual(
                error as? PetLibraryError,
                .invalidManifestContract(.unsafeSpritesheetPath)
            )
        }
        XCTAssertThrowsError(try PetLibrary.loadPackage(at: wrongSize, within: root)) { error in
            XCTAssertEqual(
                error as? PetLibraryError,
                .invalidAtlasSize(width: 32, height: 32)
            )
        }
    }

    func testRejectsMissingCorruptAndSymlinkedSpritesheets() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let valid = try makePackage(id: "valid", in: root)
        let validAtlas = valid.appendingPathComponent("spritesheet.png")
        try writePNG(
            to: validAtlas,
            width: PetV2Contract.atlasWidth,
            height: PetV2Contract.atlasHeight
        )

        let missing = try makePackage(id: "missing", in: root)
        let corrupt = try makePackage(id: "corrupt", in: root)
        try Data("not an image".utf8).write(
            to: corrupt.appendingPathComponent("spritesheet.png")
        )
        let linked = try makePackage(id: "linked", in: root)
        try FileManager.default.createSymbolicLink(
            at: linked.appendingPathComponent("spritesheet.png"),
            withDestinationURL: validAtlas
        )

        XCTAssertThrowsError(try PetLibrary.loadPackage(at: missing, within: root)) { error in
            XCTAssertEqual(error as? PetLibraryError, .missingOrNonRegularSpritesheet)
        }
        XCTAssertThrowsError(try PetLibrary.loadPackage(at: corrupt, within: root)) { error in
            XCTAssertEqual(error as? PetLibraryError, .undecodableSpritesheet)
        }
        XCTAssertThrowsError(try PetLibrary.loadPackage(at: linked, within: root)) { error in
            XCTAssertEqual(error as? PetLibraryError, .unsafeSpritesheetPath)
        }
    }

    func testRejectsSymlinkedPackageDirectoryAndIdentifierMismatch() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let realPackage = try makePackage(id: "real", in: root)
        try writePNG(
            to: realPackage.appendingPathComponent("spritesheet.png"),
            width: PetV2Contract.atlasWidth,
            height: PetV2Contract.atlasHeight
        )
        let linkedPackage = root.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: linkedPackage,
            withDestinationURL: realPackage
        )

        let mismatch = try makePackage(id: "actual", manifestID: "different", in: root)

        XCTAssertThrowsError(try PetLibrary.loadPackage(at: linkedPackage, within: root)) { error in
            XCTAssertEqual(error as? PetLibraryError, .unsafePackageDirectory)
        }
        XCTAssertThrowsError(try PetLibrary.loadPackage(at: mismatch, within: root)) { error in
            XCTAssertEqual(error as? PetLibraryError, .manifestIdentifierMismatch)
        }
        XCTAssertEqual(PetLibrary.discover(in: root).map(\.id), ["real"])
    }

    func testRejectsManifestOverEncodedByteLimitDuringLoadAndDiscovery() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let package = try makePackage(id: "oversized-manifest", in: root)
        let manifestURL = package.appendingPathComponent("pet.json")
        var manifestData = try Data(contentsOf: manifestURL)
        manifestData.append(
            Data(
                repeating: 0x20,
                count: PetPackageInstaller.maximumManifestByteCount + 1 - manifestData.count
            )
        )
        try manifestData.write(to: manifestURL)
        try writePNG(
            to: package.appendingPathComponent("spritesheet.png"),
            width: PetV2Contract.atlasWidth,
            height: PetV2Contract.atlasHeight
        )

        XCTAssertThrowsError(try PetLibrary.loadPackage(at: package, within: root)) { error in
            XCTAssertEqual(error as? PetLibraryError, .invalidManifest)
        }
        XCTAssertTrue(PetLibrary.discover(in: root).isEmpty)
    }

    func testRejectsSpritesheetOverEncodedByteLimitDuringLoadAndDiscovery() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let package = try makePackage(id: "oversized-atlas", in: root)
        let spritesheetURL = package.appendingPathComponent("spritesheet.png")
        try writePNG(
            to: spritesheetURL,
            width: PetV2Contract.atlasWidth,
            height: PetV2Contract.atlasHeight
        )
        try resizeFile(
            at: spritesheetURL,
            to: PetPackageInstaller.maximumSpritesheetByteCount + 1
        )

        XCTAssertThrowsError(try PetLibrary.loadPackage(at: package, within: root)) { error in
            XCTAssertEqual(error as? PetLibraryError, .undecodableSpritesheet)
        }
        XCTAssertTrue(PetLibrary.discover(in: root).isEmpty)
    }

    func testRejectsHugeAdvertisedDimensionsBeforeImageDecode() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let package = try makePackage(id: "huge-atlas", in: root)
        let spritesheetURL = package.appendingPathComponent("spritesheet.png")
        try writeMonochromePNG(to: spritesheetURL, width: 8_192, height: 8_192)
        XCTAssertLessThan(
            try fileSize(at: spritesheetURL),
            PetPackageInstaller.maximumSpritesheetByteCount
        )

        XCTAssertThrowsError(try PetLibrary.loadPackage(at: package, within: root)) { error in
            XCTAssertEqual(
                error as? PetLibraryError,
                .invalidAtlasSize(width: 8_192, height: 8_192)
            )
        }
        XCTAssertTrue(PetLibrary.discover(in: root).isEmpty)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func makePackage(
        id: String,
        manifestID: String? = nil,
        version: Int = 2,
        spritesheetPath: String = "spritesheet.png",
        in root: URL
    ) throws -> URL {
        let directory = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "id": manifestID ?? id,
            "displayName": id,
            "description": "Synthetic test pet.",
            "spriteVersionNumber": version,
            "spritesheetPath": spritesheetPath
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: directory.appendingPathComponent("pet.json"))
        return directory
    }

    private func writePNG(to url: URL, width: Int, height: Int) throws {
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
            CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func writeMonochromePNG(to url: URL, width: Int, height: Int) throws {
        let bytesPerRow = (width + 7) / 8
        let pixels = Data(repeating: 0, count: bytesPerRow * height)
        let provider = try XCTUnwrap(CGDataProvider(data: pixels as CFData))
        let image = try XCTUnwrap(
            CGImage(
                width: width,
                height: height,
                bitsPerComponent: 1,
                bitsPerPixel: 1,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        )
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
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
}
