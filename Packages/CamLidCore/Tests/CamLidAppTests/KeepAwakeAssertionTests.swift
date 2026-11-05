import Foundation
import Testing
import IOKit.pwr_mgt
@testable import CamLidApp

/// Spec 018 (User Story 1): the lid-open keep-awake is held only while wanted, verified only by a read-back of this
/// process's own assertion, and released when no longer wanted.
@Suite("Lid-open keep-awake assertion")
struct KeepAwakeAssertionTests {
    /// Stands in for the power manager and records what CamLid asked of it.
    final class PowerManagerDouble {
        var refuseCreate = false
        var ownNames: [String] = []
        var readBacks = 0
        var created: [IOPMAssertionID] = []
        var released: [IOPMAssertionID] = []
        private var next: IOPMAssertionID = 100

        var system: KeepAwakeSystem {
            KeepAwakeSystem(
                create: { _ in
                    if self.refuseCreate { return nil }
                    self.next += 1
                    self.created.append(self.next)
                    return self.next
                },
                release: { self.released.append($0) },
                ownAssertionNames: {
                    self.readBacks += 1
                    return self.ownNames
                })
        }
    }

    @Test("holds once, reads its own assertion back, and releases it when no longer wanted")
    func holdsReadsBackAndReleases() {
        let manager = PowerManagerDouble()
        manager.ownNames = [KeepAwakeAssertion.reason]
        let keepAwake = KeepAwakeAssertion(system: manager.system)
        keepAwake.reconcile(wanted: true, now: 0)
        keepAwake.reconcile(wanted: true, now: 1)
        #expect(keepAwake.held && keepAwake.verified && keepAwake.issue == nil)
        #expect(manager.created.count == 1)
        keepAwake.reconcile(wanted: false, now: 2)
        #expect(!keepAwake.held && !keepAwake.verified)
        #expect(manager.released == manager.created)
    }

    @Test("an assertion that cannot be read back is held but not verified")
    func missingReadBackIsNotVerified() {
        let manager = PowerManagerDouble()
        let keepAwake = KeepAwakeAssertion(system: manager.system)
        keepAwake.reconcile(wanted: true, now: 0)
        #expect(keepAwake.held)
        #expect(!keepAwake.verified)
        #expect(keepAwake.issue == "readBackMissing")
    }

    @Test("a refused create is reported and tried again on the next pass")
    func refusedCreateIsRetried() {
        let manager = PowerManagerDouble()
        manager.ownNames = [KeepAwakeAssertion.reason]
        manager.refuseCreate = true
        let keepAwake = KeepAwakeAssertion(system: manager.system)
        keepAwake.reconcile(wanted: true, now: 0)
        #expect(!keepAwake.held && keepAwake.issue == "createFailed")
        manager.refuseCreate = false
        keepAwake.reconcile(wanted: true, now: 1)
        #expect(keepAwake.held && keepAwake.verified)
    }

    @Test("while held, the assertion is read back at most every 15 seconds")
    func rereadsOnlyPeriodically() {
        let manager = PowerManagerDouble()
        manager.ownNames = [KeepAwakeAssertion.reason]
        let keepAwake = KeepAwakeAssertion(system: manager.system)
        keepAwake.reconcile(wanted: true, now: 0)
        keepAwake.reconcile(wanted: true, now: 5)
        #expect(manager.readBacks == 1)
        keepAwake.reconcile(wanted: true, now: 15)
        #expect(manager.readBacks == 2)
    }

    @Test("releasing twice releases once")
    func releaseIsIdempotent() {
        let manager = PowerManagerDouble()
        manager.ownNames = [KeepAwakeAssertion.reason]
        let keepAwake = KeepAwakeAssertion(system: manager.system)
        keepAwake.reconcile(wanted: true, now: 0)
        keepAwake.release()
        keepAwake.release()
        #expect(manager.released.count == 1)
    }
}
