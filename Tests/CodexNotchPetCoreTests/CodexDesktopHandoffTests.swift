import XCTest
@testable import CodexNotchPetCore

final class CodexDesktopHandoffTests: XCTestCase {
    func testBuildsPercentEncodedNewThreadReviewHandoff() throws {
        let url = try XCTUnwrap(
            CodexDesktopHandoff.url(for: "  Fix this & add tests\n")
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "codex")
        XCTAssertEqual(components.host, "new")
        XCTAssertEqual(components.queryItems, [
            URLQueryItem(name: "prompt", value: "Fix this & add tests")
        ])
    }

    func testRejectsBlankAndOversizedPayloads() throws {
        XCTAssertNil(CodexDesktopHandoff.url(for: " \n\t "))

        let oversized = String(repeating: "🐾", count: 1_001)
        XCTAssertNil(CodexDesktopHandoff.url(for: oversized))

        let oversizedSingleGrapheme = "a" + String(repeating: "\u{0301}", count: 2_100)
        XCTAssertEqual(oversizedSingleGrapheme.count, 1)
        XCTAssertNil(CodexDesktopHandoff.url(for: oversizedSingleGrapheme))
    }

    func testDraftTruncationPreservesUnicodeBoundariesAndBoundsBytes() {
        let oversized = String(repeating: "🐾", count: 1_100)
        let truncated = CodexDesktopHandoff.truncatingToMaximumUTF8Bytes(oversized)

        XCTAssertLessThanOrEqual(
            truncated.utf8.count,
            CodexDesktopHandoff.maximumPromptUTF8Bytes
        )
        XCTAssertTrue(oversized.hasPrefix(truncated))
        XCTAssertEqual(truncated.count, 1_000)
    }
}
