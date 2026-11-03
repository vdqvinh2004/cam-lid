import Foundation
import Testing
@testable import CamLidApp

@MainActor private final class ProbeStub: UpdateProbeDriver {
    var checks = 0
    var failToStart = false
    var completion: (@MainActor (UpdateProbeOutcome) -> Void)?
    func checkInformation(completion: @escaping @MainActor (UpdateProbeOutcome) -> Void) throws {
        checks += 1
        if failToStart { throw NSError(domain: "fixture", code: 1) }
        self.completion = completion
    }
    func finish(_ outcome: UpdateProbeOutcome) { let callback = completion; completion = nil; callback?(outcome) }
}
@MainActor private final class UpdateContextBox { var value = UpdateSafetyContext() }

@Suite("Information-only updates") @MainActor
struct UpdateControllerTests {
    @Test func blockersDeferOneExplicitRequest() {
        for key in [\UpdateSafetyContext.sessionActive, \.agentWorkActive, \.recoveryRequired, \.unsavedSettings] {
            let box = UpdateContextBox(); box.value[keyPath: key] = true
            let driver = ProbeStub()
            let controller = UpdateController(safety: { box.value }, makeDriver: { driver })
            controller.check(); controller.refreshSafety()
            #expect(controller.snapshot.phase == .deferred)
            #expect(driver.checks == 0)
            box.value[keyPath: key] = false; controller.refreshSafety()
            #expect(driver.checks == 1)
            driver.finish(.current); controller.refreshSafety()
            #expect(controller.snapshot.phase == .current)
            #expect(driver.checks == 1)
        }
    }
    @Test func activityAppearingDuringCheckDefersResult() {
        let box = UpdateContextBox(); let driver = ProbeStub()
        let controller = UpdateController(safety: { box.value }, makeDriver: { driver })
        controller.check(); box.value.agentWorkActive = true; controller.refreshSafety()
        driver.finish(.available("2.0"))
        #expect(controller.snapshot.phase == .deferred)
        box.value.agentWorkActive = false; controller.refreshSafety()
        #expect(controller.snapshot.phase == .available)
        #expect(controller.snapshot.version == "2.0")
        #expect(driver.checks == 1)
        #expect(!controller.snapshot.installationAvailable)
    }
    @Test func repeatedClicksDoNotQueueChecks() {
        let driver = ProbeStub()
        let controller = UpdateController(safety: { UpdateSafetyContext() }, makeDriver: { driver })
        controller.check(); controller.check(); controller.check(); driver.finish(.current); controller.refreshSafety()
        #expect(driver.checks == 1)
    }
    @Test func outcomesAndRetryNeverInventCurrent() {
        for (outcome, phase) in [(UpdateProbeOutcome.current, UpdatePhase.current), (.available("2"), .available),
                                  (.noCompatibleUpdate, .unavailable), (.offline, .offline), (.failed, .error)] {
            let driver = ProbeStub()
            let controller = UpdateController(safety: { UpdateSafetyContext() }, makeDriver: { driver })
            controller.check(); driver.finish(outcome)
            #expect(controller.snapshot.phase == phase)
            #expect(!controller.snapshot.installationAvailable)
            #expect(controller.canCheck)
            controller.check(); #expect(driver.checks == 2)
        }
    }
    @Test func failedStartCanBeRetried() {
        let driver = ProbeStub(); driver.failToStart = true
        let controller = UpdateController(safety: { UpdateSafetyContext() }, makeDriver: { driver })
        controller.check(); #expect(controller.snapshot.phase == .error)
        driver.failToStart = false; controller.check(); driver.finish(.current)
        #expect(controller.snapshot.phase == .current)
    }

    @Test func theControllerStartsReadyAndNeverInstalls() {
        let controller = UpdateController(safety: { UpdateSafetyContext() }, makeDriver: { ProbeStub() })
        #expect(controller.snapshot.phase == .ready && controller.canCheck && !controller.snapshot.installationAvailable)
    }
}

@Suite("GitHub release check") @MainActor
struct GitHubReleaseCheckTests {
    private func body(_ releases: [[String: Any]]) -> Data { try! JSONSerialization.data(withJSONObject: releases) }
    private let current = ReleaseVersion("0.1.0")!

    @Test func versionsCompareNumerically() {
        #expect(ReleaseVersion("v0.1.0") == ReleaseVersion("0.1"))
        #expect(ReleaseVersion("0.10.0")! > ReleaseVersion("0.9.9")!)
        #expect(ReleaseVersion("1.0")! > ReleaseVersion("0.99.99")!)
        for bad in ["", "v", "1", "1.x", "0.1.0-rc1", "1.2.3.4.5", "1..2", "1.-2", "1.9999999", "latest", "+1.2"] {
            #expect(ReleaseVersion(bad) == nil, "\(bad)")
        }
    }

    @Test func theNewestPublishedReleaseDecidesAndPreReleasesCount() {
        let newer = body([["tag_name": "v0.2.0", "draft": false, "prerelease": true], ["tag_name": "v0.1.0", "draft": false]])
        #expect(GitHubReleaseDriver.outcome(status: 200, body: newer, current: current) == .available("0.2.0"))
        let same = body([["tag_name": "v0.1.0", "draft": false, "prerelease": true]])
        #expect(GitHubReleaseDriver.outcome(status: 200, body: same, current: current) == .current)
        let older = body([["tag_name": "v0.0.9", "draft": false]])
        #expect(GitHubReleaseDriver.outcome(status: 200, body: older, current: current) == .current)
    }

    @Test func draftsAndUnreadableTagsAreSkipped() {
        let mixed = body([["tag_name": "v9.0.0", "draft": true], ["tag_name": "nightly"], ["tag_name": "v0.3.0", "draft": false]])
        #expect(GitHubReleaseDriver.outcome(status: 200, body: mixed, current: current) == .available("0.3.0"))
        #expect(GitHubReleaseDriver.outcome(status: 200, body: body([["tag_name": "v9.0.0", "draft": true]]), current: current) == .noCompatibleUpdate)
    }

    @Test func errorsNeverInventAnUpdate() {
        #expect(GitHubReleaseDriver.outcome(status: 404, body: Data(), current: current) == .noCompatibleUpdate)
        #expect(GitHubReleaseDriver.outcome(status: 403, body: Data("{}".utf8), current: current) == .failed)   // rate limit
        #expect(GitHubReleaseDriver.outcome(status: 200, body: Data("not json".utf8), current: current) == .failed)
        #expect(GitHubReleaseDriver.outcome(status: 200, body: Data(repeating: 0x20, count: 300_000), current: current) == .failed)
        #expect(GitHubReleaseDriver.isOffline(URLError(.notConnectedToInternet)))
        #expect(!GitHubReleaseDriver.isOffline(URLError(.badServerResponse)))
    }

    @Test func theCheckOnlyEverAsksTheProjectsPublicApi() {
        #expect(GitHubReleaseDriver.releasesAPI.host == "api.github.com" && GitHubReleaseDriver.releasesAPI.scheme == "https")
        #expect(GitHubReleaseDriver.releasesAPI.path == "/repos/vdqvinh2004/cam-lid/releases")
        #expect(GitHubReleaseDriver.releasesPage.absoluteString == "https://github.com/vdqvinh2004/cam-lid/releases")
    }
}
