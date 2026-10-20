import Foundation
import Testing

@testable import CamLidCore

private func snapshot(
    battery: Double? = 80, power: PowerSource = .ac,
    thermal: ThermalPressure = .nominal, lid: LidState = .open
) throws -> HealthSnapshot {
    try HealthSnapshot(
        batteryPercent: battery, powerSource: power, thermalPressure: thermal,
        cpuPercent: 10, lidState: lid, internalDisplayState: .awake,
        capabilityVerified: true
    )
}

@Suite("Safety and capacity (T013, T014)")
struct SafetyTests {
    @Test("battery preference takes effect without waiting for the sample cache")
    func batteryPreferenceAppliesImmediately() throws {
        var policy = SafetyPolicy()
        let health = try snapshot(battery: 60, power: .battery)
        let blocked = policy.evaluate(health: health, config: try Configuration(), cpuStop: false, now: 100)
        #expect(blocked.reasons.contains("notCharging"))
        let allowed = policy.evaluate(health: health, config: try Configuration(chargingOnly: false, batteryModeAllowed: true), cpuStop: false, now: 101)
        #expect(allowed == .clear)
        let required = policy.evaluate(health: health, config: try Configuration(), cpuStop: false, now: 102)
        #expect(required.reasons.contains("notCharging"))
        let lowBattery = policy.evaluate(health: try snapshot(battery: 10, power: .battery),
            config: try Configuration(chargingOnly: false), cpuStop: false, now: 108)
        #expect(lowBattery.reasons.contains("batteryFloor"))
    }
    @Test("critical thermal stops immediately")
    func criticalImmediate() throws {
        var policy = SafetyPolicy()
        let signal = policy.evaluate(
            health: try snapshot(thermal: .critical), config: try Configuration(),
            cpuStop: false, now: 100
        )
        #expect(signal.reasons.contains("thermalCritical"))
    }

    @Test("serious thermal stops only after 30s sustained")
    func seriousSustained() throws {
        var policy = SafetyPolicy()
        var signal = policy.evaluate(
            health: try snapshot(thermal: .serious), config: try Configuration(),
            cpuStop: false, now: 100
        )
        #expect(!signal.reasons.contains("thermalSerious"))
        signal = policy.evaluate(
            health: try snapshot(thermal: .serious), config: try Configuration(),
            cpuStop: false, now: 125
        )
        #expect(!signal.reasons.contains("thermalSerious"))
        signal = policy.evaluate(
            health: try snapshot(thermal: .serious), config: try Configuration(),
            cpuStop: false, now: 130
        )
        #expect(signal.reasons.contains("thermalSerious"))
    }

    @Test("unknown safety inputs stop with specific reasons")
    func unknownStops() throws {
        var policy = SafetyPolicy()
        let signal = policy.evaluate(
            health: try HealthSnapshot(), config: try Configuration(),
            cpuStop: false, now: 100
        )
        #expect(signal.reasons.contains("thermalUnknown"))
        #expect(signal.reasons.contains("lidUnknown"))
        #expect(signal.reasons.contains("powerUnknown"))
    }

    @Test("battery floor and AC cutoff stop; AC with charge passes")
    func batteryAndAC() throws {
        var policy = SafetyPolicy()
        var signal = policy.evaluate(
            health: try snapshot(battery: 10), config: try Configuration(),
            cpuStop: false, now: 100
        )
        #expect(signal.reasons.contains("batteryFloor"))
        signal = policy.evaluate(
            health: try snapshot(battery: 80, power: .battery),
            config: try Configuration(), cpuStop: false, now: 200
        )
        #expect(signal.reasons.contains("notCharging"))
        signal = policy.evaluate(
            health: try snapshot(), config: try Configuration(),
            cpuStop: false, now: 300
        )
        #expect(signal == .clear)
    }

    @Test("stale readings surface as unknown and stop")
    func staleStops() throws {
        let monitor = HealthMonitor()
        let readings = SensorReadings(
            batteryPercent: 80, powerSource: .ac, thermalPressure: .nominal,
            cpuPercent: 10, lidState: .open, internalDisplayState: .awake,
            measuredAtMonotonic: 0
        )
        let (snapshot, issues) = monitor.snapshot(from: readings, now: 100)
        #expect(issues.contains("staleTelemetry"))
        #expect(snapshot.thermalPressure == .unknown)
        var policy = SafetyPolicy()
        let signal = policy.evaluate(
            health: snapshot, config: try Configuration(), cpuStop: false, now: 100
        )
        #expect(signal.reasons.contains("thermalUnknown"))
    }

    @Test("safety overrides an engaged protected session")
    func safetyOverridesModes() throws {
        let session = try ProtectionSession(
            id: "s", requestedMode: .auto, armedClosedLid: true,
            startedAtMonotonic: 0, capDeadlineMonotonic: 7_200
        )
        let task = try AgentTask(
            id: "t", sessionID: "s", runID: "r", state: .working,
            evidenceKind: .lifecycle, confidence: .exact
        )
        let decision = PolicyEngine.evaluate(
            session: session, tasks: [task], health: try snapshot(),
            config: try Configuration(), armed: true,
            safety: SafetySignal(reasons: ["thermalCritical"]),
            recoveryConflict: false, nowMonotonic: 10
        )
        #expect(decision.state == .safetyStopped)
    }

    @Test("boundary battery at exactly the floor passes")
    func floorBoundary() throws {
        var policy = SafetyPolicy()
        let signal = policy.evaluate(
            health: try snapshot(battery: 20), config: try Configuration(),
            cpuStop: false, now: 100
        )
        #expect(signal == .clear)
    }

    @Test("missing battery on AC passes; missing battery off AC stops")
    func missingBattery() throws {
        var policy = SafetyPolicy()
        var signal = policy.evaluate(
            health: try snapshot(battery: nil, power: .ac),
            config: try Configuration(), cpuStop: false, now: 100
        )
        #expect(signal == .clear)
        signal = policy.evaluate(
            health: try snapshot(battery: nil, power: .battery),
            config: try Configuration(), cpuStop: false, now: 200
        )
        #expect(signal.reasons.contains("batteryUnknown"))
    }
}

@Suite("Capacity (T014)")
struct CapacityTests {
    @Test("enrollment rejects past 20 and preserves existing work")
    func enrollmentLimit() throws {
        var set = EnrollmentSet()
        for index in 0..<20 { try set.enroll("task-\(index)") }
        do {
            try set.enroll("task-20")
            Issue.record("expected over-limit throw")
        } catch let error {
            #expect(error == .overLimit(limit: 20, active: 20))
        }
        #expect(set.count == 20)
        #expect(set.ids.first == "task-0")
        // Re-enrollment is idempotent, release frees exactly one slot.
        try set.enroll("task-0")
        #expect(set.count == 20)
        set.release("task-0")
        try set.enroll("task-20")
        #expect(set.count == 20)
        #expect(!set.ids.contains("task-0"))
    }

    @Test("payload bound rejects oversized events")
    func payloadBound() throws {
        let ok = Data(repeating: 0, count: PolicyLimits.maxEventBytes)
        #expect(throws: Never.self) { try BoundedPayload(ok) }
        do {
            _ = try BoundedPayload(Data(repeating: 0, count: PolicyLimits.maxEventBytes + 1))
            Issue.record("expected too-large throw")
        } catch let error {
            #expect(error == .tooLarge(PolicyLimits.maxEventBytes + 1))
        }
    }

    @Test("read-only storage fails closed without partial mutation")
    func storageFailureClosed() throws {
        var journal = RecoveryJournal(capacity: 4, writable: false)
        let record = try RecoveryRecord(
            journalRevision: 1, sessionID: "s", ownerIdentity: "uid501",
            originalState: ["sleep": "1"], expectedState: ["sleep": "1"]
        )
        do {
            try journal.commit(record)
            Issue.record("expected read-only throw")
        } catch {
            #expect(error == .readOnly)
        }
        #expect(journal.count == 0)
    }
    @Test("waiting holds supervision but never holds power")
    func waitingNeverHoldsPower() throws {
        func task(_ state: TaskState, wait: Double? = nil) throws -> AgentTask {
            try AgentTask(id: "t", sessionID: "s", runID: "r", state: state,
                evidenceKind: .lifecycle, confidence: .exact,
                waitUntilMonotonic: wait, unknownUntilMonotonic: wait)
        }
        #expect(PolicyEngine.holdsPower(try task(.working), now: 10))
        #expect(!PolicyEngine.holdsPower(try task(.waiting, wait: 100), now: 10))
        #expect(!PolicyEngine.holdsPower(try task(.idle), now: 10))
        #expect(PolicyEngine.holdsSession(try task(.waiting, wait: 100), now: 10))
        let session = try ProtectionSession(
            id: "s", requestedMode: .auto, armedClosedLid: true,
            startedAtMonotonic: 0, capDeadlineMonotonic: 7_200
        )
        func decide(_ tasks: [AgentTask]) throws -> PolicyDecision {
            PolicyEngine.evaluate(session: session, tasks: tasks, health: try snapshot(),
                config: try Configuration(), armed: true,
                safety: SafetySignal(reasons: []), recoveryConflict: false, nowMonotonic: 10)
        }
        let waitingOnly = try decide([try task(.waiting, wait: 100)])
        #expect(waitingOnly.state != .protected)
        #expect(waitingOnly.session.taskIDs == Set(["t"]))
        #expect(try decide([try task(.working)]).state == .protected)
    }
}