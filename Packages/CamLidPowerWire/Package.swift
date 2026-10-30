// swift-tools-version: 6.0
import PackageDescription

/// Wire types and identity checks shared by the closed-lid helper, its QA client and the app.
/// No IOKit, journal or power calls live here.
let package = Package(
    name: "CamLidPowerWire",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CamLidPowerWire", targets: ["CamLidPowerWire"])],
    targets: [
        .target(name: "CamLidPowerWire"),
        .testTarget(name: "CamLidPowerWireTests", dependencies: ["CamLidPowerWire"]),
    ]
)
