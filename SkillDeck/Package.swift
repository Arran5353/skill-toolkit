// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SkillDeck",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "SkillDeckCore"
        ),
        .executableTarget(
            name: "SkillDeckApp",
            dependencies: ["SkillDeckCore"]
        ),
        .testTarget(
            name: "SkillDeckCoreTests",
            dependencies: ["SkillDeckCore"]
        ),
    ]
)
