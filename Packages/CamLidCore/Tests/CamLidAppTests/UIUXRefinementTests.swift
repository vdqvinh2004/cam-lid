import AppKit
import Foundation
import Testing
import CamLidCore
@testable import CamLidApp

@Suite("QA UI/UX refinement", .serialized)
struct UIUXRefinementTests {
    @Test func historyReadKeepsRowsRejectsLateRepliesAndPreservesFailure() throws {
        let record = try StoredTransition(stateRevision: 0, category: .configuration,
            newState: .off, reasonCodes: ["configApplied"])
        var snapshot = ActivitySnapshot()
        #expect(snapshot.isLoading && snapshot.records.isEmpty)
        let first = UUID(), second = UUID(), third = UUID()
        snapshot.beginRead(first)
        let initial = snapshot.completeRead(first, records: [record], error: nil, outcome: nil)
        #expect(initial)
        snapshot.beginRead(second)
        #expect(snapshot.isLoading && snapshot.records.map(\.id) == [record.id])
        snapshot.beginRead(third)
        let stale = snapshot.completeRead(second, records: [], error: nil, outcome: "stale")
        #expect(!stale)
        #expect(snapshot.isLoading && snapshot.outcome == nil)
        let failure = snapshot.completeRead(third, records: [], error: "Read timed out", outcome: nil)
        #expect(failure)
        #expect(!snapshot.isLoading && snapshot.error != nil && snapshot.records.map(\.id) == [record.id])
        let duplicate = snapshot.completeRead(third, records: [], error: nil, outcome: nil)
        #expect(!duplicate)
        let retry = UUID(); snapshot.beginRead(retry)
        let retried = snapshot.completeRead(retry, records: [], error: nil, outcome: nil)
        #expect(retried)
        #expect(snapshot.records.isEmpty && snapshot.error == nil && !snapshot.isLoading)
    }

    @Test func ignoredWorkAndUnknownEvidenceDoNotBecomeKnownIdle() throws {
        let working = try AgentTask(id: "orca/work", sessionID: "work", runID: "run",
            state: .working, evidenceKind: .lifecycle, confidence: .exact)
        let ignored = AgentBadgeState(provider: "orca", enabled: false, tasks: [working])
        let unknown = AgentBadgeState(provider: "codex", enabled: true, tasks: [], processCount: 1)
        #expect(AgentBadgeState.workingSummary([ignored, unknown]) == "No selected agents reporting work")
        #expect(ignored.compactDetail.contains("Active") && unknown.observedState == "Unknown")
        let enabled = AgentBadgeState(provider: "orca", enabled: true, tasks: [working])
        #expect(AgentBadgeState.workingSummary([enabled, unknown]) == "1 selected agent reporting work")
    }

    @Test @MainActor func welcomeReplayPreservesConsentAndRecordsCompletionOnce() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        var patch = ConfigPatch(); patch.closedLidOptIn = true; patch.telemetryEnabled = true
        guard case .saved = await app.applySettingsPatchAsync(patch, expectedRevision: 1) else {
            Issue.record("Could not prepare consent fixture"); return
        }
        #expect(app.finishOnboarding())
        #expect(app.finishOnboarding())
        #expect(await app.flushHistory())
        let records = FileHistoryStorage(directory: fixture.root.appendingPathComponent("history")).load()
        #expect(records.filter { $0.reasonCodes.contains("onboardingComplete") }.count == 1)
        let persisted = try Data(contentsOf: fixture.root.appendingPathComponent("history/preferences.json"))
        let json = try #require(JSONSerialization.jsonObject(with: persisted) as? [String: Any])
        let config = (json["configuration"] as? [String: Any]) ?? json
        #expect(config["closedLidOptIn"] as? Bool == true)
        #expect(config["telemetryEnabled"] as? Bool == true)
    }

    @Test @MainActor func helperMenuUsesProjectedCommandAvailability() throws {
        _ = NSApplication.shared
        let helper = UtilityUICoordinator()
        let start = NSMenuItem(); start.tag = 1
        let stop = NSMenuItem(); stop.tag = 2
        #expect(!helper.validateMenuItem(start) && !helper.validateMenuItem(stop))
        let configuration = try Configuration()
        let protection = ProtectionReadiness(facts: ProtectionReadinessFacts(buildKind: .preview,
            supportRowID: nil, supportRowQualified: false, helperTrusted: false, helperAvailable: false,
            recoveryRequired: false, recoveryJournalReady: false, ownershipEvidence: .unknown,
            matchingGlobalOverrideObserved: false, backendVerified: false, leaseVerified: false,
            safetyQualifying: false, requestedClosedLidIntent: false))
        var state = UtilityUIState(dashboard: DashboardData(state: .ready, reasonText: "", startEnabled: true),
            configuration: configuration, revision: 1, protection: protection, settingsSection: .agents,
            anchorFrame: .zero, installationPending: false)
        helper.update(state)
        #expect(helper.validateMenuItem(start) && !helper.validateMenuItem(stop))
        state.dashboard = DashboardData(state: .completionGrace, reasonText: "", stopEnabled: true)
        helper.update(state)
        #expect(!helper.validateMenuItem(start) && helper.validateMenuItem(stop))
    }

    @Test @MainActor func autoStartUnavailableWithoutSelectedAgent() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        #expect(!app.menuBarAutoAvailable)
        #expect(app.menuBarCanStart)
        var patch = ConfigPatch(); patch.adapterEnrollment = ["orca"]
        guard case .saved = await app.applySettingsPatchAsync(patch, expectedRevision: 1) else {
            Issue.record("Could not enroll agent"); return
        }
        #expect(app.menuBarAutoAvailable)
    }

    @Test func privateRepliesPreserveRequestIdentity() throws {
        let id = UUID()
        for command in [UtilityUICommand.historyLoading(id), .history(id, [], error: nil, outcome: "read"), .onboardingResult(id, false)] {
            let data = try JSONEncoder().encode(command)
            let decoded = try JSONDecoder().decode(UtilityUICommand.self, from: data)
            switch decoded {
            case .historyLoading(let value), .history(let value, _, _, _), .onboardingResult(let value, _): #expect(value == id)
            default: Issue.record("Reply changed kind")
            }
        }
    }

    @Test func routineSensorUpdatesStayOutOfTheDefaultTimeline() throws {
        let lid = try StoredTransition(stateRevision: 0, category: .configuration,
            newState: .off, reasonCodes: ["lidAvailabilityChanged"])
        let temperature = try StoredTransition(stateRevision: 0, category: .configuration,
            newState: .off, reasonCodes: ["temperatureAvailabilityChanged"])
        let settings = try StoredTransition(stateRevision: 0, category: .configuration,
            newState: .off, reasonCodes: ["configApplied"])
        #expect(ActivityPresentation.isRoutineSensorUpdate(lid))
        #expect(ActivityPresentation.isRoutineSensorUpdate(temperature))
        #expect(!ActivityPresentation.isRoutineSensorUpdate(settings))
        #expect(ActivityPresentation.readableReason("appQuitNoOwnedPower") == "CamLid quit without a session")
    }

    @Test @MainActor func updatesUnavailableExplainsThePreviewWithoutImplyingInstallation() throws {
        let snapshot = UpdateSnapshot(phase: .unavailable, reason: "developerIDRequired")
        let view = UpdatesView(snapshot: snapshot, canCheck: false, onCheck: {})
        #expect(view.title == "Updates unavailable")
        #expect(view.detail.contains("release version"))
        #expect(!view.detail.lowercased().contains("install"))
        #expect(view.preferredHeight < 185)
    }

    @Test func updateProjectionCannotEnableInstallation() throws {
        let payload = Data(#"{"phase":"available","reason":"updateAvailable","version":"2.0","installationAvailable":true}"#.utf8)
        let snapshot = try JSONDecoder().decode(UpdateSnapshot.self, from: payload)
        #expect(snapshot.phase == .available && snapshot.version == "2.0")
        #expect(!snapshot.installationAvailable)
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        #expect(encoded["installationAvailable"] as? Bool == false)
    }
}
