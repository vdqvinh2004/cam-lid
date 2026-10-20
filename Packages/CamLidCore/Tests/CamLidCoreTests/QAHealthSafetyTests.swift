import Testing
import Foundation
@testable import CamLidCore

struct QAHealthSafetyTests {
    @Test func lidFreshnessDoesNotRefreshOtherSources() throws {
        let readings = SensorReadings(batteryPercent: 80, powerSource: .ac, thermalPressure: .nominal,
            cpuPercent: 0, lidState: .open, measuredAtMonotonic: 20,
            lidObservation: LidObservation(state: .closed, sampledAtMonotonic: 10))
        let snapshot = HealthMonitor().snapshot(from: readings, now: 20).snapshot
        #expect(snapshot.batteryPercent == 80 && snapshot.thermalPressure == .nominal)
        #expect(snapshot.lidState == .unknown && snapshot.lid?.availability == "stale")
        var policy = SafetyPolicy()
        #expect(policy.evaluate(health: snapshot, config: try Configuration(), cpuStop: false, now: 20).reasons.contains("lidUnknown"))
    }
    @Test func invalidGlobalTimeCannotProveSafety() {
        for stamp in [-1.0, 101, Double.nan] {
            let readings = SensorReadings(batteryPercent: 100, powerSource: .ac, thermalPressure: .nominal,
                lidState: .open, measuredAtMonotonic: stamp)
            #expect(HealthMonitor().snapshot(from: readings, now: 100).snapshot.thermalPressure == .unknown)
        }
    }
    @Test func criticalPressureBypassesWarmCacheWithUnknownLid() throws {
        var policy = SafetyPolicy()
        let healthy = try HealthSnapshot(batteryPercent: 90, powerSource: .ac, thermalPressure: .nominal, lidState: .open)
        #expect(policy.evaluate(health: healthy, config: try Configuration(), cpuStop: false, now: 100) == .clear)
        let critical = try HealthSnapshot(batteryPercent: 90, powerSource: .ac, thermalPressure: .critical, lidState: .unknown)
        let signal = policy.evaluate(health: critical, config: try Configuration(), cpuStop: false, now: 101)
        #expect(signal.reasons.contains("thermalCritical") && signal.reasons.contains("lidUnknown"))
    }
    @Test func legacyAndNullObservationDecodeButInvalidObservationsFail() throws {
        let raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try HealthSnapshot())) as! [String: Any]
        #expect(try JSONDecoder().decode(HealthSnapshot.self, from: JSONSerialization.data(withJSONObject: raw)).lid == nil)
        var null = raw; null["lid"] = NSNull()
        #expect(try JSONDecoder().decode(HealthSnapshot.self, from: JSONSerialization.data(withJSONObject: null)).lid == nil)
        var bad: [String: Any] = ["state": "closed", "source": "IOPMrootDomain.AppleClamshellState", "availability": "available", "sampledAtMonotonic": -1]
        #expect(throws: (any Error).self) { try JSONDecoder().decode(LidObservation.self, from: JSONSerialization.data(withJSONObject: bad)) }
        bad["sampledAtMonotonic"] = NSNull()
        #expect(throws: (any Error).self) { try JSONDecoder().decode(LidObservation.self, from: JSONSerialization.data(withJSONObject: bad)) }
    }
    @Test func hashedIdentityAndWaitDeadlineSurvivePreferenceChange() throws {
        var store = RuntimeAgentStore(); store.configure(waitRetentionSeconds: 60)
        let event = try NormalizedEvent(provider: "codex", sessionID: String(repeating: "s", count: 100),
            runID: String(repeating: "r", count: 100), state: .waiting, evidenceKind: .lifecycle,
            confidence: .exact, sequence: 0, epoch: 1, receivedMonotonic: 10)
        _ = try store.ingest(JSONEncoder().encode(event), now: 10)
        let task = try #require(store.tasks(provider: "codex", now: 10).first)
        #expect(task.id.hasPrefix("evt-") && store.provider(for: task.id) == "codex")
        let deadline = task.waitUntilMonotonic
        store.configure(waitRetentionSeconds: 1_800)
        #expect(store.tasks(now: 20).first?.waitUntilMonotonic == deadline)
    }
}
