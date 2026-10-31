import Testing

@testable import CamLidCore

private func makeTask(
    state: TaskState = .working,
    kind: EvidenceKind = .lifecycle,
    waitUntil: Double? = nil,
    unknownUntil: Double? = nil
) throws -> AgentTask {
    try AgentTask(
        id: "task-1", sessionID: "session-1", runID: "run-1",
        state: state, evidenceKind: kind, confidence: .exact,
        waitUntilMonotonic: waitUntil, unknownUntilMonotonic: unknownUntil
    )
}

private func makeSession(mode: RequestedMode = .auto, capAt: Double = 7_200) throws
    -> ProtectionSession
{
    try ProtectionSession(
        id: "session-1", requestedMode: mode, armedClosedLid: true,
        startedAtMonotonic: 0, capDeadlineMonotonic: capAt
    )
}

private func healthy() throws -> HealthSnapshot {
    try HealthSnapshot(
        batteryPercent: 80, powerSource: .ac, thermalPressure: .nominal,
        cpuPercent: 10, lidState: .open, internalDisplayState: .awake,
        capabilityVerified: true
    )
}

private func config() throws -> Configuration { try Configuration() }

@Suite("Policy hazards (T007)")
struct PolicyTests {
    @Test("auto arms on working lifecycle evidence")
    func autoArms() throws {
        var session = try makeSession()
        let decision = PolicyEngine.evaluate(
            session: session, tasks: [try makeTask()], health: try healthy(),
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: false, nowMonotonic: 10
        )
        #expect(decision.state == .protected)
        #expect(decision.session.stateRevision == 1)
        session = decision.session
        #expect(session.taskIDs == ["task-1"])
    }

    @Test("process-only discovery never arms auto")
    func processOnlyNoArm() throws {
        let decision = PolicyEngine.evaluate(
            session: try makeSession(), tasks: [try makeTask(kind: .process)],
            health: try healthy(), config: try config(), armed: true,
            safety: .clear, recoveryConflict: false, nowMonotonic: 10
        )
        #expect(decision.state == .ready)
        #expect(decision.reasons.contains("processOnlyNoArm"))
    }

    @Test("grace race: stop and fresh work in the same tick stays protected")
    func graceRace() throws {
        var session = try makeSession()
        var decision = PolicyEngine.evaluate(
            session: session, tasks: [try makeTask()], health: try healthy(),
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: false, nowMonotonic: 10
        )
        #expect(decision.state == .protected)
        session = decision.session
        // All work stops, then fresh work arrives before grace expiry.
        decision = PolicyEngine.evaluate(
            session: session, tasks: [], health: try healthy(),
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: false, nowMonotonic: 20
        )
        #expect(decision.state == .completionGrace)
        session = decision.session
        decision = PolicyEngine.evaluate(
            session: session, tasks: [try makeTask()], health: try healthy(),
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: false, nowMonotonic: 21
        )
        #expect(decision.state == .protected)
        #expect(decision.session.graceDeadlineMonotonic == nil)
    }

    @Test("lid-open completion releases grace to ready")
    func lidOpenCompletion() throws {
        var session = try makeSession()
        var decision = PolicyEngine.evaluate(
            session: session, tasks: [try makeTask()], health: try healthy(),
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: false, nowMonotonic: 10
        )
        session = decision.session
        decision = PolicyEngine.evaluate(
            session: session, tasks: [], health: try healthy(),
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: false, nowMonotonic: 20
        )
        #expect(decision.state == .completionGrace)
        session = decision.session
        // completionDelay default 2min -> grace ends at 140.
        decision = PolicyEngine.evaluate(
            session: session, tasks: [], health: try healthy(),
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: false, nowMonotonic: 200
        )
        #expect(decision.state == .ready)
        #expect(decision.reasons.contains("releaseComplete"))
    }

    @Test("lid-closed grace expiry requests sleep instead of release")
    func lidClosedSleepRequest() throws {
        var health = try healthy()
        var session = try makeSession()
        var decision = PolicyEngine.evaluate(
            session: session, tasks: [try makeTask()], health: health,
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: false, nowMonotonic: 10
        )
        session = decision.session
        decision = PolicyEngine.evaluate(
            session: session, tasks: [], health: health,
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: false, nowMonotonic: 20
        )
        session = decision.session
        health = try HealthSnapshot(
            batteryPercent: 80, powerSource: .ac, thermalPressure: .nominal,
            cpuPercent: 10, lidState: .closed, internalDisplayState: .asleep,
            capabilityVerified: true
        )
        decision = PolicyEngine.evaluate(
            session: session, tasks: [], health: health,
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: false, nowMonotonic: 200
        )
        #expect(decision.state == .ready)
        #expect(decision.reasons.contains("sleepRequested"))
    }

    @Test("cap expiry wins and never resets on fresh work")
    func capNotResetting() throws {
        var session = try makeSession(capAt: 100)
        var decision = PolicyEngine.evaluate(
            session: session, tasks: [try makeTask()], health: try healthy(),
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: false, nowMonotonic: 10
        )
        #expect(decision.state == .protected)
        session = decision.session
        let cap = session.capDeadlineMonotonic
        decision = PolicyEngine.evaluate(
            session: session, tasks: [try makeTask()], health: try healthy(),
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: false, nowMonotonic: 100
        )
        #expect(decision.state == .expired)
        #expect(decision.reasons.contains("capReached"))
        #expect(decision.session.capDeadlineMonotonic == cap)
        session = decision.session
        // Fresh work after expiry stays expired.
        decision = PolicyEngine.evaluate(
            session: session, tasks: [try makeTask()], health: try healthy(),
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: false, nowMonotonic: 101
        )
        #expect(decision.state == .expired)
        #expect(decision.reasons.contains("capReached"))
        #expect(decision.session.capDeadlineMonotonic == cap)
    }

    @Test("forward clock jump expires grace and cap like elapsed wall time")
    func clockJump() throws {
        var session = try makeSession(capAt: 1_000)
        var decision = PolicyEngine.evaluate(
            session: session, tasks: [try makeTask()], health: try healthy(),
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: false, nowMonotonic: 10
        )
        session = decision.session
        // Jump past grace (140) but before cap: enters grace, then releases.
        decision = PolicyEngine.evaluate(
            session: session, tasks: [], health: try healthy(),
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: false, nowMonotonic: 500
        )
        #expect(decision.state == .completionGrace)
        decision = PolicyEngine.evaluate(
            session: decision.session, tasks: [], health: try healthy(),
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: false, nowMonotonic: 700
        )
        #expect(decision.state == .ready)
        // Jump past cap: expired even with holding work.
        decision = PolicyEngine.evaluate(
            session: decision.session, tasks: [try makeTask()], health: try healthy(),
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: false, nowMonotonic: 5_000
        )
        #expect(decision.state == .expired)
    }

    @Test("unknown readings while nothing is held block holding without latching (wake, trial 8)")
    func unknownReadingsWhileReadyDoNotLatch() throws {
        let session = try makeSession()   // ready
        let unknown = SafetySignal(reasons: ["thermalUnknown", "lidUnknown"])
        var decision = PolicyEngine.evaluate(session: session, tasks: [try makeTask()], health: try healthy(),
            config: try config(), armed: true, safety: unknown, recoveryConflict: false, nowMonotonic: 10)
        #expect(decision.state == .ready && !decision.session.latchedSafetyStop)
        decision = PolicyEngine.evaluate(session: decision.session, tasks: [try makeTask()], health: try healthy(),
            config: try config(), armed: true, safety: .clear, recoveryConflict: false, nowMonotonic: 15)
        #expect(decision.state == .protected)
        // While held, unknown still stops and latches.
        decision = PolicyEngine.evaluate(session: decision.session, tasks: [try makeTask()], health: try healthy(),
            config: try config(), armed: true, safety: unknown, recoveryConflict: false, nowMonotonic: 20)
        #expect(decision.state == .safetyStopped && decision.session.latchedSafetyStop)
    }

    @Test("safety latches and requires explicit re-arm")
    func safetyLatchAndRearm() throws {
        var session = try makeSession()
        var decision = PolicyEngine.evaluate(
            session: session, tasks: [try makeTask()], health: try healthy(),
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: false, nowMonotonic: 10
        )
        session = decision.session
        decision = PolicyEngine.evaluate(
            session: session, tasks: [try makeTask()], health: try healthy(),
            config: try config(), armed: true,
            safety: SafetySignal(reasons: ["thermalSerious"]),
            recoveryConflict: false, nowMonotonic: 20
        )
        #expect(decision.state == .safetyStopped)
        session = decision.session
        // Hazard clears but holding work remains: latch holds.
        decision = PolicyEngine.evaluate(
            session: session, tasks: [try makeTask()], health: try healthy(),
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: false, nowMonotonic: 30
        )
        #expect(decision.state == .safetyStopped)
        #expect(decision.reasons.contains("safetyLatched"))
        // Only explicit re-arm leaves safetyStopped.
        session = PolicyEngine.rearm(decision.session)
        #expect(session.latchedSafetyStop == false)
        decision = PolicyEngine.evaluate(
            session: session, tasks: [try makeTask()], health: try healthy(),
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: false, nowMonotonic: 40
        )
        #expect(decision.state == .protected)
    }

    @Test("waiting never holds power, within or past its deadline")
    func waitingDeadline() throws {
        let session = try makeSession()
        let waiting = try makeTask(state: .waiting, waitUntil: 50)
        #expect(!PolicyEngine.holdsPower(waiting, now: 10))
        #expect(PolicyEngine.holdsSession(waiting, now: 10))
        #expect(!PolicyEngine.holdsSession(waiting, now: 60))
        var decision = PolicyEngine.evaluate(
            session: session, tasks: [waiting], health: try healthy(),
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: false, nowMonotonic: 10
        )
        #expect(decision.state != .protected)
        #expect(decision.session.taskIDs == Set(["task-1"]))
        decision = PolicyEngine.evaluate(
            session: decision.session, tasks: [waiting], health: try healthy(),
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: false, nowMonotonic: 60
        )
        #expect(decision.state != .protected)
    }

    @Test("unknown holds only through its bounded deadline and never extends cap")
    func unknownBounded() throws {
        let session = try makeSession(capAt: 1_000)
        let unknown = try makeTask(state: .unknown, unknownUntil: 50)
        var decision = PolicyEngine.evaluate(
            session: session, tasks: [unknown], health: try healthy(),
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: false, nowMonotonic: 10
        )
        #expect(decision.state == .protected)
        #expect(decision.session.capDeadlineMonotonic == 1_000)
        decision = PolicyEngine.evaluate(
            session: decision.session, tasks: [unknown], health: try healthy(),
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: false, nowMonotonic: 60
        )
        #expect(decision.state == .ready)
        #expect(decision.reasons.contains("workUncertain"))
        #expect(!decision.reasons.contains("sleepRequested"))
        var grace = try makeSession(capAt: 1_000)
        grace.effectiveState = .completionGrace
        grace.graceDeadlineMonotonic = 20
        let closed = try HealthSnapshot(batteryPercent: 80, powerSource: .ac, thermalPressure: .nominal,
            lidState: .closed, internalDisplayState: .asleep, capabilityVerified: true)
        decision = PolicyEngine.evaluate(session: grace, tasks: [], health: closed,
            config: try config(), armed: true, safety: .clear, recoveryConflict: false,
            completionUncertain: true, nowMonotonic: 60)
        #expect(decision.state == .ready && decision.session.graceDeadlineMonotonic == nil)
        #expect(!decision.reasons.contains("sleepRequested"))
    }

    @Test("recovery conflict becomes recoveryRequired")
    func recoveryConflict() throws {
        let decision = PolicyEngine.evaluate(
            session: try makeSession(), tasks: [try makeTask()], health: try healthy(),
            config: try config(), armed: true, safety: .clear,
            recoveryConflict: true, nowMonotonic: 10
        )
        #expect(decision.state == .recoveryRequired)
    }

    @Test("config patch validates atomically and rejects unknown keys")
    func configValidation() throws {
        let base = try Configuration()
        var patch = ConfigPatch()
        patch.completionDelayMinutes = 5
        patch.batteryFloorPercent = 60  // above 10...50
        do {
            _ = try base.applying(patch)
            Issue.record("expected out-of-range throw")
        } catch let error {
            #expect(error == .outOfRange(field: "batteryFloorPercent", value: 60, allowed: "10...50"))
        }
        do {
            _ = try ConfigPatch(jsonDictionary: ["noSuchKey": true])
            Issue.record("expected unknown-key throw")
        } catch let error {
            #expect(error == .unknownKeys(["noSuchKey"]))
        }
        // Failed patch leaves base untouched (atomicity).
        #expect(base.completionDelayMinutes == 2)
    }

    @Test("migration clamps bounds and never arms")
    func migrationNeverArms() throws {
        let migrated = try Configuration.migrate(from: [
            "mode": "auto",
            "closedLidOptIn": true,
            "runCapMinutes": 9_999,
            "batteryFloorPercent": 1,
        ])
        #expect(migrated.mode == .off)
        #expect(migrated.closedLidOptIn == false)
        #expect(migrated.runCapMinutes == 480)
        #expect(migrated.batteryFloorPercent == 10)
    }

    @Test("model bounds reject invalid IDs, strings and percents")
    func modelBounds() throws {
        do {
            _ = try AgentTask(
                id: "", sessionID: "s", runID: "r", state: .working,
                evidenceKind: .lifecycle, confidence: .exact
            )
            Issue.record("expected empty-ID throw")
        } catch {
            #expect(error == .emptyID)
        }
        do {
            _ = try HealthSnapshot(batteryPercent: 101)
            Issue.record("expected percent throw")
        } catch {
            #expect(error == .outOfRange(field: "batteryPercent", value: 101))
        }
    }

    @Test("lifetime holds only Auto and cannot outrank safety or cap")
    func lifetimeContribution() throws {
        let auto = try makeSession()
        var decision = PolicyEngine.evaluate(
            session: auto, tasks: [], health: try healthy(), config: try config(),
            armed: true, safety: .clear, recoveryConflict: false,
            lifetimeHoldReason: "lifetimeRuleActive", nowMonotonic: 10)
        #expect(decision.state == .protected)
        #expect(decision.reasons == ["lifetimeRuleActive"])

        decision = PolicyEngine.evaluate(
            session: decision.session, tasks: [], health: try healthy(), config: try config(),
            armed: true, safety: .clear, recoveryConflict: false,
            lifetimeCompletionSuppressed: true, nowMonotonic: 20)
        #expect(decision.state == .ready)
        #expect(decision.reasons.contains("lifetimeEpochUnconfirmed"))
        #expect(decision.session.graceDeadlineMonotonic == nil)

        let timed = try makeSession(mode: .timed)
        decision = PolicyEngine.evaluate(
            session: timed, tasks: [], health: try healthy(), config: try config(),
            armed: true, safety: .clear, recoveryConflict: false,
            lifetimeHoldReason: "lifetimeRuleActive", nowMonotonic: 10)
        #expect(decision.state == .protected)
        #expect(decision.reasons == ["requestedProtection"])

        let expired = try makeSession(capAt: 10)
        decision = PolicyEngine.evaluate(
            session: expired, tasks: [], health: try healthy(), config: try config(),
            armed: true, safety: .clear, recoveryConflict: false,
            lifetimeHoldReason: "lifetimeRuleActive", nowMonotonic: 10)
        #expect(decision.state == .expired)
        #expect(decision.reasons == ["capReached"])

        decision = PolicyEngine.evaluate(
            session: auto, tasks: [], health: try healthy(), config: try config(),
            armed: true, safety: SafetySignal(reasons: ["thermalSerious"]),
            recoveryConflict: false, lifetimeHoldReason: "lifetimeRuleActive", nowMonotonic: 10)
        #expect(decision.state == .safetyStopped)
        #expect(decision.reasons == ["thermalSerious"])
    }
}
