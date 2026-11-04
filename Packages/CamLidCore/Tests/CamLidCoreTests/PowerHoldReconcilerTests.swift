import Foundation
import Testing
@testable import CamLidCore

@Suite struct PowerHoldReconcilerTests {
    private let token = UUID()
    private func held(at now: Double = 100) -> PowerHoldReconciler {
        var r = PowerHoldReconciler()
        _ = r.next(desired: true, remainingSessionSeconds: 600, now: now)
        r.received(HoldReply(accepted: true, state: "active", reason: "leaseAcquired", token: token), now: now)
        return r
    }

    @Test func nothingDesiredDoesNothing() {
        var r = PowerHoldReconciler()
        #expect(r.next(desired: false, remainingSessionSeconds: 600, now: 0) == nil)
        #expect(r.status == .inactive && r.restoration == .verified)
    }

    @Test func acquireClampsToTheFourHourMaximumAndNeedsEnoughTime() {
        var r = PowerHoldReconciler()
        #expect(r.next(desired: true, remainingSessionSeconds: 2, now: 0) == nil)
        #expect(r.next(desired: true, remainingSessionSeconds: 99 * 3600, now: 0) == .acquire(sessionSeconds: 4 * 3600))
        #expect(r.status == .acquiring && r.restoration == .pending)
    }

    @Test func oneCallAtATime() {
        var r = PowerHoldReconciler()
        _ = r.next(desired: true, remainingSessionSeconds: 600, now: 0)
        #expect(r.next(desired: true, remainingSessionSeconds: 600, now: 1) == nil)
    }

    @Test func heldLeaseRenewsEveryTenSecondsWithIncreasingSequence() {
        var r = held()
        #expect(r.next(desired: true, remainingSessionSeconds: 500, now: 105) == nil)
        #expect(r.next(desired: true, remainingSessionSeconds: 500, now: 110) == .renew(token: token, sequence: 2))
        r.received(HoldReply(accepted: true, state: "active", reason: "leaseRenewed", token: token), now: 110)
        #expect(r.leaseVerified(now: 111))
        #expect(r.next(desired: true, remainingSessionSeconds: 500, now: 120) == .renew(token: token, sequence: 3))
    }

    @Test func leaseIsVerifiedOnlyWithinTheLeaseWindow() {
        let r = held()
        #expect(r.leaseVerified(now: 129) && !r.leaseVerified(now: 130))
        #expect(!PowerHoldReconciler().leaseVerified(now: 0))
    }

    @Test func silenceForALeaseWindowMarksTheLeaseLostAndNeverRetriesIt() {
        var r = held()
        _ = r.next(desired: true, remainingSessionSeconds: 500, now: 110)
        r.failed(now: 111)
        #expect(r.next(desired: true, remainingSessionSeconds: 500, now: 131) == nil)
        #expect(r.status == .lost && r.restoration == .unknown)
        #expect(r.stopReasons == ["helperLeaseLost"])
        #expect(r.next(desired: true, remainingSessionSeconds: 500, now: 200) == nil)
        #expect(r.next(desired: false, remainingSessionSeconds: nil, now: 201) == nil)
        #expect(r.status == .inactive)
    }

    @Test func aRefusedRenewalIsAStopNotAReasonToRetry() {
        var r = held()
        _ = r.next(desired: true, remainingSessionSeconds: 500, now: 110)
        r.received(HoldReply(accepted: false, state: "restored", reason: "renewalRefused"), now: 110)
        #expect(r.status == .refused("renewalRefused") && r.restoration == .verified)
        #expect(r.stopReasons == ["helper:renewalRefused"])
        #expect(r.next(desired: true, remainingSessionSeconds: 500, now: 120) == nil)
        #expect(r.next(desired: false, remainingSessionSeconds: nil, now: 121) == nil)
        #expect(r.next(desired: true, remainingSessionSeconds: 500, now: 130) != nil)   // fresh episode
    }

    @Test func aForeignPolicyOrFailedRestoreMapsToConflictOrFailure() {
        var a = held()
        _ = a.next(desired: true, remainingSessionSeconds: 500, now: 110)
        a.received(HoldReply(accepted: false, state: "recoveryRequired", reason: "foreignGlobalSleepDisabled"), now: 110)
        #expect(a.restoration == .conflict)
        var b = held()
        _ = b.next(desired: true, remainingSessionSeconds: 500, now: 110)
        b.received(HoldReply(accepted: false, state: "recoveryRequired", reason: "restorationFailed"), now: 110)
        #expect(b.restoration == .failed)
    }

    @Test func refusedAcquireIsNotRetriedUntilTheDesireEnds() {
        var r = PowerHoldReconciler()
        _ = r.next(desired: true, remainingSessionSeconds: 600, now: 0)
        r.received(HoldReply(accepted: false, state: "ready", reason: "safetyRefused"), now: 0)
        #expect(r.status == .refused("safetyRefused") && r.restoration == .verified)
        #expect(r.next(desired: true, remainingSessionSeconds: 600, now: 50) == nil)
    }

    @Test func unreachableHelperAtAcquireRetriesAfterTheInterval() {
        var r = PowerHoldReconciler()
        _ = r.next(desired: true, remainingSessionSeconds: 600, now: 0)
        r.failed(now: 0)
        #expect(r.unavailableReason == "helperUnavailable" && r.status == .inactive)
        #expect(r.next(desired: true, remainingSessionSeconds: 600, now: 5) == nil)
        #expect(r.next(desired: true, remainingSessionSeconds: 600, now: 10) == .acquire(sessionSeconds: 600))
    }

    @Test func releaseRunsWhenTheDesireEndsAndRestoresOnlyOnVerifiedReply() {
        var r = held()
        #expect(r.next(desired: false, remainingSessionSeconds: nil, now: 105) == .release(token: token))
        #expect(r.status == .releasing && r.restoration == .pending)
        r.received(HoldReply(accepted: true, state: "restored", reason: "restorationVerified"), now: 105)
        #expect(r.status == .inactive && r.restoration == .verified)
    }

    @Test func aReleaseAfterTheHelperAlreadyStoppedTheLeaseIsVerified() {
        var r = held()
        _ = r.next(desired: false, remainingSessionSeconds: nil, now: 105)
        r.received(HoldReply(accepted: false, state: "restored", reason: "invalidLease"), now: 105)
        #expect(r.status == .inactive && r.restoration == .verified)
        #expect(r.stopReasons.isEmpty)
        #expect(r.next(desired: false, remainingSessionSeconds: nil, now: 110) == nil)
    }

    @Test func anInvalidLeaseWhileTheHelperIsStillActiveIsStillAFailure() {
        var r = held()
        _ = r.next(desired: false, remainingSessionSeconds: nil, now: 105)
        r.received(HoldReply(accepted: false, state: "active", reason: "invalidLease"), now: 105)
        #expect(r.status == .releaseFailed("invalidLease") && r.restoration == .failed)
    }

    @Test func aFailedReleaseIsRetriedAndNeverReportedRestored() {
        var r = held()
        _ = r.next(desired: false, remainingSessionSeconds: nil, now: 105)
        r.received(HoldReply(accepted: false, state: "recoveryRequired", reason: "restorationFailed"), now: 105)
        #expect(r.status == .releaseFailed("restorationFailed") && r.restoration == .failed)
        #expect(r.stopReasons == ["helperReleaseFailed"])
        #expect(r.next(desired: false, remainingSessionSeconds: nil, now: 107) == nil)
        #expect(r.next(desired: false, remainingSessionSeconds: nil, now: 110) == .release(token: token))
        r.failed(now: 110)
        #expect(r.status == .releaseFailed("helperUnavailable") && r.restoration == .failed)
    }

    @Test func nonFiniteTimeIsIgnored() {
        var r = PowerHoldReconciler()
        #expect(r.next(desired: true, remainingSessionSeconds: 600, now: .nan) == nil)
    }
}
