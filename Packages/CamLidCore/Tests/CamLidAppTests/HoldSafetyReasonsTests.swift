import Testing
import CamLidCore
@testable import CamLidApp

/// Spec 018 (Q-C): a refused or lost closed-lid lease stops a session only with the lid closed. The behaviour is
/// the pure rule `AppCoordinator.holdSafetyReasons`; PowerHoldIntegrationTests cover it through the coordinator.
@Suite("Hold safety reasons by lid state")
struct HoldSafetyReasonsTests {
    @Test("a refused closed-lid lease stops the session only with the lid closed")
    @MainActor func refusalDependsOnTheLid() {
        let refusal = ["helper:safetyRefused"]
        #expect(AppCoordinator.holdSafetyReasons(lidState: .closed, holdStops: refusal) == refusal)
        #expect(AppCoordinator.holdSafetyReasons(lidState: .open, holdStops: refusal).isEmpty)
        #expect(AppCoordinator.holdSafetyReasons(lidState: .unknown, holdStops: refusal).isEmpty)
        #expect(AppCoordinator.holdSafetyReasons(lidState: nil, holdStops: ["helperLeaseLost"]).isEmpty)
    }
}
