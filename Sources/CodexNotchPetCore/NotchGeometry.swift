import Foundation

public struct NotchPanelMetrics: Equatable, Sendable {
    public static let productDefault = NotchPanelMetrics(
        collapsedSize: CGSize(width: 440, height: 180),
        expandedSize: CGSize(width: 440, height: 370)
    )

    public static let noNotchDefault = NotchPanelMetrics(
        collapsedSize: CGSize(width: 420, height: 52),
        expandedSize: CGSize(width: 440, height: 370)
    )

    public let collapsedSize: CGSize
    public let expandedSize: CGSize

    public init(
        collapsedSize: CGSize,
        expandedSize: CGSize
    ) {
        self.collapsedSize = collapsedSize
        self.expandedSize = expandedSize
    }
}

public struct NotchPanelLayout: Equatable, Sendable {
    /// Panel frame in the same global coordinate space as the input screen frame.
    public let frame: CGRect

    /// Physical notch gap projected into global screen coordinates.
    public let centerGap: CGRect?

    public var hasNotch: Bool {
        centerGap != nil
    }

    public init(frame: CGRect, centerGap: CGRect?) {
        self.frame = frame
        self.centerGap = centerGap
    }
}

public enum NotchGeometry {
    public static func layout(
        screenFrame: CGRect,
        cameraHousing: CGRect?,
        expanded: Bool,
        noNotchTopOffset: CGFloat = 6
    ) -> NotchPanelLayout {
        layout(
            screenFrame: screenFrame,
            cameraHousing: cameraHousing,
            expanded: expanded,
            noNotchTopOffset: noNotchTopOffset,
            metrics: .productDefault
        )
    }

    public static func layout(
        screenFrame: CGRect,
        cameraHousing: CGRect?,
        expanded: Bool,
        noNotchTopOffset: CGFloat = 6,
        metrics: NotchPanelMetrics
    ) -> NotchPanelLayout {
        let screen = screenFrame.standardized
        guard isUsable(screen) else {
            return NotchPanelLayout(frame: .zero, centerGap: nil)
        }

        let requestedSize = expanded ? metrics.expandedSize : metrics.collapsedSize
        let width = min(sanitized(requestedSize.width), screen.width)
        let height = min(sanitized(requestedSize.height), screen.height)
        let topOffset = cameraHousing == nil ? sanitized(noNotchTopOffset) : 0
        let frame = CGRect(
            x: screen.midX - width / 2,
            y: max(screen.minY, screen.maxY - height - topOffset),
            width: width,
            height: height
        )

        guard let cameraHousing,
              isUsable(cameraHousing),
              cameraHousing.intersects(screen),
              width > 0,
              height > 0 else {
            return NotchPanelLayout(frame: frame, centerGap: nil)
        }

        let gap = cameraHousing.intersection(frame)
        guard isUsable(gap) else {
            return NotchPanelLayout(frame: frame, centerGap: nil)
        }
        return NotchPanelLayout(frame: frame, centerGap: gap)
    }

    private static func sanitized(_ value: CGFloat) -> CGFloat {
        guard value.isFinite, value > 0 else { return 0 }
        return value
    }

    private static func isUsable(_ frame: CGRect) -> Bool {
        !frame.isNull
            && !frame.isInfinite
            && frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
            && frame.width > 0
            && frame.height > 0
    }
}
