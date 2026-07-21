import XCTest
@testable import CodexNotchPetCore

final class RateLimitMappingTests: XCTestCase {
    func testMultiBucketMappingPrefersCodexLongWindowAndClampsPercentages() throws {
        let response = try JSONDecoder().decode(
            RateLimitReadResponse.self,
            from: FixtureLoader.data(named: "rate-limits-multi")
        )

        let buckets = RateLimitMapper.buckets(from: response)
        XCTAssertEqual(buckets.map(\.id), ["codex", "other"])
        XCTAssertEqual(buckets[0].windows[0].usedPercent, 0)
        XCTAssertEqual(buckets[0].windows[0].remainingPercent, 100)
        XCTAssertEqual(buckets[1].windows[0].usedPercent, 100)
        XCTAssertEqual(buckets[1].windows[0].remainingPercent, 0)

        let collapsed = try XCTUnwrap(RateLimitMapper.collapsedWindow(from: buckets))
        XCTAssertEqual(collapsed.role, .secondary)
        XCTAssertEqual(collapsed.remainingPercent, 82)
        XCTAssertTrue(collapsed.isWeekly)
        XCTAssertEqual(
            RateLimitMapper.label(for: collapsed, in: buckets[0]),
            "Codex · Weekly"
        )
        XCTAssertEqual(
            RateLimitMapper.label(for: buckets[1].windows[0], in: buckets[1]),
            "Other metered use"
        )
    }

    func testAbsentWindowDoesNotBecomeOneHundredPercent() throws {
        let response = try JSONDecoder().decode(
            RateLimitReadResponse.self,
            from: FixtureLoader.data(named: "rate-limits-absent")
        )

        let buckets = RateLimitMapper.buckets(from: response)
        XCTAssertEqual(buckets.count, 1)
        XCTAssertTrue(buckets[0].windows.isEmpty)
        XCTAssertNil(RateLimitMapper.collapsedWindow(from: buckets))
        XCTAssertThrowsError(
            try JSONDecoder().decode(RateLimitReadResponse.self, from: Data("{}".utf8))
        )
    }

    func testSingleLegacyBucketRemainsSupported() {
        let response = RateLimitReadResponse(
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                primary: RateLimitWindow(
                    usedPercent: 34,
                    windowDurationMins: nil,
                    resetsAt: nil
                )
            ),
            rateLimitsByLimitId: nil
        )

        let buckets = RateLimitMapper.buckets(from: response)
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets[0].windows[0].remainingPercent, 66)
        XCTAssertFalse(buckets[0].windows[0].isWeekly)
    }
}
