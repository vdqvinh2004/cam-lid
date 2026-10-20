import Foundation
import Testing

@testable import CamLidCore

private func auditHealth(thermal: ThermalPressure = .nominal) throws -> HealthSnapshot {
    try HealthSnapshot(
        batteryPercent: 80, powerSource: .ac, thermalPressure: thermal,
        cpuPercent: 10, lidState: .open, internalDisplayState: .awake,
        capabilityVerified: true
    )
}

private func auditSession(mode: RequestedMode, capAt: Double = 7_200) throws
    -> ProtectionSession
{
    try ProtectionSession(
        id: "audit-session", requestedMode: mode, armedClosedLid: true,
        startedAtMonotonic: 0, capDeadlineMonotonic: capAt
    )
}

@Suite("Audit F05: critical thermal bypasses the sampling cache")
struct AuditSafetyCacheTests {
    @Test("nominal at t=0 then critical at t=1 stops")
    func nominalThenCriticalStops() throws {
        var policy = SafetyPolicy()
        let clear = policy.evaluate(
            health: try auditHealth(thermal: .nominal), config: try Configuration(),
            cpuStop: false, now: 0
        )
        #expect(clear == .clear)
        let stop = policy.evaluate(
            health: try auditHealth(thermal: .critical), config: try Configuration(),
            cpuStop: false, now: 1
        )
        #expect(stop.reasons.contains("thermalCritical"))
    }

    @Test("critical simultaneous with a cached clear still stops")
    func criticalSimultaneousWithCachedClear() throws {
        var policy = SafetyPolicy()
        let clear = policy.evaluate(
            health: try auditHealth(thermal: .nominal), config: try Configuration(),
            cpuStop: false, now: 100
        )
        #expect(clear == .clear)
        // Same timestamp: inside the 5s throttle window, yet critical bypasses it.
        let stop = policy.evaluate(
            health: try auditHealth(thermal: .critical), config: try Configuration(),
            cpuStop: false, now: 100
        )
        #expect(stop.reasons.contains("thermalCritical"))
        // The bypass refreshed the cache, so a fresh nominal inside the window
        // still observes the stop rather than a stale clear.
        let stillStopped = policy.evaluate(
            health: try auditHealth(thermal: .nominal), config: try Configuration(),
            cpuStop: false, now: 101
        )
        #expect(stillStopped.reasons.contains("thermalCritical"))
    }

    @Test("non-critical inputs within 5s are still cached")
    func nonCriticalStillCached() throws {
        var policy = SafetyPolicy()
        #expect(
            policy.evaluate(
                health: try auditHealth(thermal: .nominal), config: try Configuration(),
                cpuStop: false, now: 0) == .clear)
        // An unknown thermal reading would stop if evaluated, but the throttle
        // must keep returning the cached clear signal.
        #expect(
            policy.evaluate(
                health: try auditHealth(thermal: .unknown), config: try Configuration(),
                cpuStop: false, now: 1) == .clear)
        // Past the 5s window the same reading evaluates for real.
        let fresh = policy.evaluate(
            health: try auditHealth(thermal: .unknown), config: try Configuration(),
            cpuStop: false, now: 6
        )
        #expect(fresh.reasons.contains("thermalUnknown"))
    }
}

@Suite("Audit F10: timed/manual requested protection without tasks")
struct AuditRequestedProtectionTests {
    @Test("armed timed session with no tasks stays protected")
    func timedEmptyStaysProtected() throws {
        let decision = PolicyEngine.evaluate(
            session: try auditSession(mode: .timed), tasks: [],
            health: try auditHealth(), config: try Configuration(), armed: true,
            safety: .clear, recoveryConflict: false, nowMonotonic: 10
        )
        #expect(decision.state == .protected)
        #expect(decision.reasons.contains("requestedProtection"))
    }

    @Test("armed manual session with no tasks stays protected")
    func manualEmptyStaysProtected() throws {
        let decision = PolicyEngine.evaluate(
            session: try auditSession(mode: .manual), tasks: [],
            health: try auditHealth(), config: try Configuration(), armed: true,
            safety: .clear, recoveryConflict: false, nowMonotonic: 10
        )
        #expect(decision.state == .protected)
        #expect(decision.reasons.contains("requestedProtection"))
    }

    @Test("timed expiry still fires via the cap with no tasks")
    func timedExpiryViaCap() throws {
        let decision = PolicyEngine.evaluate(
            session: try auditSession(mode: .timed, capAt: 100), tasks: [],
            health: try auditHealth(), config: try Configuration(), armed: true,
            safety: .clear, recoveryConflict: false, nowMonotonic: 100
        )
        #expect(decision.state == .expired)
        #expect(decision.reasons.contains("capReached"))
    }

    @Test("auto with no tasks stays ready")
    func autoEmptyStaysReady() throws {
        let decision = PolicyEngine.evaluate(
            session: try auditSession(mode: .auto), tasks: [],
            health: try auditHealth(), config: try Configuration(), armed: true,
            safety: .clear, recoveryConflict: false, nowMonotonic: 10
        )
        #expect(decision.state == .ready)
    }

    @Test("safety still overrides empty timed and manual sessions")
    func safetyOverridesRequestedProtection() throws {
        for mode in [RequestedMode.timed, RequestedMode.manual] {
            let decision = PolicyEngine.evaluate(
                session: try auditSession(mode: mode), tasks: [],
                health: try auditHealth(), config: try Configuration(), armed: true,
                safety: SafetySignal(reasons: ["thermalCritical"]),
                recoveryConflict: false, nowMonotonic: 10
            )
            #expect(decision.state == .safetyStopped)
        }
    }

    @Test("disarmed timed session with no tasks stays ready")
    func disarmedTimedEmptyStaysReady() throws {
        let decision = PolicyEngine.evaluate(
            session: try auditSession(mode: .timed), tasks: [],
            health: try auditHealth(), config: try Configuration(), armed: false,
            safety: .clear, recoveryConflict: false, nowMonotonic: 10
        )
        #expect(decision.state == .ready)
    }

    @Test("recovery conflict still outranks empty timed protection")
    func recoveryConflictOutranksRequestedProtection() throws {
        let decision = PolicyEngine.evaluate(
            session: try auditSession(mode: .timed), tasks: [],
            health: try auditHealth(), config: try Configuration(), armed: true,
            safety: .clear, recoveryConflict: true, nowMonotonic: 10
        )
        #expect(decision.state == .recoveryRequired)
    }
}

@Suite("Audit F11 core: decoding and patch-type validation")
struct AuditDecodeValidationTests {
    @Test("HealthSnapshot JSON with out-of-range battery throws")
    func healthSnapshotJSONValidation() throws {
        let bad = """
            {"batteryPercent":101,"powerSource":"ac","thermalPressure":"nominal",\
            "cpuPercent":10,"lidState":"open","internalDisplayState":"awake",\
            "capabilityVerified":true}
            """.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(HealthSnapshot.self, from: bad)
        }
        // Valid payloads still decode.
        let good = """
            {"batteryPercent":80,"powerSource":"ac","thermalPressure":"nominal",\
            "cpuPercent":10,"lidState":"open","internalDisplayState":"awake",\
            "capabilityVerified":true}
            """.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(HealthSnapshot.self, from: good)
        #expect(snapshot.batteryPercent == 80)
    }

    @Test("AgentTask JSON with an empty ID throws")
    func agentTaskJSONValidation() throws {
        let bad = """
            {"id":"","sessionID":"s","runID":"r","state":"working",\
            "evidenceKind":"lifecycle","confidence":"exact"}
            """.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AgentTask.self, from: bad)
        }
    }

    @Test("ProtectionSession JSON with an empty ID throws")
    func protectionSessionJSONValidation() throws {
        let bad = """
            {"id":"","requestedMode":"auto","effectiveState":"ready",\
            "armedClosedLid":true,"taskIDs":[],"startedAtMonotonic":0,\
            "capDeadlineMonotonic":7200,"latchedSafetyStop":false,\
            "stopReasons":[],"stateRevision":0}
            """.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ProtectionSession.self, from: bad)
        }
    }

    @Test("validated models round-trip through JSON unchanged")
    func validatedModelsRoundTrip() throws {
        let task = try AgentTask(
            id: "t", sessionID: "s", runID: "r", state: .working,
            evidenceKind: .lifecycle, confidence: .exact
        )
        #expect(try JSONDecoder().decode(AgentTask.self, from: JSONEncoder().encode(task)) == task)
        let health = try auditHealth()
        #expect(
            try JSONDecoder().decode(
                HealthSnapshot.self, from: JSONEncoder().encode(health)) == health)
        let session = try auditSession(mode: .timed)
        #expect(
            try JSONDecoder().decode(
                ProtectionSession.self, from: JSONEncoder().encode(session)) == session)
    }

    @Test("batteryFloorPercent=0 from JSON fails validation")
    func batteryFloorZeroRejected() throws {
        // End to end through the dictionary ingress path: the patch carries the
        // value, and atomic application rejects it against the 10...50 range.
        let patch = try ConfigPatch(jsonDictionary: ["batteryFloorPercent": 0])
        do {
            _ = try Configuration().applying(patch)
            Issue.record("expected out-of-range throw for batteryFloorPercent=0")
        } catch let error {
            #expect(
                error == .outOfRange(
                    field: "batteryFloorPercent", value: 0, allowed: "10...50"))
        }
        // The same holds for a JSON-decoded Configuration: decoding succeeds
        // (synthesis is unchanged) but validation rejects the payload.
        let payload = """
            {"mode":"off","closedLidOptIn":false,"completionDelayMinutes":2,\
            "waitRetentionMinutes":5,"batteryFloorPercent":0,"chargingOnly":true,\
            "runCapMinutes":120,"cpuStopEnabled":false,"adapterEnrollment":[],\
            "launchAtLogin":false,"telemetryEnabled":false}
            """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Configuration.self, from: payload)
        do {
            try decoded.validate()
            Issue.record("expected validate() to reject batteryFloorPercent=0")
        } catch let error {
            #expect(
                error == .outOfRange(
                    field: "batteryFloorPercent", value: 0, allowed: "10...50"))
        }
    }

    @Test("patch with a wrong-typed known key throws invalidType")
    func patchWrongTypesRejected() throws {
        let cases: [(String, Any)] = [
            ("batteryFloorPercent", "high"),
            ("runCapMinutes", true),
            ("chargingOnly", "yes"),
            ("mode", 7),
            ("adapterEnrollment", "opencode"),
        ]
        for (key, value) in cases {
            do {
                _ = try ConfigPatch(jsonDictionary: [key: value])
                Issue.record("expected invalidType throw for \(key)")
            } catch let error {
                #expect(error == .invalidType(key: key))
            }
        }
    }

    @Test("patch with null for a known key throws invalidType")
    func patchNullRejected() throws {
        for key in ["chargingOnly", "batteryFloorPercent", "mode", "adapterEnrollment"] {
            do {
                _ = try ConfigPatch(jsonDictionary: [key: NSNull()])
                Issue.record("expected invalidType throw for null \(key)")
            } catch let error {
                #expect(error == .invalidType(key: key))
            }
        }
    }

    @Test("valid and unknown-key patch behavior is unchanged")
    func patchValidAndUnknownKeys() throws {
        let base = try Configuration()
        let patch = try ConfigPatch(
            jsonDictionary: ["closedLidOptIn": true, "runCapMinutes": 60])
        let next = try base.applying(patch)
        #expect(next.closedLidOptIn == true)
        #expect(next.runCapMinutes == 60)
        do {
            _ = try ConfigPatch(jsonDictionary: ["noSuchKey": true])
            Issue.record("expected unknown-key throw")
        } catch let error {
            #expect(error == .unknownKeys(["noSuchKey"]))
        }
    }
}
