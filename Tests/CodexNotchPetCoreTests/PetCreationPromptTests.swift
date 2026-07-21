import XCTest
@testable import CodexNotchPetCore

final class PetCreationPromptTests: XCTestCase {
    func testBuildsTrimmedReviewableHatchPetRequest() throws {
        let request = try PetCreationPrompt(
            name: "  Bloop \n",
            appearance: "  A friendly cyan and indigo blob with soft bangs.  "
        )

        XCTAssertEqual(request.name, "Bloop")
        XCTAssertEqual(
            request.appearance,
            "A friendly cyan and indigo blob with soft bangs."
        )
        XCTAssertFalse(request.wasAppearanceTruncated)
        XCTAssertTrue(request.text.contains("Use $hatch-pet"))
        XCTAssertTrue(request.text.contains("full Codex v2 8x11 workflow"))
        XCTAssertTrue(request.text.contains("all nine standard animation rows"))
        XCTAssertTrue(request.text.contains("all 16 clockwise look directions"))
        XCTAssertTrue(request.text.contains("spriteVersionNumber: 2"))
        XCTAssertTrue(request.text.contains("pass every full v2 QA gate"))
        XCTAssertTrue(request.text.contains("~/.codex/pets/<pet-id>"))
        XCTAssertTrue(request.text.contains("reopen or reload"))
        XCTAssertTrue(request.text.contains("Codex-bangs"))
        XCTAssertNotNil(CodexDesktopHandoff.url(for: request.text))
    }

    func testRejectsBlankInputs() {
        XCTAssertThrowsError(
            try PetCreationPrompt(name: " \n", appearance: "cyan")
        ) { error in
            XCTAssertEqual(
                error as? PetCreationPromptValidationError,
                .missingName
            )
        }

        XCTAssertThrowsError(
            try PetCreationPrompt(name: "Bloop", appearance: " \t")
        ) { error in
            XCTAssertEqual(
                error as? PetCreationPromptValidationError,
                .missingAppearance
            )
        }
    }

    func testBoundsAppearanceAtGraphemeBoundaryWithoutDroppingRequirements() throws {
        let grapheme = "e\u{301}"
        let originalAppearance = String(repeating: grapheme, count: 3_000)
        let request = try PetCreationPrompt(
            name: "Bloop",
            appearance: originalAppearance
        )

        XCTAssertTrue(request.wasAppearanceTruncated)
        XCTAssertTrue(originalAppearance.hasPrefix(request.appearance))
        XCTAssertTrue(request.appearance.allSatisfy { String($0) == grapheme })
        XCTAssertLessThanOrEqual(
            request.text.utf8.count,
            CodexDesktopHandoff.maximumPromptUTF8Bytes
        )
        XCTAssertTrue(request.text.hasSuffix(
            "When installation and QA are complete, tell me to return to Codex-bangs and reopen or reload it so I can select the new pet."
        ))
        XCTAssertNotNil(CodexDesktopHandoff.url(for: request.text))
    }

    func testRejectsNameThatLeavesNoRoomForAppearance() {
        let oversizedName = String(
            repeating: "n",
            count: CodexDesktopHandoff.maximumPromptUTF8Bytes
        )

        XCTAssertThrowsError(
            try PetCreationPrompt(name: oversizedName, appearance: "cyan")
        ) { error in
            XCTAssertEqual(
                error as? PetCreationPromptValidationError,
                .nameTooLong
            )
        }
    }
}
