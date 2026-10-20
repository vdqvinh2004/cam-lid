import Testing
import CamLidCore
@testable import CamLidApp

@Suite("HIG truthful presentation")
struct HIGPresentationTests {
    @Test func tenStatesKeepCapabilitySeparateFromRequestedMode() {
        let cases: [(EffectiveState, String)] = [(.off,"off"), (.ready,"no work"), (.protected,"working"),
            (.protected,"waiting"), (.unavailable,"stale"), (.completionGrace,"grace"),
            (.safetyStopped,"thermal"), (.unavailable,"unsupported"), (.protected,"preview"),
            (.recoveryRequired,"restore failed")]
        for (state, reason) in cases {
            let preview = DashboardData(mode: .auto, state: state, reasonText: reason,
                leaseVerified: false, graceRemainingSeconds: 30)
            #expect(preview.presentedState != .protected)
            #expect(!preview.graceLabel.lowercased().contains("sleep"))
            #expect(preview.mode == .auto && preview.reasonText == reason)
        }
        let qualified = DashboardData(mode: .auto, state: .protected, reasonText: "verified fixture",
            leaseVerified: true, powerActuationAvailable: true)
        #expect(qualified.presentedState == .protected)
        let leaseOnly = DashboardData(state: .protected, reasonText: "capability unknown", leaseVerified: true)
        #expect(leaseOnly.presentedState == .unavailable)
    }
    @Test func recoveryIsNeverFlattenedToOffAndUnknownTelemetryRemainsUnknown() {
        let data = DashboardData.unknown(reason: "sensor unavailable")
        #expect(data.batteryText == nil && data.cpuText == nil && data.lidDisplayText == nil)
        let recovery = DashboardData(state: .recoveryRequired, reasonText: "unresolved")
        #expect(recovery.presentedState == .recoveryRequired)
    }
}
