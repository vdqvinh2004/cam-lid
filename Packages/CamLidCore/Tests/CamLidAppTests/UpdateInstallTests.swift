import CamLidCore
import Foundation
import Testing
@testable import CamLidApp

/// Records install requests and answers them on demand, so the controller's rules run without a download.
@MainActor final class FakeInstaller: UpdateInstalling {
    var canInstall = true
    var requests: [String] = []
    var cancelled: [Int32] = []
    private var completion: (@MainActor (UpdateInstallOutcome) -> Void)?

    func cancelLaunch(_ pid: Int32) { cancelled.append(pid) }

    func install(_ assets: UpdateAssets, version: String, current: ReleaseVersion,
                 completion: @escaping @MainActor (UpdateInstallOutcome) -> Void) {
        requests.append(version)
        self.completion = completion
    }
    func finish(_ outcome: UpdateInstallOutcome) {
        let callback = completion
        completion = nil
        callback?(outcome)
    }
}

@MainActor private final class ContextBox { var value = UpdateSafetyContext() }
@MainActor private final class Counter { var value = 0 }

private let zipName = "CamLid-0.2.0-macos-arm64.zip"
private let base = "https://github.com/vdqvinh2004/cam-lid/releases/download/v0.2.0/"
private let assets = UpdateAssets(zipURL: URL(string: base + zipName)!, checksumURL: URL(string: base + zipName + ".sha256")!)

@Suite("In-app update install") @MainActor
struct UpdateInstallTests {
    /// A controller that has just found 0.2.0 with the given assets.
    private func found(assets: UpdateAssets?, installer: FakeInstaller, box: ContextBox,
                       launched: @escaping @MainActor () -> Void = {}) -> UpdateController {
        let driver = ProbeStub()
        let controller = UpdateController(safety: { box.value }, makeDriver: { driver }, installer: installer,
                                          defaults: MemoryPreferences(), currentVersion: "0.1.0")
        controller.onInstallLaunched = launched
        controller.check()
        driver.finish(.available("0.2.0", assets))
        return controller
    }

    @Test func aDownloadStartsOnlyAfterTheClickOnAReleaseWithItsAssets() {
        let installer = FakeInstaller()
        let controller = found(assets: assets, installer: installer, box: ContextBox())
        #expect(controller.canInstall)
        #expect(installer.requests.isEmpty)     // offering the update downloads nothing
        controller.installAvailable(endingSession: false)
        #expect(installer.requests == ["0.2.0"])
        #expect(controller.snapshot.phase == .preparing)
    }

    @Test func noButtonWithoutAssetsOrInABuildThatCannotInstall() {
        let installer = FakeInstaller()
        let box = ContextBox()
        let noAssets = found(assets: nil, installer: installer, box: box)
        #expect(!noAssets.canInstall)
        noAssets.installAvailable(endingSession: false)
        #expect(installer.requests.isEmpty)
        installer.canInstall = false
        #expect(!found(assets: assets, installer: installer, box: box).canInstall)
    }

    @Test func aRecoveryStartsNothingAndTheReleaseIsOfferedAgainWhenItEnds() {
        let installer = FakeInstaller()
        let box = ContextBox()
        let controller = found(assets: assets, installer: installer, box: box)
        box.value.recoveryRequired = true
        controller.installAvailable(endingSession: true)
        // The release stays shown (the Dashboard notice depends on it); the reason says why the install waits.
        #expect(controller.snapshot.phase == .available && controller.snapshot.reason == "recoveryRequired")
        #expect(!controller.canInstall)
        #expect(installer.requests.isEmpty)
        box.value.recoveryRequired = false
        controller.refreshSafety()
        #expect(controller.snapshot.phase == .available && controller.snapshot.reason == "updateAvailable")
        #expect(controller.canInstall)
    }

    @Test func aRunningSessionIsEndedOnlyWithTheUsersAgreement() {
        let installer = FakeInstaller()
        let box = ContextBox()
        let controller = found(assets: assets, installer: installer, box: box)
        box.value.sessionActive = true
        #expect(controller.canInstall)                       // a session does not hold the install; the sheet asks first
        controller.installAvailable(endingSession: false)
        #expect(installer.requests.isEmpty)
        controller.installAvailable(endingSession: true)
        #expect(installer.requests == ["0.2.0"])
    }

    @Test func aLaunchedInstallShowsInstallingAndAsksTheAppToQuitOnce() {
        let installer = FakeInstaller()
        let quits = Counter()
        let controller = found(assets: assets, installer: installer, box: ContextBox()) { quits.value += 1 }
        controller.installAvailable(endingSession: false)
        installer.finish(.launched(4242))
        #expect(controller.snapshot.phase == .installing)
        #expect(quits.value == 1)
    }

    @Test func aQuitThatStaysCancelledStopsTheSwapAndSaysWhy() {
        let installer = FakeInstaller()
        let controller = found(assets: assets, installer: installer, box: ContextBox())
        controller.installAvailable(endingSession: false)
        installer.finish(.launched(4242))
        #expect(controller.snapshot.phase == .installing)
        controller.installQuitWasCancelled()
        #expect(installer.cancelled == [4242])
        #expect(controller.snapshot.phase == .error && controller.snapshot.reason == "quitCancelled")
    }

    @Test func aFailedInstallNamesItsCheckAndOffersNoRetryUntilTheNextCheck() {
        let installer = FakeInstaller()
        let controller = found(assets: assets, installer: installer, box: ContextBox())
        controller.installAvailable(endingSession: false)
        installer.finish(.failed("updateSignerMismatch"))
        #expect(controller.snapshot.phase == .error && controller.snapshot.reason == "updateSignerMismatch")
        #expect(!controller.canInstall)
    }

    @Test func releaseAssetsComeOnlyFromGitHubOverHTTPS() {
        func release(_ items: [(String, String)]) -> [String: Any] {
            ["assets": items.map { ["name": $0.0, "browser_download_url": $0.1] as [String: Any] }]
        }
        let complete = release([(zipName, base + zipName), (zipName + ".sha256", base + zipName + ".sha256")])
        #expect(GitHubReleaseDriver.assets(of: complete, version: "0.2.0") == assets)
        #expect(GitHubReleaseDriver.assets(of: release([(zipName, base + zipName)]), version: "0.2.0") == nil)
        let plainHTTP = base.replacingOccurrences(of: "https", with: "http")
        #expect(GitHubReleaseDriver.assets(of: release([(zipName, plainHTTP + zipName), (zipName + ".sha256", base + zipName + ".sha256")]),
                                           version: "0.2.0") == nil)
        #expect(GitHubReleaseDriver.assets(of: release([(zipName, "https://example.com/" + zipName),
                                                        (zipName + ".sha256", base + zipName + ".sha256")]), version: "0.2.0") == nil)
        #expect(GitHubReleaseDriver.assets(of: [:], version: "0.2.0") == nil)
    }
}
