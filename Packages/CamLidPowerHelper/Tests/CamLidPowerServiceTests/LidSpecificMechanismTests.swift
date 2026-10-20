import Foundation
import IOKit
import IOKit.pwr_mgt
import Testing
import LidRecoveryJournal
@_spi(TestInputs) import LidNativeAdapter
@_spi(CandidateInputs) @testable import CamLidPowerService

private final class LidCalls {
    var events: [String] = []
    var properties: [String: Any] = [:]
    var selectorCode: Int32 = 0
    var idleReleaseCode: Int32 = 0
    var openCode: Int32 = 0
    var matching: UInt32 = 7

    lazy var assertions = NativePowerSystemCalls(createAssertion: { [self] properties in
        self.properties = properties as! [String: Any]
        events.append("idleCreate")
        return NativeAssertionCreation(code: 0, id: 42)
    }, releaseAssertion: { [self] id in
        events.append("idleRelease:\(id)")
        return idleReleaseCode
    }, currentPID: { 123 })

    lazy var root = NativeRootDomainSystemCalls(matchingService: { [self] in
        events.append("match"); return matching
    }, open: { [self] service in
        events.append("open:\(service)"); return (openCode, openCode == 0 ? 17 : 0)
    }, releaseService: { [self] service in
        events.append("release:\(service)"); return 0
    }, scalarCall: { [self] connection, selector, value in
        events.append("scalar:\(connection):\(selector):\(value)"); return selectorCode
    }, close: { [self] connection in
        events.append("close:\(connection)"); return 0
    })

    lazy var mechanism = LidSpecificMechanism(assertionCalls: assertions, rootCalls: root)
}

private final class LidIntentStore: PowerIntentStore {
    var entry: JournalEntry?
    var commits = 0
    var failAt: Int?
    var onCommit: (() -> Void)?
    func load() throws -> JournalEntry? { entry }
    func commit(_ next: JournalEntry, replacing revision: UInt64?) throws {
        commits += 1
        if commits == failAt { throw PowerServiceFailure.journal }
        guard entry?.revision == revision else { throw PowerServiceFailure.journal }
        entry = next
        onCommit?()
    }
}

private final class LidLeaseFixture {
    let calls = LidCalls()
    let store = LidIntentStore()
    let owner = UUID()
    var time = 100.0
    var baselineAllowed = true
    var foreignPolicy: ForeignPolicyObservation = .clear
    var foreignPolicyThrows = false
    var foreignPolicyReads = 0
    lazy var mechanism = LidOnlyLeaseMechanism(
        make: { self.calls.mechanism },
        baselineAllowsLidSleep: { self.baselineAllowed },
        foreignPolicy: {
            self.foreignPolicyReads += 1
            if self.foreignPolicyThrows { throw PowerServiceFailure.backend }
            return self.foreignPolicy
        })
    lazy var service = makeService()
    func makeService() -> PowerLeaseService {
        PowerLeaseService(mechanism: mechanism, store: store, bootID: "boot-lid",
            clock: { self.time }, safety: {
                HelperSafety(onAC: true, batteryPercent: 80, thermalNominal: true,
                             consoleUID: 501, lidClosed: false, externalDisplays: 0)
            })
    }
    func acquire(seconds: Int = 24) -> PowerReply {
        service.start()
        return service.handle(PowerRequest(operation: .acquire, sequence: 1, sessionSeconds: seconds),
                              owner: owner, uid: 501)
    }
}

@Suite struct LidSpecificMechanismTests {
    @Test func reusesNarrowClamshellControlAndProcessOwnedIdle() throws {
        let f = LidCalls()
        try f.mechanism.acquireIdle(remainingNanos: 30_000_000_000, episodeID: UUID())
        #expect(f.properties[kIOPMAssertionTypeKey] as? String == kIOPMAssertionTypePreventUserIdleSystemSleep)
        #expect(f.properties[kIOPMAssertionTimeoutActionKey] as? String == kIOPMAssertionTimeoutActionRelease)
        #expect((f.properties[kIOPMAssertionTimeoutKey] as? NSNumber)?.intValue == 30)
        let enabled = try f.mechanism.suppressLidAfterJournalCommit()
        #expect(enabled.allCallsSucceeded)
        let cleared = try f.mechanism.clearLidAfterJournalCommit()
        #expect(cleared.allCallsSucceeded)
        #expect(!cleared.restorationVerified)
        #expect(try f.mechanism.releaseOwnedIdle() == 0)
        #expect(f.events == ["idleCreate", "match", "open:7", "release:7", "scalar:17:12:1", "close:17",
                             "match", "open:7", "release:7", "scalar:17:12:0", "close:17", "idleRelease:42"])
        #expect(!f.mechanism.mutatesGlobalSleepDisabled)
        #expect(!f.mechanism.sharedLidControlHasOSOwnedExpiry)
    }

    @Test func neverDispatchesWithoutIdleOrBeyondFiniteIdleBounds() {
        let f = LidCalls()
        #expect(throws: LidSpecificFailure.idleNotReady) { try f.mechanism.suppressLidAfterJournalCommit() }
        #expect(f.events.isEmpty)
        for remaining in [UInt64(0), 999_999_999, 30_000_000_001] {
            let invalid = LidCalls()
            #expect(throws: NativePowerBoundaryFailure.invalidDuration) {
                try invalid.mechanism.acquireIdle(remainingNanos: remaining, episodeID: UUID())
            }
            #expect(invalid.events.isEmpty)
        }
    }

    @Test func failedDispatchCannotAuthorizeBlindClearOrRepeatEnable() throws {
        for step in ["match", "open", "selector"] {
            let f = LidCalls()
            if step == "match" { f.matching = 0 }
            if step == "open" { f.openCode = -1 }
            if step == "selector" { f.selectorCode = -1 }
            try f.mechanism.acquireIdle(remainingNanos: 30_000_000_000, episodeID: UUID())
            #expect(try !f.mechanism.suppressLidAfterJournalCommit().allCallsSucceeded)
            let before = f.events
            #expect(throws: LidSpecificFailure.suppressionNotAcknowledged) { try f.mechanism.clearLidAfterJournalCommit() }
            #expect(throws: LidSpecificFailure.lidAlreadyAttempted) { try f.mechanism.suppressLidAfterJournalCommit() }
            #expect(f.events == before)
            #expect(try f.mechanism.releaseOwnedIdle() == 0)
        }
    }

    @Test func assertionTimeoutLeavesFiveSecondCleanupMarginAfterTwentyFourSecondLease() throws {
        let f = LidCalls()
        let mechanism = LidOnlyLeaseMechanism(make: { f.mechanism }, baselineAllowsLidSleep: { true })
        try mechanism.apply(remainingNanos: 23_999_000_000, episodeID: UUID())
        #expect((f.properties[kIOPMAssertionTimeoutKey] as? NSNumber)?.intValue == 29)
        #expect(mechanism.maximumSessionSeconds == 24)
        _ = try mechanism.clear()
    }

    @Test func sessionCapPollCleansBeforeAssertionExpiry() {
        let f = LidLeaseFixture()
        let started = f.acquire()
        #expect(started.accepted)
        f.time += 24
        f.service.poll()
        #expect(f.service.state == "cleanupAcknowledged")
        #expect(f.store.entry?.intent == .restoreLidPolicy)
        #expect(f.calls.events.suffix(6) == ["match", "open:7", "release:7", "scalar:17:12:0", "close:17", "idleRelease:42"])
    }

    @Test func activeForeignGlobalPolicyStopsAndNeverClearsTheForeignFlag() {
        let f = LidLeaseFixture()
        #expect(f.acquire().accepted)
        f.foreignPolicy = .conflicted
        f.service.poll()
        #expect(f.service.state == "recoveryRequired")
        #expect(f.service.reason == "foreignGlobalSleepDisabled")
        #expect(f.foreignPolicyReads > 0)
        #expect(f.foreignPolicy == .conflicted)
        #expect(f.store.entry?.intent == .restoreLidPolicy)
        #expect(f.store.entry?.disposition == .acknowledged)
        #expect(f.calls.events.suffix(6) == ["match", "open:7", "release:7",
                                             "scalar:17:12:0", "close:17", "idleRelease:42"])
        #expect(f.calls.events.filter { $0 == "scalar:17:12:0" }.count == 1)
    }

    @Test func unreadableForeignPolicyFailsClosedWithItsOwnReason() {
        let f = LidLeaseFixture()
        #expect(f.acquire().accepted)
        f.foreignPolicy = .unreadable
        f.service.poll()
        #expect(f.service.state == "recoveryRequired")
        #expect(f.service.reason == "foreignPolicyUnreadable")
        #expect(f.store.entry?.intent == .restoreLidPolicy)
        #expect(f.calls.events.filter { $0 == "scalar:17:12:0" }.count == 1)
    }

    @Test func throwingForeignProbeIsUnreadableNotHealthy() {
        let f = LidLeaseFixture()
        #expect(f.acquire().accepted)
        f.foreignPolicyThrows = true
        f.service.poll()
        #expect(f.service.state == "recoveryRequired")
        #expect(f.service.reason == "foreignPolicyUnreadable")
        #expect(f.calls.events.filter { $0 == "scalar:17:12:0" }.count == 1)
    }

    @Test func clearForeignPolicyLeavesTheActiveSessionRunning() {
        let f = LidLeaseFixture()
        #expect(f.acquire().accepted)
        f.foreignPolicy = .clear
        f.service.poll()
        #expect(f.service.state == "active")
        #expect(f.calls.events.filter { $0 == "scalar:17:12:0" }.isEmpty)
    }

    @Test func foreignStopIsOneShotAndCannotRearm() {
        let f = LidLeaseFixture()
        #expect(f.acquire().accepted)
        f.foreignPolicy = .conflicted
        f.service.poll()
        let events = f.calls.events
        f.service.poll()
        f.foreignPolicy = .clear
        f.service.poll()
        f.service.disconnected(owner: f.owner)
        f.service.shutdown()
        #expect(f.calls.events == events)
        #expect(f.service.state == "recoveryRequired")
        #expect(!f.service.handle(PowerRequest(operation: .acquire, sequence: 1, sessionSeconds: 24),
                                  owner: f.owner, uid: 501).accepted)
    }

    @Test func foreignConflictSurvivesSameBootRestartWithoutAnotherClear() {
        let f = LidLeaseFixture()
        #expect(f.acquire().accepted)
        f.foreignPolicy = .conflicted
        f.service.poll()
        let events = f.calls.events
        let replacement = f.makeService()
        replacement.start()
        #expect(replacement.state == "recoveryRequired")
        #expect(replacement.reason == "foreignGlobalSleepDisabled")
        #expect(f.calls.events == events)
        f.foreignPolicy = .unreadable
        let unreadable = f.makeService()
        unreadable.start()
        #expect(unreadable.state == "recoveryRequired")
        #expect(unreadable.reason == "foreignPolicyUnreadable")
        #expect(f.calls.events == events)
        f.foreignPolicy = .clear
        let benign = f.makeService()
        benign.start()
        #expect(benign.state == "cleanupAcknowledged")
        #expect(f.calls.events == events)
    }

    @Test(arguments: [ForeignPolicyObservation.conflicted, .unreadable])
    func foreignPolicyOnRestartAfterEnableClearsOwnLidOnceAndStaysRecovery(
        foreign: ForeignPolicyObservation
    ) {
        let f = LidLeaseFixture()
        #expect(f.acquire().accepted)
        f.foreignPolicy = foreign
        let replacement = f.makeService()
        replacement.start()
        #expect(replacement.state == "recoveryRequired")
        #expect(replacement.reason == (foreign == .conflicted
            ? "foreignGlobalSleepDisabled" : "foreignPolicyUnreadable"))
        #expect(f.calls.events.filter { $0 == "scalar:17:12:0" }.count == 1)
        let events = f.calls.events
        replacement.poll()
        #expect(f.calls.events == events)
        #expect(!replacement.handle(PowerRequest(operation: .acquire, sequence: 1, sessionSeconds: 24),
                                    owner: f.owner, uid: 501).accepted)
    }

    @Test func delayedPollPastAssertionExpiryStaysUncertainAndCannotRearm() {
        let f = LidLeaseFixture()
        #expect(f.acquire().accepted)
        f.time += 31
        f.calls.idleReleaseCode = kIOReturnNotFound
        f.service.poll()
        #expect(f.service.state == "recoveryRequired")
        #expect(f.service.reason == "restorationFailed")
        let attempts = f.calls.events
        f.service.poll()
        f.service.disconnected(owner: f.owner)
        f.service.shutdown()
        #expect(f.calls.events == attempts)
        #expect(f.calls.events.filter { $0 == "idleRelease:42" }.count == 1)
        #expect(!f.service.handle(PowerRequest(operation: .acquire, sequence: 1, sessionSeconds: 24), owner: f.owner, uid: 501).accepted)
    }

    @Test(arguments: [3, 4]) func cleanupJournalFailureNeverClaimsRestorationOrRetriesClear(commit: Int) {
        let f = LidLeaseFixture()
        #expect(f.acquire().accepted)
        f.store.failAt = commit
        f.time += 24
        f.service.poll()
        #expect(f.service.state == "recoveryRequired")
        let attempts = f.calls.events
        f.service.poll()
        f.service.disconnected(owner: f.owner)
        f.service.shutdown()
        #expect(f.calls.events == attempts)
        let clears = f.calls.events.filter { $0 == "scalar:17:12:0" }.count
        #expect(clears == (commit == 3 ? 0 : 1))
        #expect(!f.service.handle(PowerRequest(operation: .acquire, sequence: 1, sessionSeconds: 24), owner: f.owner, uid: 501).accepted)
    }

    @Test func leaseControllerReportsAcknowledgedCleanupOnlyAndRefusesRearm() {
        let f = LidLeaseFixture()
        let started = f.acquire()
        #expect(started.accepted && started.state == "active")
        #expect(started.mechanismFamily == "lid-specific-v1")
        #expect(f.calls.properties[kIOPMAssertionTimeoutKey] as? Int == 30)
        #expect(f.store.entry?.ownerIdentity.hasPrefix("lid-specific-v1:") == true)
        let stopped = f.service.handle(PowerRequest(operation: .release, token: started.token), owner: f.owner, uid: 501)
        #expect(!stopped.accepted && stopped.state == "cleanupAcknowledged")
        #expect(stopped.reason == "userStop")
        #expect(!stopped.qualifiedClosedLidProtection)
        let second = f.service.handle(PowerRequest(operation: .acquire, sequence: 1, sessionSeconds: 24), owner: f.owner, uid: 501)
        #expect(!second.accepted && second.reason == "notReady")
        let replacement = f.makeService()
        replacement.start()
        #expect(replacement.state == "cleanupAcknowledged")
        #expect(replacement.reason == "sharedLidRestorationUnverified")
        #expect(f.calls.events == ["idleCreate", "match", "open:7", "release:7", "scalar:17:12:1", "close:17",
                                   "match", "open:7", "release:7", "scalar:17:12:0", "close:17", "idleRelease:42"])
    }

    @Test func leaseControllerRollsBackOrReleasesIdleOnApplyFailure() {
        let ackFail = LidLeaseFixture()
        ackFail.store.failAt = 2
        let rollback = ackFail.acquire()
        #expect(!rollback.accepted && rollback.state == "cleanupAcknowledged")
        #expect(ackFail.calls.events == ["idleCreate", "match", "open:7", "release:7", "scalar:17:12:1", "close:17",
                                         "match", "open:7", "release:7", "scalar:17:12:0", "close:17", "idleRelease:42"])

        let selectorFail = LidLeaseFixture()
        selectorFail.calls.selectorCode = -1
        let failed = selectorFail.acquire()
        #expect(!failed.accepted && failed.state == "recoveryRequired")
        #expect(selectorFail.calls.events == ["idleCreate", "match", "open:7", "release:7", "scalar:17:12:1", "close:17",
                                              "idleRelease:42"])
    }

    @Test func leaseControllerRejectsOverlongSessionsUnhealthyBaselineAndCrossMechanismJournals() {
        let tooLong = LidLeaseFixture()
        #expect(!tooLong.acquire(seconds: 25).accepted)
        #expect(tooLong.calls.events.isEmpty)

        let baseline = LidLeaseFixture()
        baseline.baselineAllowed = false
        #expect(baseline.acquire().reason == "preexistingOverride")
        #expect(baseline.calls.events.isEmpty)

        let changed = LidLeaseFixture()
        changed.store.onCommit = { changed.baselineAllowed = false }
        #expect(changed.acquire().reason == "admissionChangedBeforeWrite")
        #expect(changed.calls.events.isEmpty)

        let cross = LidLeaseFixture()
        cross.store.entry = JournalEntry(revision: 1, sessionID: UUID().uuidString, ownerIdentity: "uid:501:connection:1",
            bootID: "boot-lid", generation: 1, operationID: UUID().uuidString, intent: .enableLidOverride,
            disposition: .acknowledged, continuousDeadlineNanos: 1)
        cross.service.start()
        #expect(cross.service.state == "recoveryRequired" && cross.service.reason == "startupInspectionFailed")
        #expect(cross.calls.events.isEmpty)
    }

    @Test func clearAndIdleReleaseAreOneShotEvenWhenClearReturnsFailure() throws {
        let f = LidCalls()
        try f.mechanism.acquireIdle(remainingNanos: 30_000_000_000, episodeID: UUID())
        _ = try f.mechanism.suppressLidAfterJournalCommit()
        f.selectorCode = -1
        #expect(try !f.mechanism.clearLidAfterJournalCommit().allCallsSucceeded)
        #expect(throws: LidSpecificFailure.clearAlreadyAttempted) { try f.mechanism.clearLidAfterJournalCommit() }
        _ = try f.mechanism.releaseOwnedIdle()
        #expect(throws: NativePowerBoundaryFailure.releaseAlreadyAttempted) { try f.mechanism.releaseOwnedIdle() }
        #expect(throws: LidSpecificFailure.idleNotReady) { try f.mechanism.suppressLidAfterJournalCommit() }
    }
}
