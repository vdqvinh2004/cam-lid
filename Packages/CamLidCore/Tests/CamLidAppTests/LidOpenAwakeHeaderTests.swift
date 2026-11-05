import Testing
import CamLidCore
@testable import CamLidApp

/// Spec 018 (T013 follow-up, agreed 2026-11-05): with the lid open and keep-awake verified, the Dashboard and the menu
/// bar say "Keeping awake (lid open)" instead of "Unknown". "Protected" still needs a verified closed-lid lease.
@Suite("Lid-open keep-awake header")
struct LidOpenAwakeHeaderTests {
    @Test func keepingAwakeWithTheLidOpenReplacesUnknownWhileTheLeaseIsUnverified() {
        let data = DashboardData(state: .protected, reasonText: "", leaseVerified: false,
                                 powerActuationAvailable: true, keepingAwakeWithLidOpen: true)
        #expect(data.statusTitle == "Keeping awake (lid open)")
        #expect(data.statusSymbol == "laptopcomputer")
    }

    @Test func withoutTheFlagAnUnverifiedLeaseStillShowsUnknown() {
        let data = DashboardData(state: .protected, reasonText: "", leaseVerified: false,
                                 powerActuationAvailable: true)
        #expect(data.statusTitle == "Unknown")
    }

    @Test func aVerifiedLeaseKeepsProtected() {
        let data = DashboardData(state: .protected, reasonText: "", leaseVerified: true,
                                 powerActuationAvailable: true, keepingAwakeWithLidOpen: true)
        #expect(data.statusTitle == "Protected")
    }

    @Test func theMenuBarLabelSaysKeepingAwakeWithTheLidOpen() {
        let status = MenuBarStatus(state: .protected, leaseVerified: false, keepingAwakeWithLidOpen: true)
        #expect(status.accessibilityLabel == "CamLid: Keeping awake (lid open)")
    }
}
