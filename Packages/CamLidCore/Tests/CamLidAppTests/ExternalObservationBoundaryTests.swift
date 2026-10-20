import Foundation
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

@Suite("Third-person receiver boundary", .serialized)
struct ExternalObservationBoundaryTests {
    @Test @MainActor func noCompletedProcessScanCannotClaimAbsence() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.status, payload: Data()))
        let object = try #require(JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as? [String: Any])
        let badges = try #require(object["agentDetection"] as? [[String: Any]])
        #expect(badges.count == AgentBadgeState.providers.count)
        #expect(badges.allSatisfy { $0["observedState"] as? String == "Unknown" })
        #expect(badges.allSatisfy { $0["workingCount"] as? Int == 0 })
    }

    @Test(arguments: ["complete", "failed", "stale", "future", "nonfinite"])
    @MainActor func absenceRequiresACompleteCurrentScan(_ kind: String) throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let now = ContinuousTime.now
        let observedAt = kind == "stale" ? now - 16 : kind == "future" ? now + 1 : kind == "nonfinite" ? .nan : now
        app.receiveProcessSnapshot([], complete: kind != "failed", observedAt: observedAt)
        let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.status, payload: Data()))
        let object = try #require(JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as? [String: Any])
        let badges = try #require(object["agentDetection"] as? [[String: Any]])
        let expected = kind == "complete" ? "Not detected" : "Unknown"
        #expect(badges.allSatisfy { $0["observedState"] as? String == expected })
        let limits = try #require(object["agentSourceLimitations"] as? [String: Any])
        #expect(limits["processScanCompleteAndFresh"] as? Bool == (kind == "complete"))
        #expect(limits["providerConnections"] as? Bool == false) // No Detect selection, no Orca query.
        #expect(limits["providerEventsAccepted"] as? Bool == false)
    }

    @Test(arguments: ["partial", "stale", "future", "nonfinite"])
    @MainActor func partialPresenceCountsDoNotClaimWorkOrAbsence(_ kind: String) throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let now = ContinuousTime.now
        let records = try ["codex", "opencode"].enumerated().map { index, name in
            try ProcessRecord(identity: ProcessIdentity(pid: Int32(100 + index), startTime: 1),
                executableName: name, lastSeenMonotonic: now)
        }
        let candidates = ProcessDiscovery(provider: InMemoryProcessList(records: records),
            patterns: [CandidatePattern(executableContains: "codex", provider: "codex"),
                       CandidatePattern(executableContains: "opencode", provider: "opencode")]).discover()
        let observedAt = kind == "stale" ? now - 16 : kind == "future" ? now + 1 : kind == "nonfinite" ? .nan : now
        app.receiveProcessSnapshot(candidates, complete: false, observedAt: observedAt)
        let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.status, payload: Data()))
        let object = try #require(JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as? [String: Any])
        let badges = try #require(object["agentDetection"] as? [[String: Any]])
        for provider in ["codex", "opencode"] {
            let badge = try #require(badges.first { $0["provider"] as? String == provider })
            #expect(badge["processCount"] as? Int == (kind == "partial" ? 1 : 0))
            #expect(badge["observedState"] as? String == "Unknown")
            #expect(badge["workingCount"] as? Int == 0 && badge["waitingCount"] as? Int == 0)
        }
        let limits = try #require(object["agentSourceLimitations"] as? [String: Any])
        #expect(limits["processScanCompleteAndFresh"] as? Bool == false)
        #expect(limits["processPresenceProvesWork"] as? Bool == false)
        #expect(object["powerActuation"] as? Bool == false)
    }

    @Test func metadataConsentRequiredBeforeAnyStatusQuery() {
        #expect(throws: IPCError.policyDenied("orcaMetadataConsentRequired")) {
            try OrcaPoller(executable: URL(fileURLWithPath: "/no/provider/query/allowed")).poll()
        }
    }

    @Test @MainActor func legacyIngressCannotCreateTasksOrToolDiagnostics() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        var patch = ConfigPatch(); patch.adapterEnrollment = AgentBadgeState.providers
        guard case .saved = app.applySettingsPatch(patch, expectedRevision: 1) else {
            Issue.record("Cannot select observed providers"); return
        }
        let event = try NormalizedEvent(provider: "codex", sessionID: "outside", runID: "r",
            state: .working, evidenceKind: .lifecycle, confidence: .exact, sequence: 0,
            receivedMonotonic: ContinuousTime.now)
        let bytes = try JSONEncoder().encode(event)
        let commands: [AllowlistedCommand] = [.event, .agentDiagnostic, .run, .admitCommand, .renewCommand, .finishCommand]
        for command in commands {
            #expect(throws: IPCError.policyDenied("externalObservationOnly")) {
                try app.handleControl(command, payload: bytes)
            }
            await #expect(throws: IPCError.policyDenied("externalObservationOnly")) {
                try await app.handleControlAsync(command, payload: bytes, deadline: ContinuousTime.now + 1)
            }
        }
        let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.status, payload: Data()))
        let status = try #require(JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as? [String: Any])
        #expect((status["tasks"] as? [[String: Any]])?.isEmpty == true)
        #expect(status["toolDiagnostic"] is NSNull)
        #expect(status["powerActuation"] as? Bool == false)
    }
}
