@preconcurrency import AppKit
import CodexNotchPetCore
import ImageIO
import SwiftUI

@MainActor
struct PetSpriteView: View {
    let package: LoadedPetPackage?
    let animation: PetAnimationState
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spriteSheet: PetSpriteSheet?
    @State private var hoverFrame: HoverFrame?
    @State private var gaze = CGVector.zero
    @State private var animationStartedAt = Date.now

    var body: some View {
        GeometryReader { proxy in
            Group {
                if animation == .idle,
                   let hoverFrame,
                   !reduceMotion,
                   let frames = spriteSheet?.framesByState[hoverFrame.state],
                   frames.indices.contains(hoverFrame.index) {
                    sprite(frames[hoverFrame.index])
                } else if let spriteSheet,
                          let frames = spriteSheet.framesByState[animation],
                          !frames.isEmpty {
                    if reduceMotion {
                        sprite(frames[reducedMotionFrameIndex(frameCount: frames.count)])
                    } else {
                        TimelineView(.animation(minimumInterval: 0.08)) { context in
                            sprite(frames[frameIndex(at: context.date, frameCount: frames.count)])
                        }
                    }
                } else {
                    fallback
                }
            }
            .contentShape(Rectangle())
            .gesture(
                TapGesture(count: 2)
                    .onEnded(onDoubleClick)
                    .exclusively(
                        before: TapGesture(count: 1).onEnded(onSingleClick)
                    )
            )
            .onContinuousHover { phase in
                updateHover(phase, in: proxy.size)
            }
        }
        .task(id: package?.spritesheetURL) {
            spriteSheet = package.flatMap(PetSpriteSheet.init(package:))
        }
        .onChange(of: animation) {
            animationStartedAt = .now
            if animation != .idle {
                hoverFrame = nil
            }
        }
        .help("Click to wave · Double-click to play")
        .accessibilityRepresentation {
            Button(package?.manifest.displayName ?? "Bloop", action: onSingleClick)
                .accessibilityHint("Press to wave. Double-press to play.")
                .accessibilityAction(named: "Wave", onSingleClick)
                .accessibilityAction(named: "Play", onDoubleClick)
        }
    }

    private func sprite(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.none)
            .antialiased(false)
            .scaledToFit()
    }

    private var fallback: some View {
        BuiltInPetView(animation: animation, gaze: gaze)
    }

    private func frameIndex(at date: Date, frameCount: Int) -> Int {
        guard let row = PetV2Contract.animationRows.first(where: { $0.state == animation }) else {
            return 0
        }

        let durations = row.frameDurationsMilliseconds.isEmpty
            ? Array(repeating: 180, count: frameCount)
            : Array(row.frameDurationsMilliseconds.prefix(frameCount))
        guard !durations.isEmpty else { return 0 }

        let total = durations.reduce(0, +)
        guard total > 0 else { return 0 }
        let elapsed = max(0, Int(date.timeIntervalSince(animationStartedAt) * 1_000))
        var cursor = elapsed % total

        for (index, duration) in durations.enumerated() {
            if cursor < duration {
                return index
            }
            cursor -= duration
        }
        return 0
    }

    private func reducedMotionFrameIndex(frameCount: Int) -> Int {
        guard frameCount > 1 else { return 0 }
        switch animation {
        case .waving, .jumping, .failed, .waiting, .review, .running:
            return min(frameCount / 2, frameCount - 1)
        case .idle, .runningRight, .runningLeft, .lookDirectionsA, .lookDirectionsB:
            return 0
        }
    }

    private func updateHover(_ phase: HoverPhase, in size: CGSize) {
        guard !reduceMotion else {
            hoverFrame = nil
            gaze = .zero
            return
        }

        switch phase {
        case .ended:
            hoverFrame = nil
            gaze = .zero
        case .active(let location):
            let dx = location.x - size.width / 2
            let dy = location.y - size.height / 2
            gaze = CGVector(
                dx: dx / max(size.width / 2, 1),
                dy: dy / max(size.height / 2, 1)
            )
            guard abs(dx) + abs(dy) > 2 else {
                hoverFrame = nil
                gaze = .zero
                return
            }

            var degrees = atan2(dx, -dy) * 180 / .pi
            if degrees < 0 { degrees += 360 }
            let slot = Int((degrees / 22.5).rounded()) % 16
            let nextFrame = HoverFrame(
                state: slot < 8 ? .lookDirectionsA : .lookDirectionsB,
                index: slot % 8
            )
            if hoverFrame != nextFrame {
                hoverFrame = nextFrame
            }
        }
    }
}

private struct HoverFrame: Equatable {
    let state: PetAnimationState
    let index: Int
}

@MainActor
private struct PetSpriteSheet {
    let framesByState: [PetAnimationState: [NSImage]]

    init?(package: LoadedPetPackage) {
        guard let source = CGImageSourceCreateWithURL(package.spritesheetURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == PetV2Contract.atlasWidth,
              image.height == PetV2Contract.atlasHeight else {
            return nil
        }

        var loaded: [PetAnimationState: [NSImage]] = [:]
        for row in PetV2Contract.animationRows {
            var frames: [NSImage] = []
            for column in 0..<row.frameCount {
                let rect = CGRect(
                    x: column * PetV2Contract.cellWidth,
                    y: row.index * PetV2Contract.cellHeight,
                    width: PetV2Contract.cellWidth,
                    height: PetV2Contract.cellHeight
                )
                guard let frame = image.cropping(to: rect) else { return nil }
                frames.append(
                    NSImage(
                        cgImage: frame,
                        size: NSSize(
                            width: PetV2Contract.cellWidth,
                            height: PetV2Contract.cellHeight
                        )
                    )
                )
            }
            loaded[row.state] = frames
        }
        framesByState = loaded
    }
}
