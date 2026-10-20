import Foundation
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

@Suite("External completion evidence", .serialized)
struct CompletionObservationGuardTests {
    @MainActor private func sleepDecision(_ app: AppCoordinator) throws -> GuardedSleepDecision {
        let payload = try JSONEncoder().encode(CLIOptions(flags: ["dry-run": "true"]))
        let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.sleep, payload: payload))
        let decision = try JSONDecoder().decode(GuardedSleepDecision.self, from: Data(reply.json.utf8))
        #expect(reply.exitCode == 3 && !decision.eligible)
        #expect(decision.blockers.contains("previewOnly"))
        return decision
    }

    @Test(arguments: ["working", "waiting", "idle", "unknown", "empty", "legacyOff"])
    @MainActor func unqualifiedOrcaCoverageCannotAuthorizeCompletion(_ kind: String) throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        var patch = ConfigPatch()
        patch.adapterEnrollment = ["orca"]
        patch.orcaMetadataConsent = kind != "legacyOff"
        guard case .saved = app.applySettingsPatch(patch, expectedRevision: 1) else {
            Issue.record("Could not select Orca source"); return
        }
        app.receiveProcessSnapshot([], complete: true, observedAt: ContinuousTime.now)
        let now = ContinuousTime.now
        let rows: [OrcaUIStatus] = kind == "empty" ? []
            : [OrcaUIStatus(id: "meta-fixture", state: kind == "legacyOff" ? .idle : try #require(OrcaUIState(rawValue: kind)))]
        app.receiveOrcaMetadataSnapshot(OrcaMetadataSnapshot(statuses: rows, queryStartedAt: now, receivedAt: now))
        #expect(try sleepDecision(app).blockers.contains("workUnknown"))
    }

    @Test @MainActor func unselectedOrcaDoesNotOverrideSelectedCompleteAbsence() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        var patch = ConfigPatch(); patch.adapterEnrollment = ["codex"]
        guard case .saved = app.applySettingsPatch(patch, expectedRevision: 1) else {
            Issue.record("Could not select Codex"); return
        }
        app.receiveProcessSnapshot([], complete: true, observedAt: ContinuousTime.now)
        let now = ContinuousTime.now
        app.receiveOrcaMetadataSnapshot(OrcaMetadataSnapshot(
            statuses: [OrcaUIStatus(id: "meta-unselected", state: .idle)], queryStartedAt: now, receivedAt: now))
        #expect(try !sleepDecision(app).blockers.contains("workUnknown"))
    }

    @Test @MainActor func positiveProcessPresenceAndInactiveRowDoNotProveCompletion() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        var patch = ConfigPatch(); patch.adapterEnrollment = ["codex"]
        guard case .saved = app.applySettingsPatch(patch, expectedRevision: 1) else {
            Issue.record("Could not select Codex"); return
        }
        let now = ContinuousTime.now
        let record = try ProcessRecord(identity: ProcessIdentity(pid: 101, startTime: 1),
            executableName: "codex", lastSeenMonotonic: now)
        let candidates = ProcessDiscovery(provider: InMemoryProcessList(records: [record]),
            patterns: [CandidatePattern(executableContains: "codex", provider: "codex")]).discover()
        app.receiveProcessSnapshot(candidates, complete: true, observedAt: ContinuousTime.now)
        // Direct inert receiver fixture only, not an authorized provider ingress or real idle classification.
        try app.receiveObservation(NormalizedEvent(provider: "codex", sessionID: "fixture", runID: "main",
            state: .idle, evidenceKind: .lifecycle, confidence: .inferred, sequence: 0,
            receivedMonotonic: ContinuousTime.now))
        #expect(try sleepDecision(app).blockers.contains("workUnknown"))
    }
}
