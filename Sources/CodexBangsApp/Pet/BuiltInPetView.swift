import CodexNotchPetCore
import CoreGraphics
import SwiftUI

@MainActor
struct BuiltInPetView: View {
    let animation: PetAnimationState
    let gaze: CGVector

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `gaze` uses screen coordinates: `dx` is left (-1) to right (+1), and
    /// `dy` is up (-1) to down (+1). Values outside that range are clamped.
    init(animation: PetAnimationState, gaze: CGVector = .zero) {
        self.animation = animation
        self.gaze = gaze
    }

    var body: some View {
        GeometryReader { proxy in
            if reduceMotion {
                bloop(at: 0, in: proxy.size, animated: false)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    bloop(
                        at: context.date.timeIntervalSinceReferenceDate,
                        in: proxy.size,
                        animated: true
                    )
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bloop, the built-in Codex pet")
        .accessibilityValue(accessibilityState)
    }

    private func bloop(
        at time: TimeInterval,
        in size: CGSize,
        animated: Bool
    ) -> some View {
        let side = min(size.width, size.height)
        let visualState = BloopVisualState(animation)
        let pose = BloopPose(
            state: visualState,
            time: time,
            animated: animated,
            travelDirection: travelDirection
        )

        return BloopDrawing(
            side: side,
            state: visualState,
            pose: pose,
            gaze: animated ? normalizedGaze : .zero
        )
        .frame(width: size.width, height: size.height)
    }

    private var normalizedGaze: CGVector {
        CGVector(
            dx: min(max(gaze.dx, -1), 1),
            dy: min(max(gaze.dy, -1), 1)
        )
    }

    private var travelDirection: CGFloat {
        switch animation {
        case .runningLeft:
            return -1
        case .runningRight:
            return 1
        default:
            return 0
        }
    }

    private var accessibilityState: String {
        switch BloopVisualState(animation) {
        case .idle:
            return "Idle"
        case .running:
            return "Working"
        case .waiting:
            return "Waiting for you"
        case .review:
            return "Ready for review"
        case .failed:
            return "Needs attention"
        case .waving:
            return "Waving"
        case .jumping:
            return "Jumping"
        }
    }
}

private enum BloopVisualState {
    case idle
    case running
    case waiting
    case review
    case failed
    case waving
    case jumping

    init(_ animation: PetAnimationState) {
        switch animation {
        case .running, .runningRight, .runningLeft:
            self = .running
        case .waiting:
            self = .waiting
        case .review:
            self = .review
        case .failed:
            self = .failed
        case .waving:
            self = .waving
        case .jumping:
            self = .jumping
        case .idle, .lookDirectionsA, .lookDirectionsB:
            self = .idle
        }
    }
}

private struct BloopPose {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rotation = Angle.zero
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var leftArmDegrees: CGFloat = 12
    var rightArmDegrees: CGFloat = -12
    var footStride: CGFloat = 0

    init(
        state: BloopVisualState,
        time: TimeInterval,
        animated: Bool,
        travelDirection: CGFloat
    ) {
        guard animated else {
            applyReducedMotionPose(for: state)
            return
        }

        switch state {
        case .idle:
            let breath = CGFloat(sin(time * 1.8))
            y = -0.35 - breath * 0.35
            scaleX = 1 - breath * 0.006
            scaleY = 1 + breath * 0.010
        case .running:
            let cadence = CGFloat(sin(time * 8.5))
            let lean = travelDirection == 0 ? 0 : travelDirection * 1.4
            x = cadence * 0.7 + travelDirection * 0.6
            y = -abs(cadence) * 0.8
            rotation = .degrees(lean + cadence * 1.8)
            scaleX = 1 + abs(cadence) * 0.012
            scaleY = 1 - abs(cadence) * 0.012
            leftArmDegrees = 12 + cadence * 8
            rightArmDegrees = -12 - cadence * 8
            footStride = cadence * 1.5
        case .waiting:
            let sway = CGFloat(sin(time * 2.2))
            y = -abs(sway) * 0.35
            rotation = .degrees(sway * 1.2)
            leftArmDegrees = 20 + sway * 2
            rightArmDegrees = -20 - sway * 2
        case .review:
            let focus = CGFloat(sin(time * 2.5))
            y = -0.25 - abs(focus) * 0.2
            rotation = .degrees(-1 + focus * 0.45)
            leftArmDegrees = 17
            rightArmDegrees = -8
        case .failed:
            let breath = CGFloat(sin(time * 1.4))
            y = 1.8 + breath * 0.15
            rotation = .degrees(-2.4)
            scaleX = 1.015
            scaleY = 0.975
            leftArmDegrees = 24
            rightArmDegrees = -24
        case .waving:
            let wave = CGFloat(sin(time * 9.0))
            y = -0.4
            rotation = .degrees(-0.8 + wave * 0.45)
            rightArmDegrees = -38 + wave * 12
            leftArmDegrees = 10
        case .jumping:
            let jump = abs(CGFloat(sin(time * 2.8)))
            y = -jump * 4.2
            rotation = .degrees(CGFloat(sin(time * 2.8)) * 1.2)
            scaleX = 1 - jump * 0.025
            scaleY = 1 + jump * 0.035
            leftArmDegrees = 22 + jump * 8
            rightArmDegrees = -22 - jump * 8
        }
    }

    private mutating func applyReducedMotionPose(for state: BloopVisualState) {
        switch state {
        case .idle:
            break
        case .running:
            rotation = .degrees(1)
            leftArmDegrees = 16
            rightArmDegrees = -16
        case .waiting:
            leftArmDegrees = 20
            rightArmDegrees = -20
        case .review:
            rotation = .degrees(-1)
            leftArmDegrees = 17
            rightArmDegrees = -8
        case .failed:
            y = 1.5
            rotation = .degrees(-2)
            scaleX = 1.01
            scaleY = 0.98
            leftArmDegrees = 24
            rightArmDegrees = -24
        case .waving:
            rightArmDegrees = -38
        case .jumping:
            y = -1.5
            leftArmDegrees = 26
            rightArmDegrees = -26
        }
    }
}

private struct BloopDrawing: View {
    let side: CGFloat
    let state: BloopVisualState
    let pose: BloopPose
    let gaze: CGVector

    var body: some View {
        ZStack {
            feet
            arm(onRight: false)
            arm(onRight: true)

            BloopBodyShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.88, blue: 0.94),
                            Color(red: 0.25, green: 0.42, blue: 0.94)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    BloopBodyShape()
                        .stroke(.white.opacity(0.30), lineWidth: max(0.8, side * 0.016))
                }
                .frame(width: side * 0.68, height: side * 0.67)
                .offset(y: side * 0.055)

            Ellipse()
                .fill(.white.opacity(0.15))
                .frame(width: side * 0.31, height: side * 0.14)
                .rotationEffect(.degrees(-24))
                .offset(x: -side * 0.11, y: -side * 0.105)

            BloopBangsShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.20, blue: 0.58),
                            Color(red: 0.31, green: 0.24, blue: 0.72)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: side * 0.53, height: side * 0.20)
                .offset(y: -side * 0.225)

            face
        }
        .frame(width: side, height: side)
        .scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: .bottom)
        .rotationEffect(pose.rotation, anchor: .bottom)
        .offset(x: pose.x, y: pose.y)
    }

    private var feet: some View {
        ZStack {
            Capsule()
                .fill(Color(red: 0.19, green: 0.25, blue: 0.69))
                .frame(width: side * 0.25, height: side * 0.12)
                .offset(
                    x: -side * 0.16 + pose.footStride,
                    y: side * 0.36
                )
            Capsule()
                .fill(Color(red: 0.19, green: 0.25, blue: 0.69))
                .frame(width: side * 0.25, height: side * 0.12)
                .offset(
                    x: side * 0.16 - pose.footStride,
                    y: side * 0.36
                )
        }
    }

    private func arm(onRight: Bool) -> some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.13, green: 0.73, blue: 0.90),
                        Color(red: 0.25, green: 0.35, blue: 0.82)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: side * 0.14, height: side * 0.30)
            .rotationEffect(
                .degrees(onRight ? pose.rightArmDegrees : pose.leftArmDegrees),
                anchor: .bottom
            )
            .offset(x: (onRight ? 1 : -1) * side * 0.335, y: side * 0.08)
    }

    private var face: some View {
        VStack(spacing: side * 0.055) {
            HStack(spacing: side * 0.10) {
                eye(onRight: false)
                eye(onRight: true)
            }

            BloopMouthShape(style: mouthStyle)
                .stroke(
                    Color(red: 0.10, green: 0.12, blue: 0.34).opacity(0.88),
                    style: StrokeStyle(
                        lineWidth: max(1, side * 0.026),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: side * 0.19, height: side * 0.11)
        }
        .offset(y: side * 0.035)
    }

    private func eye(onRight: Bool) -> some View {
        ZStack {
            Capsule()
                .fill(.white.opacity(0.94))

            Circle()
                .fill(Color(red: 0.08, green: 0.10, blue: 0.30))
                .frame(width: side * 0.052, height: side * 0.052)
                .offset(
                    x: gaze.dx * side * 0.027,
                    y: gaze.dy * side * 0.022
                )
                .opacity(state == .failed ? 0 : 1)
        }
        .frame(width: side * 0.13, height: side * 0.15 * eyeHeightScale)
        .rotationEffect(.degrees(eyeTilt(onRight: onRight)))
    }

    private var eyeHeightScale: CGFloat {
        switch state {
        case .failed:
            return 0.20
        case .review:
            return 0.62
        case .waiting:
            return 1.08
        case .idle, .running, .waving, .jumping:
            return 1
        }
    }

    private func eyeTilt(onRight: Bool) -> CGFloat {
        switch state {
        case .failed:
            return onRight ? 10 : -10
        case .review:
            return onRight ? -4 : 4
        default:
            return 0
        }
    }

    private var mouthStyle: BloopMouthStyle {
        switch state {
        case .waiting:
            return .waiting
        case .review, .running:
            return .focused
        case .failed:
            return .failed
        case .idle, .waving, .jumping:
            return .smile
        }
    }
}

private enum BloopMouthStyle {
    case smile
    case waiting
    case focused
    case failed
}

private struct BloopMouthShape: Shape {
    let style: BloopMouthStyle

    func path(in rect: CGRect) -> Path {
        var path = Path()

        switch style {
        case .smile:
            path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.24))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.height * 0.24),
                control: CGPoint(x: rect.midX, y: rect.maxY)
            )
        case .waiting:
            path.addEllipse(in: CGRect(
                x: rect.midX - rect.width * 0.18,
                y: rect.midY - rect.height * 0.27,
                width: rect.width * 0.36,
                height: rect.height * 0.54
            ))
        case .focused:
            path.move(to: CGPoint(x: rect.width * 0.16, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.width * 0.84, y: rect.midY))
        case .failed:
            path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.76))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.height * 0.76),
                control: CGPoint(x: rect.midX, y: rect.minY)
            )
        }

        return path
    }
}

private struct BloopBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.height * 0.42),
            control1: CGPoint(x: rect.width * 0.79, y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: rect.height * 0.18)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.78, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.height * 0.72),
            control2: CGPoint(x: rect.width * 0.94, y: rect.maxY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.22, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.height * 0.91)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.height * 0.42),
            control1: CGPoint(x: rect.width * 0.06, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.height * 0.72)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.height * 0.18),
            control2: CGPoint(x: rect.width * 0.21, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

private struct BloopBangsShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.30))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.height * 0.30),
            control: CGPoint(x: rect.midX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.55))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.68, y: rect.height * 0.63),
            control: CGPoint(x: rect.width * 0.84, y: rect.maxY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.43, y: rect.height * 0.72),
            control: CGPoint(x: rect.width * 0.57, y: rect.maxY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.height * 0.55),
            control: CGPoint(x: rect.width * 0.21, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}
