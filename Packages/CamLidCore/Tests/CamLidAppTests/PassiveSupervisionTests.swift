import Foundation
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

@Suite("Passive supervision", .serialized)
struct PassiveSupervisionTests {
    private func observation(_ id: String, state: TaskState, sequence: Int) throws -> NormalizedEvent {
        try NormalizedEvent(provider: "orca", sessionID: id, runID: "main", state: state,
            evidenceKind: .lifecycle, confidence: .inferred, sequence: sequence,
            receivedMonotonic: ContinuousTime.now)
    }
    @Test @MainActor func unselectedObservationIsVisibleButCannotDelaySleep() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        try app.receiveObservation(observation("passive-a", state: .working, sequence: 0))
        #expect(app.sleepRelevantTasks(now: ContinuousTime.now).isEmpty)
        let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.status, payload: Data()))
        let status = try #require(JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as? [String: Any])
        let badges = try #require(status["agentDetection"] as? [[String: Any]])
        let orca = try #require(badges.first { $0["provider"] as? String == "orca" })
        #expect(orca["observedState"] as? String == "Active")
        #expect(orca["detectionEnabled"] as? Bool == false)
        #expect(status["powerActuation"] as? Bool == false)
        var patch = ConfigPatch(); patch.adapterEnrollment = ["orca"]
        guard case .saved(let revision) = app.applySettingsPatch(patch, expectedRevision: 1) else {
            Issue.record("Could not select Orca"); return
        }
        #expect(app.sleepRelevantTasks(now: ContinuousTime.now).count == 1)
        patch.adapterEnrollment = []
        guard case .saved = app.applySettingsPatch(patch, expectedRevision: revision) else {
            Issue.record("Could not ignore Orca"); return
        }
        #expect(app.sleepRelevantTasks(now: ContinuousTime.now).isEmpty)
        #expect(AgentBadgeState(provider: "orca", enabled: false, tasks: [try AgentTask(id: "a", sessionID: "s", runID: "r", state: .working, evidenceKind: .lifecycle, confidence: .exact)]).isDetected)
    }

    @Test @MainActor func parallelPassivePanesAndMissingSnapshotNeverInventCompletion() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        var patch = ConfigPatch(); patch.adapterEnrollment = ["orca"]
        guard case .saved = app.applySettingsPatch(patch, expectedRevision: 1) else {
            Issue.record("Could not select Orca"); return
        }
        for id in ["a", "b"] { try app.receiveObservation(observation(id, state: .working, sequence: 0)) }
        try app.receiveObservation(observation("a", state: .idle, sequence: 1))
        let now = ContinuousTime.now
        #expect(app.sleepRelevantTasks(now: now).filter { $0.state == .working }.count == 1)
        // No further observation: stale work degrades, never completes.
        let stale = app.sleepRelevantTasks(now: now + 16)
        #expect(stale.contains { $0.state == .unknown })
        #expect(!stale.contains { $0.state == .completed })
    }
}
