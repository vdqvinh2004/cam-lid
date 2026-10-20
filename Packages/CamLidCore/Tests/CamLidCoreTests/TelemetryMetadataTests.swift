import Foundation
import Testing
@testable import CamLidCore

struct TelemetryMetadataTests {
    @Test func infiniteHasNoExpiryButBatteryThermalAndLatchStillStop() throws {
        let config = try Configuration(mode: .timed, runCapMinutes: 5, timerMinutes: 0, adapterEnrollment: ["orca"])
        let healthy = try HealthSnapshot(batteryPercent: 80, powerSource: .ac, thermalPressure: .nominal, lidState: .open)
        let session = try ProtectionSession(id: "infinite", requestedMode: .timed, armedClosedLid: false, startedAtMonotonic: 0, capDeadlineMonotonic: nil)
        let restored = try JSONDecoder().decode(ProtectionSession.self, from: JSONEncoder().encode(session))
        let decision = PolicyEngine.evaluate(session: restored, tasks: [], health: healthy, config: config, armed: true,
            safety: .clear, recoveryConflict: false, nowMonotonic: 10_000_000)
        #expect(decision.state == .protected && decision.session.capDeadlineMonotonic == nil)
        for danger in [try HealthSnapshot(batteryPercent: 10, powerSource: .ac, thermalPressure: .nominal, lidState: .open),
                       try HealthSnapshot(batteryPercent: 80, powerSource: .ac, thermalPressure: .critical, lidState: .open)] {
            var safety = SafetyPolicy()
            let signal = safety.evaluate(health: danger, config: config, cpuStop: false, now: 10_000_000)
            let stopped = PolicyEngine.evaluate(session: restored, tasks: [], health: danger, config: config, armed: true,
                safety: signal, recoveryConflict: false, nowMonotonic: 10_000_000)
            #expect(stopped.state == .safetyStopped && stopped.session.latchedSafetyStop)
            #expect(PolicyEngine.evaluate(session: stopped.session, tasks: [], health: healthy, config: config, armed: true,
                safety: .clear, recoveryConflict: false, nowMonotonic: 10_000_001).state == .safetyStopped)
        }
        #expect(throws: ValidationError.self) {
            try ProtectionSession(id: "auto", requestedMode: .auto, armedClosedLid: false, startedAtMonotonic: 0, capDeadlineMonotonic: nil)
        }
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as! [String: Any]
        legacy.removeValue(forKey: "timerMinutes")
        let decoded = try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.adapterEnrollment == ["orca"] && decoded.timedDurationMinutes == 5)
        #expect(throws: ConfigError.self) { try Configuration(timerMinutes: -1) }
        #expect(throws: ConfigError.self) { try ConfigPatch(jsonDictionary: ["timerMinutes": true]) }
    }
    @Test func sessionDeadlinesAndDecodedBoundsRejectUnsafeValues() throws {
        for deadline in [-1.0, Double.infinity, Double.nan] {
            #expect(throws: ValidationError.self) {
                try ProtectionSession(id: "s", requestedMode: .manual, armedClosedLid: false,
                    startedAtMonotonic: 0, capDeadlineMonotonic: deadline)
            }
        }
        #expect(throws: ValidationError.self) {
            try ProtectionSession(id: "s", requestedMode: .manual, armedClosedLid: false,
                startedAtMonotonic: 20, capDeadlineMonotonic: 10)
        }
        let valid = try ProtectionSession(id: "s", requestedMode: .manual, armedClosedLid: false,
            startedAtMonotonic: 0, capDeadlineMonotonic: 10)
        let original = try JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as! [String: Any]
        for patch: [String: Any] in [["stateRevision": -1], ["graceDeadlineMonotonic": -1],
                                   ["taskIDs": (0..<21).map { "task-\($0)" }]] {
            let object = original.merging(patch) { _, newer in newer }
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(ProtectionSession.self, from: JSONSerialization.data(withJSONObject: object))
            }
        }
    }
    @Test func namedTemperatureAgeIsIndependentOfLidAndPressure() throws {
        let temperature = TemperatureObservation(valueCelsius: 42.5, sensorID: "test-soc", displayName: "Test SoC", source: "isolated-test", sampledAtMonotonic: 10, availability: "available", reasonCode: nil)
        let readings = SensorReadings(thermalPressure: .critical, measuredAtMonotonic: 21,
            lidObservation: LidObservation(state: .closed, sampledAtMonotonic: 20), temperature: temperature)
        let snapshot = HealthMonitor().snapshot(from: readings, now: 21).snapshot
        #expect(snapshot.temperature.availability == "stale" && snapshot.temperature.valueCelsius == nil)
        #expect(snapshot.lidState == .closed && snapshot.thermalPressure == .critical)
    }
    @Test func freshCriticalPressureSurvivesHungOtherSources() {
        let readings = SensorReadings(batteryPercent: 100, powerSource: .ac, thermalPressure: .critical,
            measuredAtMonotonic: 0, criticalThermalSampledAtMonotonic: 99.5)
        let snapshot = HealthMonitor().snapshot(from: readings, now: 100).snapshot
        #expect(snapshot.batteryPercent == nil && snapshot.powerSource == .unknown)
        #expect(snapshot.thermalPressure == .critical)
        #expect(HealthMonitor().snapshot(from: readings, now: 101).snapshot.thermalPressure == .unknown)
    }
    @Test func temperatureLegacyNullRoundTripAndInvalidValues() throws {
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try HealthSnapshot())) as! [String: Any]
        legacy.removeValue(forKey: "temperature")
        #expect(try JSONDecoder().decode(HealthSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy)).temperature == .unsupported)
        legacy["temperature"] = NSNull()
        #expect(try JSONDecoder().decode(HealthSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy)).temperature == .unsupported)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TemperatureObservation.unsupported)) as! [String: Any]
        #expect(json["valueCelsius"] is NSNull && json["sampledAtMonotonic"] is NSNull)
        var invalid = json; invalid["availability"] = "available"; invalid["valueCelsius"] = 42
        #expect(throws: (any Error).self) { try JSONDecoder().decode(TemperatureObservation.self, from: JSONSerialization.data(withJSONObject: invalid)) }
        #expect(TemperatureObservation(valueCelsius: .nan, availability: "available").availability == "error")
    }
    @Test func typedLidCannotContradictLegacyState() throws {
        let snapshot = try HealthSnapshot(lidState: .open, lid: LidObservation(state: .closed, sampledAtMonotonic: 20))
        #expect(snapshot.lidState == .closed)
    }
    @Test func invalidTaskDeadlinesNeverDecodeOrHold() throws {
        for deadline in [-1.0, Double.infinity, Double.nan] {
            #expect(throws: ValidationError.self) {
                try AgentTask(id: "t", sessionID: "s", runID: "r", state: .unknown, evidenceKind: .lifecycle,
                    confidence: .unknown, unknownUntilMonotonic: deadline)
            }
        }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(AgentTask.self, from: Data(#"{"id":"t","sessionID":"s","runID":"r","state":"waiting","evidenceKind":"lifecycle","confidence":"exact","waitUntilMonotonic":-1}"#.utf8))
        }
    }
    @Test func jsonBooleanIntegerCoercionAndUnboundedEnrollmentReject() throws {
        let boolAsInt = try JSONSerialization.jsonObject(with: Data(#"{"completionDelayMinutes":true}"#.utf8)) as! [String: Any]
        let intAsBool = try JSONSerialization.jsonObject(with: Data(#"{"chargingOnly":1}"#.utf8)) as! [String: Any]
        #expect(throws: ConfigError.self) { try ConfigPatch(jsonDictionary: boolAsInt) }
        #expect(throws: ConfigError.self) { try ConfigPatch(jsonDictionary: intAsBool) }
        #expect(throws: ConfigError.self) { try Configuration(adapterEnrollment: (0..<21).map { "provider-\($0)" }) }
    }

    @Test func unavailableLidCanNeverProjectKnownState() {
        for availability in ["error", "stale", "unsupported", "permissionRequired", "invalid"] {
            let source = LidObservation(state: .open, sampledAtMonotonic: 100, availability: availability)
            #expect(source.projected(now: 100).state == .unknown)
        }
        #expect(LidObservation(state: .open, sampledAtMonotonic: .nan).state == .unknown)
        #expect(LidObservation(state: .open).state == .unknown)
    }

}
