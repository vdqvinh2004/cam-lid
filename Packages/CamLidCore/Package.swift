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
    dependencies: [
        .package(path: "../CamLidPowerWire"),
    ],
    targets: [
        .target(
            name: "CamLidCore",
            dependencies: [.product(name: "CamLidPowerWire", package: "CamLidPowerWire")],
            path: "Sources/CamLidCore"
        ),
        .target(
            name: "CamLidCLI",
            dependencies: ["CamLidCore"],
            path: "Sources/CamLidCLI"
        ),
        .target(
            name: "CamLidApp",
            dependencies: ["CamLidCore", "CamLidCLI", .product(name: "CamLidPowerWire", package: "CamLidPowerWire")],
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
