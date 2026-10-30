// swift-tools-version: 6.0
import PackageDescription

// Isolated experimental disk-persistence seam, not a shipping power backend.
let package = Package(
    name: "LidRecoveryJournal",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LidRecoveryJournal", targets: ["LidRecoveryJournal"]),
        .executable(name: "LidJournalFixture", targets: ["LidJournalFixture"]),
    ],
    targets: [
        .target(name: "LidRecoveryJournal"),
        .executableTarget(name: "LidJournalFixture", dependencies: ["LidRecoveryJournal"]),
        .testTarget(name: "LidRecoveryJournalTests", dependencies: ["LidRecoveryJournal", "LidJournalFixture"]),
    ]
)
