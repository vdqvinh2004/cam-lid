import Testing
@testable import CamLidCore
@Suite("Explicit sleep admission") struct SleepDecisionTests {
    @Test func staleUnknownWorkInteractionAndBackendBlockTogether() {
        let decision = GuardedSleepDecision.evaluate(now: 100, observedAt: 90, lid: .unknown,
            displaysObservedAt: 100, displays: .unknown, inputObservedAt: 100,
            idleSeconds: nil, workActive: true, workUnknown: true, restore: .unknown, backendVerified: false)
        #expect(!decision.eligible)
        #expect(Set(decision.blockers) == ["telemetryStale", "displayUnknown", "inputUnknown", "trackedWorkActive", "workUnknown", "restorationUnverified", "backendUnverified"])
    }
    @Test func freshClosedLidIsInsufficientWithRecentInputOrWork() {
        let allowed = GuardedSleepDecision.evaluate(now: 100, observedAt: 100, lid: .closed,
            displaysObservedAt: 100, displays: .unknown, inputObservedAt: 100,
            idleSeconds: 60, workActive: false, workUnknown: false, restore: .verified, backendVerified: true)
        #expect(allowed.eligible && allowed.outcome == "notRequested")
        let blocked = GuardedSleepDecision.evaluate(now: 100, observedAt: 100, lid: .closed,
            displaysObservedAt: 100, displays: .asleep, inputObservedAt: 100,
            idleSeconds: 59, workActive: false, workUnknown: false, restore: .verified, backendVerified: true)
        #expect(!blocked.eligible && blocked.blockers == ["inUse"])
    }

    @Test func requiresFreshTelemetryAndOneSafeLidOrDisplayPath() {
        let closed = evaluate(observedAt: 95, lid: .closed, displays: .unknown, idle: 60)
        #expect(closed.eligible && closed.outcome == "notRequested")

        let displayAsleep = evaluate(observedAt: 95, lid: .open, displays: .asleep, idle: 60)
        #expect(displayAsleep.eligible)
        #expect(evaluate(observedAt: 94.999, lid: .closed, displays: .unknown, idle: 60).blockers.contains("telemetryStale"))
        #expect(evaluate(observedAt: 101, lid: .closed, displays: .unknown, idle: 60).blockers.contains("telemetryStale"))
        #expect(evaluate(observedAt: 95, lid: .open, displays: .awake, idle: 60).blockers == ["displayAwake"])
        #expect(evaluate(observedAt: 95, lid: .open, displays: .unknown, idle: 60).blockers == ["displayUnknown"])
    }

    @Test func recentOrUnknownInputAndAnyWorkBlockAdmission() {
        #expect(evaluate(observedAt: 100, lid: .closed, displays: .unknown, idle: 59).blockers == ["inUse"])
        #expect(evaluate(observedAt: 100, lid: .closed, displays: .unknown, idle: nil).blockers == ["inputUnknown"])
        #expect(evaluate(observedAt: 100, lid: .closed, displays: .unknown, idle: .nan).blockers == ["inputUnknown"])

        let active = evaluate(observedAt: 100, lid: .closed, displays: .unknown, idle: 60, workActive: true)
        let unknown = evaluate(observedAt: 100, lid: .closed, displays: .unknown, idle: 60, workUnknown: true)
        #expect(active.blockers == ["trackedWorkActive"])
        #expect(unknown.blockers == ["workUnknown"])
    }

    @Test func displayAndInputSamplesMustBothBeFresh() {
        #expect(evaluate(observedAt: 100, lid: .closed, displays: .unknown, idle: 60,
            displayAt: 94.999).blockers == ["displayStale"])
        #expect(evaluate(observedAt: 100, lid: .closed, displays: .unknown, idle: 60,
            inputAt: 94.999).blockers == ["inputStale"])
        #expect(evaluate(observedAt: 100, lid: .closed, displays: .unknown, idle: 60,
            displayAt: 95, inputAt: 95).eligible)
    }

    @Test func restorationAndBackendBlockOtherwiseEligibleRequest() {
        for restore in [RestoreState.pending, .unknown, .failed, .conflict] {
            #expect(evaluate(observedAt: 100, lid: .closed, displays: .unknown, idle: 60,
                restore: restore).blockers == ["restorationUnverified"])
        }
        #expect(evaluate(observedAt: 100, lid: .closed, displays: .unknown, idle: 60,
            backendVerified: false).blockers == ["backendUnverified"])
    }

    private func evaluate(
        observedAt: Double, lid: LidState, displays: DisplayState, idle: Double?,
        displayAt: Double = 100, inputAt: Double = 100,
        workActive: Bool = false, workUnknown: Bool = false,
        restore: RestoreState = .verified, backendVerified: Bool = true
    ) -> GuardedSleepDecision {
        GuardedSleepDecision.evaluate(now: 100, observedAt: observedAt, lid: lid,
            displaysObservedAt: displayAt, displays: displays, inputObservedAt: inputAt,
            idleSeconds: idle, workActive: workActive,
            workUnknown: workUnknown, restore: restore, backendVerified: backendVerified)
    }
}
