import Testing
@testable import CamLidApp

/// The Updates window's state rules (specs 021 and 026): which button is offered, whether it is enabled, and what it says.
@Suite("Updates window states") @MainActor
struct UpdatesWindowTests {
    private func window(_ phase: UpdatePhase, _ reason: String, canInstall: Bool, canCheck: Bool = true,
                        sessionActive: Bool = false) -> UpdatesView {
        UpdatesView(snapshot: UpdateSnapshot(phase: phase, reason: reason, version: "0.2.0"), canCheck: canCheck,
                    canInstall: canInstall, sessionActive: sessionActive, installedVersion: "0.1.0", onCheck: {})
    }

    @Test func aReadyReleaseOffersAnEnabledUpdate() {
        let view = window(.available, "updateAvailable", canInstall: true)
        #expect(view.showsUpdateButton && view.updateButtonEnabled && !view.isWaitingToInstall)
        #expect(view.detail == "Version 0.2.0 is available; you have 0.1.0. Click Update to download, check and install it. CamLid restarts when the install is done.")
    }

    @Test func aRunningSessionKeepsUpdateEnabledAndSaysItAsksFirst() {
        let view = window(.available, "updateAvailable", canInstall: true, sessionActive: true)
        #expect(view.showsUpdateButton && view.updateButtonEnabled && !view.isWaitingToInstall)
        #expect(view.detail == "Version 0.2.0 is available; you have 0.1.0. Installing stops the running session first. You will be asked to confirm.")
    }

    @Test func aPendingSettingsChangeKeepsADisabledUpdateAndSaysWhy() {
        let view = window(.available, "unsavedSettings", canInstall: false)
        #expect(view.showsUpdateButton && !view.updateButtonEnabled && view.isWaitingToInstall)
        #expect(view.detail == "Version 0.2.0 is available; you have 0.1.0. Installing waits until the pending Settings change is saved.")
        #expect(view.title == "Update available")
    }

    @Test func aRecoveryKeepsADisabledUpdateAndSaysWhy() {
        let view = window(.available, "recoveryRequired", canInstall: false)
        #expect(view.showsUpdateButton && !view.updateButtonEnabled && view.isWaitingToInstall)
        #expect(view.detail.hasSuffix("Installing waits until recovery is finished."))
    }

    @Test func aReleaseWithoutAnInstallerLinksToTheReleasesPage() {
        let view = window(.available, "updateAvailable", canInstall: false)
        #expect(!view.showsUpdateButton && !view.isWaitingToInstall)
        #expect(view.detail.hasSuffix("Download it from the releases page and replace the app."))
    }

    @Test func aQuitThatStaysCancelledSaysTheUpdateDidNotStart() {
        let view = window(.error, "quitCancelled", canInstall: false)
        #expect(view.title.contains("install"))
        #expect(view.detail.hasPrefix("CamLid stayed open, so the update did not start."))
    }

    @Test func theCheckIsOfferedAfterAFailureOrWhenNothingWasFound() {
        #expect(window(.unavailable, "noCompatibleUpdate", canInstall: false).showsButtons)
        #expect(window(.error, "updateCheckFailed", canInstall: false).showsButtons)
        #expect(!window(.checking, "checkingReleases", canInstall: false, canCheck: false).showsButtons)
    }
}
