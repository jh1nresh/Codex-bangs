import XCTest
@testable import CodexNotchPetCore

final class NotchGeometryTests: XCTestCase {
    func testCollapsedLayoutWithoutNotchUsesTopCenterCapsule() {
        let layout = NotchGeometry.layout(
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            cameraHousing: nil,
            expanded: false,
            noNotchTopOffset: 30,
            metrics: .noNotchDefault
        )

        XCTAssertEqual(layout.frame, CGRect(x: 510, y: 818, width: 420, height: 52))
        XCTAssertNil(layout.centerGap)
        XCTAssertFalse(layout.hasNotch)
    }

    func testNotchedOpenDetailsExtendsDownwardWithoutWidening() {
        let collapsed = NotchGeometry.layout(
            screenFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            cameraHousing: CGRect(x: 666, y: 950, width: 180, height: 32),
            expanded: false
        )
        let expanded = NotchGeometry.layout(
            screenFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            cameraHousing: CGRect(x: 666, y: 950, width: 180, height: 32),
            expanded: true
        )

        XCTAssertEqual(collapsed.frame, CGRect(x: 536, y: 802, width: 440, height: 180))
        XCTAssertEqual(collapsed.centerGap, CGRect(x: 666, y: 950, width: 180, height: 32))
        XCTAssertTrue(collapsed.hasNotch)
        XCTAssertEqual(expanded.frame, CGRect(x: 536, y: 552, width: 440, height: 430))
        XCTAssertEqual(expanded.centerGap, collapsed.centerGap)
        XCTAssertEqual(expanded.frame.minX, collapsed.frame.minX)
        XCTAssertEqual(expanded.frame.width, collapsed.frame.width)
        XCTAssertEqual(expanded.frame.maxY, collapsed.frame.maxY)
    }

    func testDisplayOriginAndCustomMetricsStayInScreenCoordinates() {
        let metrics = NotchPanelMetrics(
            collapsedSize: CGSize(width: 400, height: 50),
            expandedSize: CGSize(width: 500, height: 240)
        )
        let layout = NotchGeometry.layout(
            screenFrame: CGRect(x: 1_920, y: -200, width: 1_728, height: 1_117),
            cameraHousing: CGRect(x: 2_684, y: 887, width: 200, height: 30),
            expanded: true,
            metrics: metrics
        )

        XCTAssertEqual(layout.frame, CGRect(x: 2_534, y: 677, width: 500, height: 240))
        XCTAssertEqual(layout.centerGap, CGRect(x: 2_684, y: 887, width: 200, height: 30))
        XCTAssertEqual(layout.frame.maxY, 917)
    }
}
