// swift-tools-version: 6.0
import PackageDescription

// Isolated OS boundary and hard-disabled read-only preflight. No shipping target/service.
let package = Package(
    name: "LidNativeAdapter",
    platforms: [.macOS(.v13)],
    products: [.library(name: "LidNativeAdapter", targets: ["LidNativeAdapter"]),
        .executable(name: "LidAttendedPreflight", targets: ["LidAttendedPreflight"])],
    dependencies: [.package(path: "../LidRecoveryBroker")],
    targets: [
        .target(name: "LidNativeAdapter", dependencies: [
            .product(name: "LidRecoveryBroker", package: "LidRecoveryBroker")]),
        .executableTarget(name: "LidAttendedPreflight", dependencies: ["LidNativeAdapter",
            .product(name: "LidRecoveryBroker", package: "LidRecoveryBroker")]),
        .testTarget(name: "LidNativeAdapterTests", dependencies: ["LidNativeAdapter", "LidAttendedPreflight",
            .product(name: "LidRecoveryBroker", package: "LidRecoveryBroker")]),
    ]
)
