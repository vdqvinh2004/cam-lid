import Testing
@testable import CamLidApp

/// Only the session the user agreed to end for an install is ended at restart (spec 026 FR-003 and D6). The controller side is in
/// UpdateInstallTests; this covers the identity check that keeps a later session from being ended by an earlier agreement.
@Suite("Session consent for an install") @MainActor
struct SessionConsentTests {
    @Test func theAgreedSessionMayEnd() {
        #expect(AppCoordinator.restartMayProceed(consented: 120, current: 120))
    }

    @Test func aSessionStartedAfterTheAgreementBlocksTheRestart() {
        #expect(!AppCoordinator.restartMayProceed(consented: 120, current: 480))
    }

    @Test func aSessionWithoutAnAgreementBlocksTheRestart() {
        #expect(!AppCoordinator.restartMayProceed(consented: nil, current: 120))
    }

    @Test func noRunningSessionLetsTheRestartProceed() {
        #expect(AppCoordinator.restartMayProceed(consented: nil, current: nil))
        #expect(AppCoordinator.restartMayProceed(consented: 120, current: nil))
    }
}
