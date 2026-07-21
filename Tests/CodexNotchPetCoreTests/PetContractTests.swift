import XCTest
@testable import CodexNotchPetCore

final class PetContractTests: XCTestCase {
    func testV2AtlasGeometryAndRowsAreFrozen() {
        XCTAssertEqual(PetV2Contract.spriteVersionNumber, 2)
        XCTAssertEqual(PetV2Contract.columns, 8)
        XCTAssertEqual(PetV2Contract.rows, 11)
        XCTAssertEqual(PetV2Contract.cellWidth, 192)
        XCTAssertEqual(PetV2Contract.cellHeight, 208)
        XCTAssertEqual(PetV2Contract.atlasWidth, 1_536)
        XCTAssertEqual(PetV2Contract.atlasHeight, 2_288)
        XCTAssertEqual(
            PetV2Contract.animationRows.map(\.frameCount),
            [6, 8, 8, 4, 5, 8, 6, 6, 6, 8, 8]
        )
        XCTAssertEqual(
            PetV2Contract.animationRows[9].lookDegrees,
            [0, 22.5, 45, 67.5, 90, 112.5, 135, 157.5]
        )
        XCTAssertEqual(PetV2Contract.animationRows[10].lookDegrees.last, 337.5)
    }

    func testPackageValidatorFailsClosedForV1AndTraversal() {
        let valid = PetPackageManifest(
            id: "miaomiao",
            displayName: "苗苗",
            spriteVersionNumber: 2,
            spritesheetPath: "spritesheet.webp"
        )
        XCTAssertNoThrow(try PetPackageValidator.validate(valid))

        let versionOne = PetPackageManifest(
            id: "old",
            displayName: "Old",
            spriteVersionNumber: 1,
            spritesheetPath: "spritesheet.webp"
        )
        XCTAssertThrowsError(try PetPackageValidator.validate(versionOne)) { error in
            XCTAssertEqual(error as? PetPackageValidationError, .unsupportedSpriteVersion(1))
        }

        let traversal = PetPackageManifest(
            id: "unsafe",
            displayName: "Unsafe",
            spriteVersionNumber: 2,
            spritesheetPath: "../spritesheet.webp"
        )
        XCTAssertThrowsError(try PetPackageValidator.validate(traversal))
    }

    func testMonitorStateMappingUsesExistingPetRows() {
        XCTAssertEqual(PetStateMapper.animation(for: .working), .running)
        XCTAssertEqual(PetStateMapper.animation(for: .approval), .review)
        XCTAssertEqual(PetStateMapper.animation(for: .waiting), .waiting)
        XCTAssertEqual(PetStateMapper.animation(for: .offline), .failed)
        XCTAssertEqual(PetStateMapper.animation(for: .unavailable), .idle)
    }
}
