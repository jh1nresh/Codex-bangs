import Foundation

public enum PetAnimationState: String, Hashable, Sendable {
    case idle
    case runningRight = "running-right"
    case runningLeft = "running-left"
    case waving
    case jumping
    case failed
    case waiting
    case running
    case review
    case lookDirectionsA = "look-directions-a"
    case lookDirectionsB = "look-directions-b"
}

public struct PetAnimationRow: Equatable, Sendable {
    public let index: Int
    public let state: PetAnimationState
    public let frameDurationsMilliseconds: [Int]
    public let lookDegrees: [Double]

    public var frameCount: Int {
        max(frameDurationsMilliseconds.count, lookDegrees.count)
    }

    public init(
        index: Int,
        state: PetAnimationState,
        frameDurationsMilliseconds: [Int] = [],
        lookDegrees: [Double] = []
    ) {
        self.index = index
        self.state = state
        self.frameDurationsMilliseconds = frameDurationsMilliseconds
        self.lookDegrees = lookDegrees
    }
}

public enum PetV2Contract {
    public static let spriteVersionNumber = 2
    public static let columns = 8
    public static let rows = 11
    public static let cellWidth = 192
    public static let cellHeight = 208
    public static let atlasWidth = 1_536
    public static let atlasHeight = 2_288

    public static let animationRows: [PetAnimationRow] = [
        PetAnimationRow(
            index: 0,
            state: .idle,
            frameDurationsMilliseconds: [280, 110, 110, 140, 140, 320]
        ),
        PetAnimationRow(
            index: 1,
            state: .runningRight,
            frameDurationsMilliseconds: [120, 120, 120, 120, 120, 120, 120, 220]
        ),
        PetAnimationRow(
            index: 2,
            state: .runningLeft,
            frameDurationsMilliseconds: [120, 120, 120, 120, 120, 120, 120, 220]
        ),
        PetAnimationRow(
            index: 3,
            state: .waving,
            frameDurationsMilliseconds: [140, 140, 140, 280]
        ),
        PetAnimationRow(
            index: 4,
            state: .jumping,
            frameDurationsMilliseconds: [140, 140, 140, 140, 280]
        ),
        PetAnimationRow(
            index: 5,
            state: .failed,
            frameDurationsMilliseconds: [140, 140, 140, 140, 140, 140, 140, 240]
        ),
        PetAnimationRow(
            index: 6,
            state: .waiting,
            frameDurationsMilliseconds: [150, 150, 150, 150, 150, 260]
        ),
        PetAnimationRow(
            index: 7,
            state: .running,
            frameDurationsMilliseconds: [120, 120, 120, 120, 120, 220]
        ),
        PetAnimationRow(
            index: 8,
            state: .review,
            frameDurationsMilliseconds: [150, 150, 150, 150, 150, 280]
        ),
        PetAnimationRow(
            index: 9,
            state: .lookDirectionsA,
            lookDegrees: [0, 22.5, 45, 67.5, 90, 112.5, 135, 157.5]
        ),
        PetAnimationRow(
            index: 10,
            state: .lookDirectionsB,
            lookDegrees: [180, 202.5, 225, 247.5, 270, 292.5, 315, 337.5]
        )
    ]
}

public struct PetPackageManifest: Decodable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let description: String?
    public let spriteVersionNumber: Int
    public let spritesheetPath: String

    public init(
        id: String,
        displayName: String,
        description: String? = nil,
        spriteVersionNumber: Int,
        spritesheetPath: String
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.spriteVersionNumber = spriteVersionNumber
        self.spritesheetPath = spritesheetPath
    }
}

public enum PetPackageValidationError: Error, Equatable, Sendable {
    case missingIdentifier
    case unsupportedSpriteVersion(Int)
    case unsafeSpritesheetPath
}

public enum PetPackageValidator {
    public static func validate(_ manifest: PetPackageManifest) throws {
        guard !manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PetPackageValidationError.missingIdentifier
        }
        guard manifest.spriteVersionNumber == PetV2Contract.spriteVersionNumber else {
            throw PetPackageValidationError.unsupportedSpriteVersion(manifest.spriteVersionNumber)
        }

        let path = manifest.spritesheetPath
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !components.contains(".."),
              !components.contains("") else {
            throw PetPackageValidationError.unsafeSpritesheetPath
        }
    }
}

public enum PetStateMapper {
    public static func animation(for state: MonitorState) -> PetAnimationState {
        switch state {
        case .offline, .failed, .unknown:
            return .failed
        case .unavailable:
            return .idle
        case .idle:
            return .idle
        case .working:
            return .running
        case .waiting:
            return .waiting
        case .approval:
            return .review
        }
    }
}
