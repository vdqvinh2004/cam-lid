// swift-tools-version: 6.0
import PackageDescription

// Isolated admission/reconciliation experiment. No shipping targets or power APIs.
let package = Package(
    name: "LidRecoveryBroker",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LidRecoveryBroker", targets: ["LidRecoveryBroker"]),
        .executable(name: "LidBrokerFixture", targets: ["LidBrokerFixture"]),
        .executable(name: "LidBrokerServerFixture", targets: ["LidBrokerServerFixture"]),
        .executable(name: "LidRecoveryMonitorFixture", targets: ["LidRecoveryMonitorFixture"]),
    ],
    dependencies: [.package(path: "../LidRecoveryJournal")],
    targets: [
        .target(name: "CPeerIdentity", linkerSettings: [.linkedFramework("Security"), .linkedLibrary("bsm")]),
        .target(name: "LidRecoveryBroker", dependencies: ["LidRecoveryJournal", "CPeerIdentity"]),
        .executableTarget(name: "LidBrokerFixture", dependencies: ["LidRecoveryBroker"]),
        .executableTarget(name: "LidBrokerServerFixture", dependencies: ["LidRecoveryBroker", "LidRecoveryJournal"]),
        .executableTarget(name: "LidRecoveryMonitorFixture", dependencies: ["LidRecoveryBroker"]),
        .testTarget(name: "LidRecoveryBrokerTests", dependencies: ["LidRecoveryBroker", "LidRecoveryJournal",
            "LidBrokerFixture", "LidBrokerServerFixture", "LidRecoveryMonitorFixture"]),
    ]
)
