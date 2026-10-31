import Foundation
import Testing
@testable import CamLidPowerService

/// Strict on the persistent helper (ADR 0003, spec 016 T103-T105).
@Suite struct StrictLeaseTests {
    private func fixture() -> (Fixture, FakeClamshellCalls) {
        let f = Fixture(); let fake = FakeClamshellCalls(); f.clamshell = fake
        return (f, fake)
    }
    private func acquireStrict(_ f: Fixture, _ service: PowerLeaseService? = nil) -> PowerReply {
        let s = service ?? f.service
        s.start()
        return s.handle(PowerRequest(operation: .acquire, sequence: 1, sessionSeconds: 300, mechanism: .strict),
                        owner: f.owner, uid: 501)
    }

    @Test func aStrictLeaseSetsOnlyTheBitAndItsReleaseAllowsTheNextSession() throws {
        let (f, fake) = fixture()
        let held = acquireStrict(f)
        #expect(held.accepted && held.mechanismFamily == ClamshellBitMechanism.familyName)
        #expect(fake.bit && f.backend.writes.isEmpty)                    // SleepDisabled untouched
        #expect(f.store.record?.ownerIdentity.hasPrefix("clamshell-bit-v1:") == true)
        let released = f.service.handle(PowerRequest(operation: .release, token: held.token), owner: f.owner, uid: 501)
        #expect(released.accepted && released.state == "restored" && !fake.bit)
        let standard = f.service.handle(PowerRequest(operation: .acquire, sequence: 1, sessionSeconds: 300),
                                        owner: f.owner, uid: 501)
        #expect(standard.accepted && f.backend.disabled)
    }

    @Test func oneLeaseAcrossMechanismsAndStrictNeedsToBeOffered() {
        let (f, _) = fixture()
        #expect(acquireStrict(f).accepted)
        let second = f.service.handle(PowerRequest(operation: .acquire, sequence: 1, sessionSeconds: 300),
                                      owner: UUID(), uid: 501)
        #expect(!second.accepted && f.backend.writes.isEmpty)
        let plain = Fixture()
        #expect(acquireStrict(plain).reason == "mechanismUnavailable")
    }

    @Test func renewalSetsTheBitAgain() {
        let (f, fake) = fixture()
        let held = acquireStrict(f)
        fake.bit = false                                                  // powerd cleared the shared bit
        f.time += 10
        #expect(f.service.handle(PowerRequest(operation: .renew, token: held.token, sequence: 2), owner: f.owner, uid: 501).accepted)
        #expect(fake.bit)
    }

    @Test func aHelperRestartInTheSameBootClearsTheBit() {
        let (f, fake) = fixture()
        #expect(acquireStrict(f).accepted)
        let replacement = f.makeService()
        replacement.start()
        #expect(!fake.bit && replacement.state == "restored")
    }

    @Test func aRecordFromAnotherBootNeedsNoWrite() {
        let (f, fake) = fixture()
        #expect(acquireStrict(f).accepted)
        let calls = fake.log.count
        let afterRestart = f.makeService(bootID: "boot-b")
        afterRestart.start()
        #expect(afterRestart.state == "restored" && fake.log.count == calls)
        #expect(f.store.record?.intent == .restoreLidPolicy && f.store.record?.disposition == .acknowledged)
    }

    @Test func theRecoveryJobClearsAnOrphanedStrictLease() {
        let (f, fake) = fixture()
        #expect(acquireStrict(f).accepted)
        #expect(f.makeService().recoverOrphanedPolicy(graceSeconds: 10) == .leaseStillValid)
        f.time = 200
        #expect(f.makeService().recoverOrphanedPolicy(graceSeconds: 10) == .restored)
        #expect(!fake.bit && f.store.record?.intent == .restoreLidPolicy)
        #expect(f.makeService().recoverOrphanedPolicy(graceSeconds: 10) == .nothingToRecover)
    }

    @Test func theKernelSleepsAClosedMacSoTheHelperSendsNoSleepRequest() {
        let (f, _) = fixture()
        var requests = 0
        f.service.sleepSystem = { requests += 1 }
        let held = acquireStrict(f)
        f.safety = HelperSafety(onAC: true, batteryPercent: 80, thermalNominal: true, consoleUID: 501,
                                lidClosed: true, externalDisplays: 0)
        _ = f.service.handle(PowerRequest(operation: .release, token: held.token), owner: f.owner, uid: 501)
        #expect(requests == 0)
    }

    @Test func systemSleepDuringAStrictLeaseEndsItAsAnInterruption() {
        let (f, fake) = fixture()
        let held = acquireStrict(f)
        #expect(held.accepted)
        f.service.observeSystemSleep()
        let renew = f.service.handle(PowerRequest(operation: .renew, token: held.token, sequence: 2), owner: f.owner, uid: 501)
        #expect(!renew.accepted && renew.reason == "systemSleptWhileHeld")
        #expect(!fake.bit && f.service.state == "restored" && f.service.reason == "systemSleptWhileHeld")
        // The helper is not latched: the next session may start.
        #expect(acquireStrict(f).accepted)
        // Standard is never ended by this signal.
        let standard = Fixture()
        #expect(standard.acquire().accepted)
        standard.service.observeSystemSleep()
        #expect(standard.service.state == "active")
    }
}
