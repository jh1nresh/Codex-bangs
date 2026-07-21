// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexNotchPet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CodexNotchPetCore",
            targets: ["CodexNotchPetCore"]
        ),
        .executable(
            name: "codex-notch-pet-spike",
            targets: ["CodexNotchPetSpike"]
        )
    ],
    targets: [
        .target(name: "CodexNotchPetCore"),
        .executableTarget(
            name: "CodexNotchPetSpike",
            dependencies: ["CodexNotchPetCore"]
        ),
        .testTarget(
            name: "CodexNotchPetCoreTests",
            dependencies: ["CodexNotchPetCore"],
            resources: [.process("Fixtures")]
        )
    ]
)
