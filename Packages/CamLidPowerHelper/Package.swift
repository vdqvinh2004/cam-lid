// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CamLidPowerHelper",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CamLidPowerService", targets: ["CamLidPowerService"]),
        .executable(name: "camlid-power-helper", targets: ["camlid-power-helper"]),
        .executable(name: "camlid-power-qa", targets: ["camlid-power-qa"]),
    ],
    dependencies: [
        .package(path: "../LidRecoveryJournal"),
        .package(path: "../LidNativeAdapter"),
    ],
    targets: [
        .target(name: "CamLidPowerService", dependencies: [
            .product(name: "LidRecoveryJournal", package: "LidRecoveryJournal"),
            .product(name: "LidNativeAdapter", package: "LidNativeAdapter"),
        ]),
        .executableTarget(name: "camlid-power-helper", dependencies: ["CamLidPowerService"]),
        .executableTarget(name: "camlid-power-qa", dependencies: ["CamLidPowerService"]),
        .testTarget(name: "CamLidPowerServiceTests", dependencies: ["CamLidPowerService"]),
    ]
)
