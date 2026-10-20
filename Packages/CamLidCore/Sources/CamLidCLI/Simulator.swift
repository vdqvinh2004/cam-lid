import Foundation
import CamLidCore

/// Isolated fake clock/sensors/power simulator (T006).
///
/// No real-power API by construction: this file imports only Foundation and
/// CamLidCore, never IOKit, ServiceManagement, and never shells out to
/// `pmset`/`caffeinate`. All time comes from `fakeNow + step.at`, all sensors
/// from scripted values, all power effects from `PolicyEngine`
/// decisions. `simulate` and every dry-run path in this target are pure: they
/// cannot mutate host power state because they hold no handle to it.
public struct Simulator: Sendable {
    /// Fake monotonic origin. Step times are offsets from this clock.
    public var fakeNow: Double

    public init(fakeNow: Double = 0) {
        self.fakeNow = fakeNow
    }

    /// Drives PolicyEngine + SafetyPolicy + CPUObserver + HealthMonitor
    /// deterministically over the scenario steps (sorted by `at`).
    /// Unspecified sensor fields default to healthy (AC, nominal, 80% battery,
    /// lid open) so scenarios only script what they vary; unknown is never
    /// healthy, so a default-unknown simulator would latch safety on step 0.
    ///
    /// Task identity is preserved across ticks within a run: the same id keeps
    /// its first-seen wait/unknown deadlines instead of renewing them per tick.
    public func run(scenario: SimulationScenario, config: Configuration) -> SimulationResult {
        let monitor = HealthMonitor()
        var cpu = CPUObserver()
        var safety = SafetyPolicy()
        // Defaults are valid by construction; force-unwrap cannot fail.
        var session = try! ProtectionSession(
            id: "sim-session", requestedMode: .auto, armedClosedLid: true,
            startedAtMonotonic: fakeNow,
            capDeadlineMonotonic: fakeNow + Double(config.runCapMinutes) * 60
        )
        var transitions: [SimulationTransition] = []
        var firstDeadlines: [String: (wait: Double?, unknown: Double?)] = [:]
        for (index, step) in scenario.steps.sorted(by: { $0.at < $1.at }).enumerated() {
            let now = fakeNow + step.at
            let (snapshot, _) = monitor.snapshot(from: step.readings(base: fakeNow), now: now)
            let cpuEval = cpu.evaluate(
                cpuPercent: snapshot.cpuPercent,
                cpuStopEnabled: config.cpuStopEnabled, now: now)
            let signal = safety.evaluate(
                health: snapshot, config: config, cpuStop: cpuEval.stop, now: now)
            let tasks = step.tasksPreservingIdentity(
                stepIndex: index, base: fakeNow, firstDeadlines: &firstDeadlines)
            let decision = PolicyEngine.evaluate(
                session: session, tasks: tasks,
                health: snapshot, config: config, armed: step.armed ?? true,
                safety: signal, recoveryConflict: step.recoveryConflict ?? false,
                nowMonotonic: now)
            session = decision.session
            transitions.append(SimulationTransition(at: step.at, state: decision.state, reasons: decision.reasons))
        }
        return SimulationResult(scenarioName: scenario.name, transitions: transitions, simulated: true)
    }

    /// Fixture-matrix run (F13). Applies the fixture config, preserves task
    /// identity across ticks (same id keeps first-seen deadlines), honors an
    /// optional absolute `capDeadlineAt`, and asserts `expect`/`expectReasons`
    /// per step. Injected `safety[]` is used verbatim when non-empty (per
    /// fixtures README); otherwise safety is derived from sensors.
    public func runFixture(_ fixture: FixtureFile) -> FixtureRunResult {
        let config = (try? fixture.config.makeConfiguration()) ?? (try! Configuration())
        let capDeadline: Double
        if let capAt = fixture.capDeadlineAt {
            capDeadline = fakeNow + capAt
        } else {
            capDeadline = fakeNow + Double(config.runCapMinutes) * 60
        }
        var session = try! ProtectionSession(
            id: "sim-session", requestedMode: .auto, armedClosedLid: true,
            startedAtMonotonic: fakeNow, capDeadlineMonotonic: capDeadline)
        let monitor = HealthMonitor()
        var cpu = CPUObserver()
        var safetyPolicy = SafetyPolicy()
        var firstDeadlines: [String: (wait: Double?, unknown: Double?)] = [:]
        var results: [FixtureStepResult] = []
        for step in fixture.steps.sorted(by: { $0.at < $1.at }) {
            let now = fakeNow + step.at
            let readings = step.sensors.sensorReadings(at: now)
            let (snapshot, _) = monitor.snapshot(from: readings, now: now)
            let cpuEval = cpu.evaluate(
                cpuPercent: snapshot.cpuPercent,
                cpuStopEnabled: config.cpuStopEnabled, now: now)
            let signal: SafetySignal
            if !step.safety.isEmpty {
                signal = SafetySignal(reasons: step.safety)
            } else {
                signal = safetyPolicy.evaluate(
                    health: snapshot, config: config, cpuStop: cpuEval.stop, now: now)
            }
            let tasks = fixtureTasks(
                step.tasks, firstDeadlines: &firstDeadlines)
            let decision = PolicyEngine.evaluate(
                session: session, tasks: tasks, health: snapshot, config: config,
                armed: true, safety: signal, recoveryConflict: false,
                nowMonotonic: now)
            session = decision.session
            let actual = decision.state.rawValue
            var passed = (actual == step.expect)
            if let expectedReasons = step.expectReasons, passed {
                let actualSet = Set(decision.reasons)
                for want in expectedReasons where !actualSet.contains(want) {
                    passed = false
                    break
                }
            }
            results.append(FixtureStepResult(
                at: step.at, expected: step.expect, actual: actual,
                expectedReasons: step.expectReasons ?? [],
                actualReasons: decision.reasons, passed: passed))
        }
        let overall = results.allSatisfy(\.passed)
        return FixtureRunResult(
            fixtureName: fixture.fixture, steps: results,
            passed: overall, simulated: true)
    }

    private func fixtureTasks(
        _ specs: [FixtureTask],
        firstDeadlines: inout [String: (wait: Double?, unknown: Double?)]
    ) -> [AgentTask] {
        specs.compactMap { spec in
            let stored: (wait: Double?, unknown: Double?)
            if let seen = firstDeadlines[spec.id] {
                stored = seen
            } else {
                stored = (spec.waitUntil, spec.unknownUntil)
                firstDeadlines[spec.id] = stored
            }
            let state = TaskState(rawValue: spec.state) ?? .unknown
            let kind = EvidenceKind(rawValue: spec.kind) ?? .lifecycle
            return try? AgentTask(
                id: spec.id, sessionID: "sim-session", runID: "sim-run",
                state: state, evidenceKind: kind, confidence: .exact,
                waitUntilMonotonic: stored.wait,
                unknownUntilMonotonic: stored.unknown)
        }
    }
}

/// Decodable scenario envelope so JSON fixtures can decode to it later.
public struct SimulationScenario: Sendable, Codable, Equatable {
    public var name: String
    public var steps: [SimulationStep]

    public init(name: String, steps: [SimulationStep]) {
        self.name = name
        self.steps = steps
    }
}

/// One scripted step. `at` is seconds after the simulator's fake origin.
/// Sensor fields left nil mean healthy (see `Simulator.run`); `taskStates`
/// holds `TaskState` raw values (invalid strings become `.unknown`).
/// `armed` defaults to true, `recoveryConflict` to false.
public struct SimulationStep: Sendable, Codable, Equatable {
    public var at: Double
    public var batteryPercent: Double?
    public var powerSource: PowerSource?
    public var thermalPressure: ThermalPressure?
    public var cpuPercent: Double?
    public var lidState: LidState?
    public var taskStates: [String]?
    public var armed: Bool?
    public var recoveryConflict: Bool?

    public init(
        at: Double, batteryPercent: Double? = nil, powerSource: PowerSource? = nil,
        thermalPressure: ThermalPressure? = nil, cpuPercent: Double? = nil,
        lidState: LidState? = nil, taskStates: [String]? = nil,
        armed: Bool? = nil, recoveryConflict: Bool? = nil
    ) {
        self.at = at
        self.batteryPercent = batteryPercent
        self.powerSource = powerSource
        self.thermalPressure = thermalPressure
        self.cpuPercent = cpuPercent
        self.lidState = lidState
        self.taskStates = taskStates
        self.armed = armed
        self.recoveryConflict = recoveryConflict
    }

    func readings(base: Double) -> SensorReadings {
        SensorReadings(
            batteryPercent: batteryPercent ?? 80,
            powerSource: powerSource ?? .ac,
            thermalPressure: thermalPressure ?? .nominal,
            cpuPercent: cpuPercent ?? 10,
            lidState: lidState ?? .open,
            internalDisplayState: .awake,
            measuredAtMonotonic: base + at)
    }

    func tasks(stepIndex: Int, base: Double) -> [AgentTask] {
        var firstDeadlines: [String: (wait: Double?, unknown: Double?)] = [:]
        return tasksPreservingIdentity(
            stepIndex: stepIndex, base: base, firstDeadlines: &firstDeadlines)
    }

    func tasksPreservingIdentity(
        stepIndex: Int, base: Double,
        firstDeadlines: inout [String: (wait: Double?, unknown: Double?)]
    ) -> [AgentTask] {
        (taskStates ?? ["working"]).enumerated().compactMap { offset, raw in
            let id = "sim-task-\(offset)"
            let state = TaskState(rawValue: raw) ?? .unknown
            let freshWait = base + at + 300.0
            let freshUnknown = base + at + 120.0
            let stored: (wait: Double?, unknown: Double?)
            if let seen = firstDeadlines[id] {
                stored = seen
            } else {
                stored = (freshWait, freshUnknown)
                firstDeadlines[id] = stored
            }
            return try? AgentTask(
                id: id, sessionID: "sim-session", runID: "sim-run-\(stepIndex)",
                state: state, evidenceKind: .lifecycle, confidence: .exact,
                waitUntilMonotonic: stored.wait, unknownUntilMonotonic: stored.unknown)
        }
    }
}

public struct SimulationTransition: Sendable, Codable, Equatable {
    public var at: Double
    public var state: EffectiveState
    public var reasons: [String]
}

public struct SimulationResult: Sendable, Codable, Equatable {
    public var scenarioName: String
    public var transitions: [SimulationTransition]
    /// Always true. Marks output as simulated; never host-observed.
    public var simulated: Bool
}

public struct FixtureStepResult: Sendable, Codable, Equatable {
    public var at: Double
    public var expected: String
    public var actual: String
    public var expectedReasons: [String]
    public var actualReasons: [String]
    public var passed: Bool
}

public struct FixtureRunResult: Sendable, Codable, Equatable {
    public var fixtureName: String
    public var steps: [FixtureStepResult]
    public var passed: Bool
    /// Always true. Marks output as simulated; never host-observed.
    public var simulated: Bool
}
