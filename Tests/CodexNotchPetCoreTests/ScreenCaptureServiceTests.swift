import Foundation
import XCTest
@testable import CodexNotchPetCore

final class ScreenCaptureServiceTests: XCTestCase {
    func testCaptureDimensionsCapLongestEdgeAndPreserveAspectRatio() {
        XCTAssertEqual(
            ScreenCaptureService.scaledDimensions(width: 1_920, height: 1_080).width,
            1_920
        )
        XCTAssertEqual(
            ScreenCaptureService.scaledDimensions(width: 1_920, height: 1_080).height,
            1_080
        )

        let scaled = ScreenCaptureService.scaledDimensions(width: 5_120, height: 2_880)
        XCTAssertEqual(scaled.width, 2_560)
        XCTAssertEqual(scaled.height, 1_440)
    }

    func testStoresPrivateCaptureAndRemovesOnlyItsUUIDDirectory() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let sibling = temporaryRoot.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sibling)
        let capture = try ScreenCaptureService(temporaryRoot: temporaryRoot)
            .storePNGData(Data("private pixels".utf8))

        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: capture.fileURL.deletingLastPathComponent().path
        )
        let fileAttributes = try FileManager.default.attributesOfItem(
            atPath: capture.fileURL.path
        )
        XCTAssertEqual(
            (directoryAttributes[.posixPermissions] as? NSNumber)?.intValue,
            0o700
        )
        XCTAssertEqual(
            (fileAttributes[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )

        capture.remove()

        XCTAssertFalse(FileManager.default.fileExists(atPath: capture.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path))
    }
}
