import Testing
import Foundation
import CamLidCore
@testable import CamLidApp

@Suite("Friendly sleep explanations")
struct SleepDiagnosticsCopyTests {
    private func blocker(_ id: String, _ type: String, _ effect: SleepEffect,
                         _ owner: String?, pid: Int? = 42) -> DiagnosticBlocker {
        DiagnosticBlocker(id: id, type: type, effect: effect, source: "IOKit", owner: owner, pid: pid,
            explanation: effect.title)
    }

    private func snapshot(_ blockers: [DiagnosticBlocker], preventedBy: [String] = [],
                          coverage: [String: DiagnosticCoverage] = ["preventing": .complete]) -> DiagnosticSnapshot {
        DiagnosticSnapshot(coverage: coverage, blockers: blockers, preventedBy: preventedBy)
    }

    @Test func rawAssertionsBecomePlainLanguageCauses() {
        let causes = SleepDiagnosticsCopy.causes(for: snapshot([
            blocker("1", "PreventUserIdleDisplaySleep", .displayIdle, "FaceTime", pid: 501),
            blocker("2", "BackgroundTask", .systemIdle, "mds_stores"),
            blocker("3", "BackgroundTask", .systemIdle, "dasd"),
            blocker("4", "ApplePushServiceTask", .systemIdle, "nsurlsessiond"),
        ], preventedBy: ["FaceTime"]))
        #expect(causes.first?.title == "FaceTime is on a call")
        #expect(causes.first?.activeNow == true)
        #expect(causes.first?.subtitle == "Keeps your Mac and screen awake")
        #expect(causes.first?.details.first?.owner == "FaceTime")
        #expect(causes.first?.details.first?.pid == 501)
        #expect(Set(causes.map(\.title)) == Set([
            "FaceTime is on a call",
            "Spotlight is organizing files",
            "macOS is doing background work",
            "Your Mac is downloading data in the background",
        ]))
        #expect(SleepDiagnosticsCopy.headline(causes)
            == "FaceTime is on a call. Three other things are also keeping your Mac awake.")
    }

    @Test func relatedAssertionsCollapseIntoOneCause() {
        let causes = SleepDiagnosticsCopy.causes(for: snapshot([
            blocker("1", "BackgroundTask", .systemIdle, "mds_stores"),
            blocker("2", "BackgroundTask", .systemIdle, "mdworker"),
            blocker("3", "BackgroundTask", .systemIdle, "dasd"),
        ]))
        #expect(causes.count == 2)
        #expect(causes.first { $0.title == "Spotlight is organizing files" }?.details.count == 2)
        #expect(causes.first { $0.title == "Spotlight is organizing files" }?.subtitle == "Keeps your Mac awake")
    }

    @Test func unknownOwnersAndMissingCoverageStayGeneric() {
        let causes = SleepDiagnosticsCopy.causes(for: snapshot([
            blocker("1", "FutureAssertion", .unknown, "worker"),
            blocker("2", "BackgroundTask", .systemIdle, nil),
        ], preventedBy: ["dasd"], coverage: ["preventing": .unavailable]))
        #expect(Set(causes.map(\.title)) == Set([
            "Something is using your Mac",
            "Something is keeping your Mac awake",
        ]))
        #expect(causes.allSatisfy { !$0.activeNow })
        #expect(causes.first { $0.title == "Something is using your Mac" }?.subtitle == "macOS reports activity")
        #expect(causes.first { $0.title == "Something is keeping your Mac awake" }?.subtitle
            == "A background process is holding a sleep request")
        #expect(SleepDiagnosticsCopy.headline([]) == "Nothing is keeping your Mac awake right now.")
    }

    @Test func systemWideCausesUseTheirOwnWords() {
        let causes = SleepDiagnosticsCopy.causes(for: snapshot([
            blocker("global", "SleepDisabled", .global, nil),
            blocker("kernel", "KernelAssertions", .kernel, nil),
        ]))
        #expect(Set(causes.map(\.title)) == Set([
            "Sleep is turned off in macOS settings",
            "A connected device is asking your Mac to stay awake",
        ]))
        #expect(causes.first { $0.title == "Sleep is turned off in macOS settings" }?.subtitle
            == "This applies to the whole Mac")
        #expect(causes.first { $0.title == "A connected device is asking your Mac to stay awake" }?.subtitle
            == "This applies to connected hardware")
        #expect(SleepDiagnosticsCopy.headline(causes).hasSuffix("One other thing is also keeping your Mac awake."))
    }

    @Test func pushServiceGetsAFriendlyCause() {
        let causes = SleepDiagnosticsCopy.causes(for: snapshot([
            blocker("1", "ApplePushServiceTask", .systemIdle, "apsd"),
        ]))
        #expect(causes.map(\.title) == ["Push notifications are active"])
        #expect(causes.first?.subtitle == "Keeps your Mac awake")
    }

    @Test func pmsetNamesWithoutIOKitRowsStillAppear() {
        let causes = SleepDiagnosticsCopy.causes(for: snapshot([
            blocker("1", "BackgroundTask", .systemIdle, "dasd"),
        ], preventedBy: ["Brave Browser", "kernel_task"]))
        #expect(causes.count == 3)
        let brave = causes.first { $0.title == "Brave Browser is active" }
        #expect(brave?.activeNow == true)
        #expect(brave?.symbol == "globe")
        #expect(brave?.subtitle == "macOS says this is preventing sleep right now")
        #expect(brave?.details.first?.source == "pmset")
        #expect(causes.first { $0.title == "A connected device is asking your Mac to stay awake" }?.activeNow == true)
    }

    @Test func emptySummaryHonorsCoverage() {
        #expect(SleepDiagnosticsCopy.summary([], appsCoverage: .complete)
            == "Nothing is keeping your Mac awake right now.")
        #expect(SleepDiagnosticsCopy.summary([], appsCoverage: .partial)
            == "We couldn't check everything keeping your Mac awake.")
        #expect(SleepDiagnosticsCopy.summary([], appsCoverage: .unavailable)
            == "We couldn't check what's keeping your Mac awake.")
        #expect(SleepDiagnosticsCopy.summary([], appsCoverage: nil)
            == "We couldn't check what's keeping your Mac awake.")
    }

    @Test func summaryKeepsKnownCausesWhenCoverageIsIncomplete() {
        let causes = SleepDiagnosticsCopy.causes(for: snapshot([
            blocker("1", "FutureAssertion", .displayIdle, "Some App"),
        ], coverage: ["userAssertions": .unavailable, "preventing": .unavailable]))
        #expect(SleepDiagnosticsCopy.summary(causes, appsCoverage: .unavailable)
            == "Some App is active. That's keeping your Mac awake.")
    }

    @Test func bluetoothGetsAFriendlyCause() {
        let causes = SleepDiagnosticsCopy.causes(for: snapshot([
            blocker("1", "PreventUserIdleSystemSleep", .systemIdle, "bluetoothd"),
        ]))
        #expect(causes.map(\.title) == ["Bluetooth is active"])
        #expect(causes.first?.symbol == "antenna.radiowaves.left.and.right")
    }

    @Test func knownUtilitiesGetPurposefulSymbols() {
        let causes = SleepDiagnosticsCopy.causes(for: snapshot([
            blocker("1", "PreventUserIdleSystemSleep", .systemIdle, "LidRun"),
        ]))
        #expect(causes.map(\.title) == ["LidRun is active"])
        #expect(causes.first?.symbol == "laptopcomputer")
    }

    @Test func appLikeOwnerNamesAreUsedWhenNoRuleMatches() {
        let causes = SleepDiagnosticsCopy.causes(for: snapshot([
            blocker("1", "FutureAssertion", .displayIdle, "Some App"),
        ]))
        #expect(causes.map(\.title) == ["Some App is active"])
        #expect(causes.first?.symbol == "macwindow")
        #expect(causes.first?.subtitle == "Keeps your Mac and screen awake")
        #expect(SleepDiagnosticsCopy.headline(causes) == "Some App is active. That's keeping your Mac awake.")
    }
}
