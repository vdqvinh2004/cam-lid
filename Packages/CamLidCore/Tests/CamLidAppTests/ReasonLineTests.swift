import Testing
import CamLidCore
@testable import CamLidApp

// The dashboard reason line for a stop. Behaviour under test: AppCoordinator.safetyReasonText and helperStopText.
// PowerHoldIntegrationTests covers helperReasonText, the wording for each helper refusal.
@Suite("Dashboard reason line")
@MainActor struct ReasonLineTests {
    @Test func plainSafetyCodesKeepTheirLabels() {
        #expect(AppCoordinator.safetyReasonText(["batteryFloor"]) == "Battery below safety floor")
        #expect(AppCoordinator.safetyReasonText(["batteryFloor", "cpuStop"])
            == "Battery below safety floor; Sustained CPU load exceeded limit")
    }

    @Test func unknownCodesFallBackToOneGenericLine() {
        #expect(AppCoordinator.safetyReasonText(["somethingNew"]) == "Safety condition requires attention")
    }

    @Test func helperStopsNameTheClosedLidCauseWithTheNoticeWording() {
        #expect(AppCoordinator.safetyReasonText(["helperLeaseLost"])
            == "Closed lid lost contact with the helper; sleep was restored automatically")
        let refusal = AppCoordinator.safetyReasonText(["helper:safetyRefused"])
        #expect(refusal.contains("lid open"))
        #expect(!refusal.hasSuffix("."))
        #expect(refusal != "Safety condition requires attention")
    }

    /// The music reason names each source with the words of its Settings chip (it said "a browser" for Chromium).
    @Test func musicReasonUsesTheChipWording() {
        #expect(AppCoordinator.musicReasonText([.browser]) == "Music is playing in Chromium browsers.")
        #expect(AppCoordinator.musicReasonText([.safari, .browser]) == "Music is playing in Chromium browsers and Safari.")
        #expect(MusicSource.allCases.allSatisfy { $0.name == $0.chipTitle })
    }

    @Test func helperStopTextMatchesTheClosedLidNoticeForEveryStopCode() {
        #expect(AppCoordinator.helperStopText("helperReleaseFailed")
            == "The sleep setting could not be restored yet. CamLid is retrying.")
        #expect(AppCoordinator.helperStopText("helper:overrideChanged")
            == AppCoordinator.helperReasonText("overrideChanged"))
    }
}
