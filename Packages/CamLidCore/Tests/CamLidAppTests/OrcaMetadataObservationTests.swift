import Foundation
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

@Suite("Read-only Orca metadata source", .serialized) struct OrcaMetadataObservationTests {
    @Test func detectOrcaAloneControlsSourceIncludingLegacyPreferences() throws {
        #expect(try !Configuration().orcaMetadataAllowed)
        for legacy in [false, true] {
            let enabled = try Configuration(adapterEnrollment: ["orca"], orcaMetadataConsent: legacy)
            #expect(enabled.orcaMetadataAllowed)
            #expect(try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(enabled)).orcaMetadataAllowed)
            #expect(try SettingsDraft(configuration: enabled).makeConfiguration().orcaMetadataAllowed)
            let migrated = try Configuration.migrate(from: ["adapterEnrollment": ["orca"], "orcaMetadataConsent": legacy])
            #expect(!migrated.orcaMetadataAllowed && migrated.adapterEnrollment.isEmpty)
            #expect(migrated.orcaMetadataConsent == legacy) // Migration still never silently selects agents.
            let disabled = try enabled.applying(ConfigPatch(jsonDictionary: ["adapterEnrollment": ["codex"]]))
            #expect(!disabled.orcaMetadataAllowed)
            #expect(disabled.orcaMetadataConsent == legacy)
        }
        #expect(try !Configuration(orcaMetadataConsent: true).orcaMetadataAllowed)
        for raw: Any in [1, "true", NSNull()] {
            #expect(throws: ConfigError.self) { try ConfigPatch(jsonDictionary: ["orcaMetadataConsent": raw]) }
        }
    }

    @Test(arguments: ["1.4.224", "1.4.226", "1.4.225", "1.4.227", "1.5.0", "1.4.226-beta", "1.4.226.0", "garbage"])
    func versionNeverGatesSchemaValidPoll(_ version: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cml-meta-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let exe = root.appendingPathComponent("fixture")
        let marker = root.appendingPathComponent("executed")
        let script = """
        #!/bin/sh
        touch '\(marker.path)'
        test -z "$ORCA_ENVIRONMENT$ORCA_SESSION_ID$NODE_OPTIONS" || exit 9
        if [ "$1" = status ]; then
          printf '%s' '{"ok":true,"result":{"target":{"kind":"local"},"runtime":{"appVersion":"\(version)","reachable":true,"runtimeId":"fixture-runtime"}}}'
        else
          test "$1 $2 $3 $4 $5" = 'worktree ps --limit 20 --json' || exit 9
          printf '%s' '{"ok":true,"_meta":{"runtimeId":"fixture-runtime"},"result":{"truncated":false,"worktrees":[{"hostId":"local","agents":[{"paneKey":"raw-pane-private","state":"working","prompt":"FIXTURE_PRIVATE","lastAssistantMessage":"FIXTURE_PRIVATE","toolInput":"FIXTURE_PRIVATE"}]}]}}'
        fi
        """
        try Data(script.utf8).write(to: exe, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: exe.path)
        let poller = OrcaPoller(executable: exe)
        #expect(throws: IPCError.policyDenied("orcaMetadataConsentRequired")) { try poller.poll() }
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        // Version-agnostic: every version above decodes once the schema holds.
        let snapshot = try poller.snapshot(consent: true, clock: { 1 })
        #expect(snapshot.statuses.count == 1 && snapshot.statuses[0].state == .working)
        #expect(snapshot.statuses[0].id.hasPrefix("meta-") && !snapshot.statuses[0].id.contains("private"))
        #expect(!String(describing: snapshot).contains("FIXTURE_PRIVATE"))
    }

    @Test(arguments: ["duplicate", "emptyIdentity", "unconfirmed", "interrupted", "unknownState"])
    func invalidOrUnconfirmedRowsCannotInventIdle(_ kind: String) throws {
        let status = OrcaPollerTests().status
        let key = kind == "emptyIdentity" ? "" : "pane"
        let state = kind == "unknownState" ? "not-a-state" : "done"
        var row: [String: Any] = ["paneKey": key, "state": state]
        if kind == "unconfirmed" { row["restoredUnconfirmed"] = true }
        if kind == "interrupted" { row["interrupted"] = true }
        let bytes = try JSONSerialization.data(withJSONObject: ["ok": true, "_meta": ["runtimeId": "test"], "result": ["truncated": false, "worktrees": [["hostId": "local", "agents": kind == "duplicate" ? [row, row] : [row]]]]])
        if ["duplicate", "emptyIdentity"].contains(kind) {
            #expect(throws: OrcaPollError.self) { try OrcaPoller.decode(status: status, worktrees: bytes) }
        } else {
            let rows = try OrcaPoller.decode(status: status, worktrees: bytes)
            #expect(rows.first?.agentState != "idle")
        }
    }

    @Test @MainActor func freshParallelCountsRevokeLateReplyAndStaleIdle() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        var patch = ConfigPatch(); patch.adapterEnrollment = ["orca"]
        guard case .saved = app.applySettingsPatch(patch, expectedRevision: 1) else { Issue.record("Consent failed"); return }
        func snapshot(_ statuses: [OrcaUIStatus], age: Double = 0) -> OrcaMetadataSnapshot {
            let now = ContinuousTime.now - age
            return OrcaMetadataSnapshot(statuses: statuses, queryStartedAt: now, receivedAt: now)
        }
        func badge() throws -> [String: Any] {
            let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.status, payload: Data()))
            let object = try #require(JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as? [String: Any])
            #expect(object["powerActuation"] as? Bool == false)
            let meta = try #require(object["orcaMetadataObservation"] as? [String: Any])
            #expect(meta["completionCoverageQualified"] as? Bool == false && meta["sourceStateFreshness"] as? String == "unverified")
            let badges = try #require(object["agentDetection"] as? [[String: Any]])
            return try #require(badges.first { $0["provider"] as? String == "orca" })
        }
        app.receiveOrcaMetadataSnapshot(snapshot([OrcaUIStatus(id: "meta-one", state: .working), OrcaUIStatus(id: "meta-two", state: .working)]))
        #expect(try badge()["workingCount"] as? Int == 2)
        app.receiveOrcaMetadataSnapshot(snapshot([OrcaUIStatus(id: "meta-one", state: .idle), OrcaUIStatus(id: "meta-two", state: .working)]))
        #expect(try badge()["workingCount"] as? Int == 1)
        app.receiveOrcaMetadataSnapshot(snapshot([OrcaUIStatus(id: "meta-one", state: .idle)], age: 16))
        let staleBadge = try badge()
        #expect(staleBadge["workingCount"] as? Int == 0)
        #expect(staleBadge["unknownCount"] as? Int == 1)
        #expect(staleBadge["observedState"] as? String == "Unknown")
        app.receiveOrcaMetadataSnapshot(snapshot([OrcaUIStatus(id: "meta-one", state: .working), OrcaUIStatus(id: "meta-two", state: .working)]))
        #expect(try badge()["workingCount"] as? Int == 2)
        patch.adapterEnrollment = []
        guard case .saved = app.applySettingsPatch(patch, expectedRevision: 2) else { Issue.record("Revoke failed"); return }
        app.receiveOrcaMetadataSnapshot(snapshot([OrcaUIStatus(id: "meta-one", state: .working)]))
        #expect(try badge()["workingCount"] as? Int == 0)
    }

    @Test @MainActor func mixedSessionsStayIndependentAcrossTransitionsAndDetect() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        var selection = ConfigPatch(); selection.adapterEnrollment = ["orca"]
        guard case .saved = app.applySettingsPatch(selection, expectedRevision: 1) else {
            Issue.record("Could not select Orca"); return
        }
        func receive(_ states: [(String, OrcaUIState)]) {
            let now = ContinuousTime.now
            app.receiveOrcaMetadataSnapshot(OrcaMetadataSnapshot(
                statuses: states.map { OrcaUIStatus(id: $0.0, state: $0.1) }, queryStartedAt: now, receivedAt: now))
        }
        func counts(_ working: Int, _ waiting: Int) throws {
            let data = app.dashboardData()
            let badge = try #require(data.agents.first { $0.provider == "orca" })
            #expect(badge.workingCount == working && badge.waitingCount == waiting)
            #expect(data.workingAgents.count == (working > 0 ? 1 : 0))
            #expect(data.waitingAgents.count == (working == 0 && waiting > 0 ? 1 : 0))
        }
        receive([("one", .working), ("two", .waiting), ("three", .idle)])
        try counts(1, 1)
        receive([("one", .idle), ("two", .waiting), ("three", .idle)])
        try counts(0, 1) // Finishing one session must not hide another waiting session.
        receive([("one", .working), ("two", .working), ("three", .idle)])
        try counts(2, 0)
        receive([("one", .waiting), ("two", .working), ("three", .idle)])
        try counts(1, 1)
        selection.adapterEnrollment = []
        guard case .saved = app.applySettingsPatch(selection, expectedRevision: 2) else {
            Issue.record("Could not disable Orca"); return
        }
        receive([("one", .working), ("two", .waiting)])
        try counts(0, 0)
        #expect(!app.dashboardData().hasEnabledAgents)
        selection.adapterEnrollment = ["orca"]
        guard case .saved = app.applySettingsPatch(selection, expectedRevision: 3) else {
            Issue.record("Could not re-enable Orca"); return
        }
        try counts(0, 0) // Enabling Detect must not resurrect the pre-disable counts.
        receive([("one", .working), ("two", .waiting), ("three", .idle)])
        try counts(1, 1)
    }

    @Test @MainActor func duplicateParallelSnapshotInvalidatesAllCountsInsteadOfInventingIdle() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        var selection = ConfigPatch(); selection.adapterEnrollment = ["orca"]
        guard case .saved = app.applySettingsPatch(selection, expectedRevision: 1) else {
            Issue.record("Could not select Orca"); return
        }
        func receive(_ rows: [OrcaUIStatus]) {
            let now = ContinuousTime.now
            app.receiveOrcaMetadataSnapshot(OrcaMetadataSnapshot(statuses: rows, queryStartedAt: now, receivedAt: now))
        }
        receive([OrcaUIStatus(id: "one", state: .working), OrcaUIStatus(id: "two", state: .waiting)])
        receive([OrcaUIStatus(id: "one", state: .idle), OrcaUIStatus(id: "one", state: .idle)])
        let badge = try #require(app.dashboardData().agents.first { $0.provider == "orca" })
        #expect(badge.workingCount == 0 && badge.waitingCount == 0 && badge.unknownCount == 2)
        #expect(badge.observedState == "Unknown")
    }

    @Test @MainActor func detectSwitchUsesRevisionedCommitAndKeepsWriteFailure() throws {
        let editor = SettingsEditor(configuration: try Configuration(), revision: 1, section: .agents)
        editor.configureAutosave { patch, revision in
            #expect(patch.adapterEnrollment == ["orca"] && revision == 1)
            return .failed("fixtureFailure")
        }
        editor.setProvider("orca", enabled: true)
        #expect(editor.message != nil && editor.isDirty)
    }
}
