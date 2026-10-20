// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CamLidCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CamLidCore", targets: ["CamLidCore"]),
        .library(name: "CamLidCLI", targets: ["CamLidCLI"]),
        .library(name: "CamLidApp", targets: ["CamLidApp"]),
        .executable(name: "camlid", targets: ["camlid"]),
    ],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(
            name: "CamLidCore",
            path: "Sources/CamLidCore"
        ),
        .target(
            name: "CamLidCLI",
            dependencies: ["CamLidCore"],
            path: "Sources/CamLidCLI"
        ),
        .target(
            name: "CamLidApp",
            dependencies: ["CamLidCore", "CamLidCLI", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/CamLidApp",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "camlid",
            dependencies: ["CamLidCLI"],
            path: "Sources/camlid"
        ),
        .testTarget(
            name: "CamLidCoreTests",
            dependencies: ["CamLidCore"],
            path: "Tests/CamLidCoreTests",
            exclude: ["Fixtures"]
        ),
        .testTarget(
            name: "CamLidCLITests",
            dependencies: ["CamLidCLI", "CamLidCore"],
            path: "Tests/CamLidCLITests"
        ),
        .testTarget(
            name: "CamLidAppTests",
            dependencies: ["CamLidApp"],
            path: "Tests/CamLidAppTests"
        ),
    ]
)
